class_name StockBuildEvolution
extends RefCounted

# Owns the (template, role, rarity) -> StockBuild lifecycle - same composed-
# helper shape as TemplateEvolution/ProfileEvolution/BossEvolution
# (constructed with the director, data array lives on the director itself:
# director.stock_builds), but evaluation is checkpoint-driven rather than
# per-death like the other three: a deviation's fitness is tracked as it
# happens (record_deviation_result, called from SquadDirector.
# credit_bot_death), and only actually decided - promote or discard - when
# either MAX_TRACKED_DEVIATIONS accumulates for that key or the player opens
# the Garage (flush_all_pending, see Main.gd's Garage-open hook). Never
# regresses: the best tracked deviation only replaces the current build if
# it actually beats that build's own average fitness.
#
# rarity is part of the key alongside (template_name, role) - base_rarity
# climbs with wave/difficulty progression (SquadDirector._spawn_bot_for_
# role), so a build solved early at COMMON must never get replayed onto a
# much later, much-higher-rarity spawn of the same role/template (see
# StockBuild.gd's own field comment) - that would silently freeze that
# (template, role)'s gear at whatever rarity it first happened to spawn at.

const StockBuild = preload("res://scripts/ai/StockBuild.gd")
const StockBuildMutator = preload("res://scripts/ai/StockBuildMutator.gd")

const MAX_TRACKED_DEVIATIONS = 8
# ~15-20% of spawns for a (template, role, rarity) that already has a stock
# build test a fresh deviation instead of replaying it.
const DEVIATION_TEST_RATE = 0.175
# Promotion gate (per the user: "anything that does better than the current
# best in X out of Y sessions gets promoted to the new best template") -
# a deviation must beat the current build's fitness in at least this
# fraction of the tracked batch, not just once via a single lucky outlier,
# before it's trusted to replace the champion.
const PROMOTION_WIN_RATE = 0.5
# Same-role squad-mates get independently-tracked builds up to this many
# slots (0-based, clamped) - bounds the key-space multiplier per (template,
# role, rarity) since role counts themselves cap at 4 (SquadTemplateMutator.
# mutate's bump op), and the common case (one of a role per squad) sees no
# change at all - slot is always 0. See SquadDirector._assemble_squad for
# where the slot index gets assigned at spawn time.
const MAX_SUB_ARCHETYPE_SLOTS = 3

var director

# key ("<template_name>:<role>:<rarity>") -> Array[{"components": Dictionary, "fitness": float}]
# In-memory only between flushes - not persisted per-entry, only the winning
# promotion (or nothing, if none beat the current build) ever hits disk.
var _tracked_deviations: Dictionary = {}

func _init(p_director):
	director = p_director

static func _key(template_name: String, role: String, rarity: int, slot: int = 0) -> String:
	return template_name + ":" + role + ":" + str(rarity) + ":" + str(slot)

func get_stock_build(template_name: String, role: String, rarity: int, slot: int = 0) -> StockBuild:
	for b in director.stock_builds:
		if b.template_name == template_name and b.role == role and b.rarity == rarity and b.sub_archetype_slot == slot:
			return b
	return null

func should_test_deviation() -> bool:
	return randf() < DEVIATION_TEST_RATE

# Loading-screen prewarm hook (Deploy-time, called from Main._close_garage)
# - warms every already-known StockBuild's simulation cache (see Mech.
# prewarm_stock_build/_recalculate_grid_for_stock) BEFORE the upcoming
# wave's spawn burst needs it, instead of paying that one-time simulate
# cost live during combat. Cheap/no-op for any build whose cache is
# already warm - only a fresh session's first Deploy (nothing loaded from
# save has ever been simulated this session) or a build that was just
# promoted (StockBuildMutator.establish/promote always hand back a
# brand-new object with an empty cache) does real work here.
func prewarm_all_simulation_caches():
	var MechScript = load("res://scripts/entities/Mech.gd")
	for b in director.stock_builds:
		MechScript.prewarm_stock_build(b)

# Registers a (template, role, rarity, slot)'s very first build - not a
# "deviation" (there was nothing to deviate from), so it's accepted
# unconditionally.
func establish_stock_build(template_name: String, role: String, rarity: int, serialized_components: Dictionary, slot: int = 0):
	# Guard a duplicate race - two mechs of a brand-new (template, role,
	# rarity, slot) can both miss on the same spawn beat before either's
	# result lands here. Keep whichever registers first; don't double-register.
	if get_stock_build(template_name, role, rarity, slot) != null:
		return
	director.stock_builds.append(StockBuildMutator.establish(template_name, role, rarity, serialized_components, slot))
	director.request_save_learned_state()

func record_deviation_result(template_name: String, role: String, rarity: int, serialized_components: Dictionary, fitness: float, slot: int = 0):
	var key = _key(template_name, role, rarity, slot)
	if not _tracked_deviations.has(key):
		_tracked_deviations[key] = []
	_tracked_deviations[key].append({"components": serialized_components, "fitness": fitness})
	if _tracked_deviations[key].size() >= MAX_TRACKED_DEVIATIONS:
		_flush(key)

# Garage-open checkpoint - flush every (template, role, rarity) with at
# least one tracked deviation, regardless of batch size, so nothing sits
# half-decided indefinitely across a play session boundary.
func flush_all_pending():
	for key in _tracked_deviations.keys().duplicate():
		_flush(key)

func _flush(key: String):
	var batch = _tracked_deviations.get(key)
	_tracked_deviations.erase(key)
	if not batch or batch.is_empty():
		return

	var parts = key.split(":", true, 3)
	var template_name = parts[0]
	var role = parts[1] if parts.size() > 1 else ""
	var rarity = int(parts[2]) if parts.size() > 2 else 0
	var slot = int(parts[3]) if parts.size() > 3 else 0
	var current = get_stock_build(template_name, role, rarity, slot)

	# Tally how many tracked sessions actually beat the current build (not
	# just whether the single best one did), and remember the best of those
	# winners as the promotion candidate.
	var best = null
	var wins = 0
	for entry in batch:
		var beats_current = current == null or entry["fitness"] > current.get_average_fitness()
		if beats_current:
			wins += 1
			if best == null or entry["fitness"] > best["fitness"]:
				best = entry

	if best == null:
		return # nothing in this batch ever beat the current build

	if current != null:
		# Never regress on a fluke - only promote once the deviation has
		# beaten the current build consistently, not just once in the batch.
		var required_wins = int(ceil(batch.size() * PROMOTION_WIN_RATE))
		if wins < required_wins:
			return

	var new_build = StockBuildMutator.promote(current, best["components"]) if current else StockBuildMutator.establish(template_name, role, rarity, best["components"], slot)
	if current:
		director.stock_builds.erase(current)
	director.stock_builds.append(new_build)
	director.request_save_learned_state()
