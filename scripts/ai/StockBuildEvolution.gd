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

var director

# key ("<template_name>:<role>:<rarity>") -> Array[{"components": Dictionary, "fitness": float}]
# In-memory only between flushes - not persisted per-entry, only the winning
# promotion (or nothing, if none beat the current build) ever hits disk.
var _tracked_deviations: Dictionary = {}

func _init(p_director):
	director = p_director

static func _key(template_name: String, role: String, rarity: int) -> String:
	return template_name + ":" + role + ":" + str(rarity)

func get_stock_build(template_name: String, role: String, rarity: int) -> StockBuild:
	for b in director.stock_builds:
		if b.template_name == template_name and b.role == role and b.rarity == rarity:
			return b
	return null

func should_test_deviation() -> bool:
	return randf() < DEVIATION_TEST_RATE

# Registers a (template, role, rarity)'s very first build - not a
# "deviation" (there was nothing to deviate from), so it's accepted
# unconditionally.
func establish_stock_build(template_name: String, role: String, rarity: int, serialized_components: Dictionary):
	# Guard a duplicate race - two mechs of a brand-new (template, role,
	# rarity) can both miss on the same spawn beat before either's result
	# lands here. Keep whichever registers first; don't double-register.
	if get_stock_build(template_name, role, rarity) != null:
		return
	director.stock_builds.append(StockBuildMutator.establish(template_name, role, rarity, serialized_components))
	director.request_save_learned_state()

func record_deviation_result(template_name: String, role: String, rarity: int, serialized_components: Dictionary, fitness: float):
	var key = _key(template_name, role, rarity)
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

	var best = batch[0]
	for entry in batch:
		if entry["fitness"] > best["fitness"]:
			best = entry

	var parts = key.split(":", true, 2)
	var template_name = parts[0]
	var role = parts[1] if parts.size() > 1 else ""
	var rarity = int(parts[2]) if parts.size() > 2 else 0
	var current = get_stock_build(template_name, role, rarity)

	# Never regress - only promote if the best tracked deviation actually
	# beat the current build's own track record.
	if current != null and best["fitness"] <= current.get_average_fitness():
		return

	var new_build = StockBuildMutator.promote(current, best["components"]) if current else StockBuildMutator.establish(template_name, role, rarity, best["components"])
	if current:
		director.stock_builds.erase(current)
	director.stock_builds.append(new_build)
	director.request_save_learned_state()
