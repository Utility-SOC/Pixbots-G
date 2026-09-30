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
const GenePool = preload("res://scripts/ai/GenePool.gd")

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
# Champion baseline: a deviation must beat the champion's RECENT normalized
# fitness (last N credited spawns; see SquadDirector.credit_bot_death) by this
# margin, and the champion needs a minimum sample count first - otherwise the
# baseline is noise (or, before this existed, a permanent 0 that let anything
# replace it).
const CHAMPION_BASELINE_WINDOW = 12
const MIN_CHAMPION_SAMPLES = 4
const PROMOTION_MARGIN = 1.05
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
	var mult = director.exploration_multiplier() if director.has_method("exploration_multiplier") else 1.0
	return randf() < min(0.5, DEVIATION_TEST_RATE * mult)

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

# Keys (template, role, slot) with no StockBuild yet at `rarity`, in the
# order a real spawn would want them: heaviest-weighted templates first.
func missing_build_keys(rarity: int) -> Array:
	var out: Array = []
	for k in _all_keys(rarity):
		if get_stock_build(k[0], k[1], _rarity_for(k[1], rarity), k[2]) == null:
			out.append(k)
	return out

var _presolving := false

# `rarity` >= 0 pins every role to that tier (tests/tools); a negative value
# asks the director for each role's own wave-gated tier (see
# SquadDirector.expected_base_rarity), since grunts and elites unlock tiers
# at different waves.
func _rarity_for(role: String, rarity: int) -> int:
	return rarity if rarity >= 0 else director.expected_base_rarity(0, role)

# Off-wave deviation candidates (see Mech.generate_deviation_candidate):
# key -> Array[StockBuild], unregistered and simulation-cache-warm.
const CANDIDATE_POOL_TARGET = 1
var _candidate_pool: Dictionary = {}

# Chance a candidate is an imported-donor splice rather than a fresh solve,
# when a same-role/same-rarity donor from another pilot exists.
const SPLICE_CHANCE = 0.5
# Splice candidates awaiting their result: [{components, tag}], matched by
# identity so the tag survives record_deviation_result -> _flush -> promote.
var _splice_tags: Array = []

func pick_donor(role: String, rarity: int):
	var pool = []
	for b in director.stock_builds:
		if b.origin_pilot != "" and b.role == role and b.rarity == rarity and GenePool.donor_quality(b) >= GenePool.DONOR_MIN_MEAN:
			pool.append(b)
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()]

func _make_candidate(MechScript, template_name: String, role: String, rarity: int, slot: int, profile):
	var champ = get_stock_build(template_name, role, rarity, slot)
	if champ != null and randf() < SPLICE_CHANCE:
		var donor = pick_donor(role, rarity)
		if donor != null and donor != champ:
			var spliced = StockBuildMutator.splice(champ, donor)
			if spliced != null:
				MechScript.prewarm_stock_build(spliced)
				_splice_tags.append({"components": spliced.serialized_components, "tag": spliced.splice_from})
				return spliced
	return MechScript.generate_deviation_candidate(self, template_name, role, rarity, slot, profile)

func take_deviation_candidate(template_name: String, role: String, rarity: int, slot: int = 0):
	var key = _key(template_name, role, rarity, slot)
	var pool: Array = _candidate_pool.get(key, [])
	if pool.is_empty():
		return null
	return pool.pop_back()

# Keys that have a champion but fewer than CANDIDATE_POOL_TARGET spare candidates.
func missing_candidate_keys(rarity: int) -> Array:
	var out: Array = []
	for k in _all_keys(rarity):
		if get_stock_build(k[0], k[1], _rarity_for(k[1], rarity), k[2]) == null:
			continue
		if _candidate_pool.get(_key(k[0], k[1], _rarity_for(k[1], rarity), k[2]), []).size() < CANDIDATE_POOL_TARGET:
			out.append(k)
	return out

func _all_keys(rarity: int) -> Array:
	var out: Array = []
	var templates: Array = director.templates.duplicate()
	templates.sort_custom(func(a, b): return a.spawn_weight > b.spawn_weight)
	for t in templates:
		var roles: Dictionary = t.required_roles.duplicate()
		if not roles.has("scout"):
			roles["scout"] = 1
		for role in roles:
			var count = 1 if role == "scout" and not t.required_roles.has("scout") else int(roles[role])
			for slot in range(min(count, MAX_SUB_ARCHETYPE_SLOTS)):
				out.append([t.template_name, role, slot])
	return out

# Everything the upcoming wave could need: missing champions first, then
# spare deviation candidates. `on_progress(done, total)` drives the loading
# screen; `should_abort` stops background runs when the wave's spawn burst starts.
func pregenerate(rarity: int, should_abort: Callable = Callable(), on_progress: Callable = Callable()) -> void:
	if _presolving:
		return
	_presolving = true
	var MechScript = load("res://scripts/entities/Mech.gd")
	var tree = director.get_tree()
	var builds = missing_build_keys(rarity)
	var total = builds.size()
	for k in _all_keys(rarity):
		var key = _key(k[0], k[1], _rarity_for(k[1], rarity), k[2])
		if get_stock_build(k[0], k[1], _rarity_for(k[1], rarity), k[2]) != null and _candidate_pool.get(key, []).size() < CANDIDATE_POOL_TARGET:
			total += 1
	var done = 0
	for k in builds:
		if _should_stop(should_abort):
			_presolving = false
			return
		MechScript.presolve_stock_build(self, k[0], k[1], _rarity_for(k[1], rarity), k[2], director.get_active_solver_profile(k[1]))
		done += 1
		if on_progress.is_valid():
			on_progress.call(done, total)
		await tree.process_frame
	for k in _all_keys(rarity):
		if _should_stop(should_abort):
			break
		var key = _key(k[0], k[1], _rarity_for(k[1], rarity), k[2])
		if get_stock_build(k[0], k[1], _rarity_for(k[1], rarity), k[2]) == null:
			continue
		var pool: Array = _candidate_pool.get(key, [])
		if pool.size() >= CANDIDATE_POOL_TARGET:
			continue
		var cand = _make_candidate(MechScript, k[0], k[1], _rarity_for(k[1], rarity), k[2], director.get_active_solver_profile(k[1]))
		if cand != null:
			pool.append(cand)
			_candidate_pool[key] = pool
		done += 1
		if on_progress.is_valid():
			on_progress.call(done, total)
		await tree.process_frame
	_presolving = false

func is_busy() -> bool:
	return _presolving

func _should_stop(should_abort: Callable) -> bool:
	if should_abort.is_valid() and should_abort.call():
		return true
	return not is_instance_valid(director) or not director.is_inside_tree()

# Time-sliced pre-solve of every missing build at `rarity`: one build per
# frame so a fresh AutoEquipSolver run never lands mid-wave. `should_abort`
# lets the caller stop as soon as the wave's own spawn burst begins.
func presolve_missing_builds(rarity: int, should_abort: Callable = Callable()) -> void:
	if _presolving:
		return
	_presolving = true
	var MechScript = load("res://scripts/entities/Mech.gd")
	var tree = director.get_tree()
	for k in missing_build_keys(rarity):
		if should_abort.is_valid() and should_abort.call():
			break
		if not is_instance_valid(director) or not director.is_inside_tree():
			break
		MechScript.presolve_stock_build(self, k[0], k[1], _rarity_for(k[1], rarity), k[2], director.get_active_solver_profile(k[1]))
		await tree.process_frame
	_presolving = false

# Registers a (template, role, rarity, slot)'s very first build - not a
# "deviation" (there was nothing to deviate from), so it's accepted
# unconditionally.
func establish_stock_build(template_name: String, role: String, rarity: int, serialized_components: Dictionary, slot: int = 0, solver_profile_name: String = ""):
	# Guard a duplicate race - two mechs of a brand-new (template, role,
	# rarity, slot) can both miss on the same spawn beat before either's
	# result lands here. Keep whichever registers first; don't double-register.
	if get_stock_build(template_name, role, rarity, slot) != null:
		return
	director.stock_builds.append(StockBuildMutator.establish(template_name, role, rarity, serialized_components, slot, solver_profile_name))
	director.request_save_learned_state()

func record_deviation_result(template_name: String, role: String, rarity: int, serialized_components: Dictionary, fitness: float, slot: int = 0, solver_profile_name: String = ""):
	var key = _key(template_name, role, rarity, slot)
	if not _tracked_deviations.has(key):
		_tracked_deviations[key] = []
	_tracked_deviations[key].append({"components": serialized_components, "fitness": fitness, "profile": solver_profile_name})
	if _tracked_deviations[key].size() >= MAX_TRACKED_DEVIATIONS:
		_flush(key)

# Garage-open checkpoint - flush every (template, role, rarity) with at
# least one tracked deviation, regardless of batch size, so nothing sits
# half-decided indefinitely across a play session boundary.
func flush_all_pending():
	for key in _tracked_deviations.keys().duplicate():
		_flush(key)

static func champion_recent_fitness(build: StockBuild) -> float:
	var h: Array = build.fitness_history
	if h.is_empty():
		return 0.0
	var n = min(h.size(), CHAMPION_BASELINE_WINDOW)
	var total = 0.0
	for i in range(h.size() - n, h.size()):
		total += float(h[i])
	return total / float(n)

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

	# Baseline = the champion's RECENT normalized fitness (credited from
	# SquadDirector.credit_bot_death), not its lifetime average.
	var baseline = 0.0
	if current != null:
		if current.fitness_history.size() < MIN_CHAMPION_SAMPLES:
			_tracked_deviations[key] = batch.slice(-MAX_TRACKED_DEVIATIONS * 2) # not enough champion data yet; keep evidence
			return
		baseline = champion_recent_fitness(current)

	var best = null
	var wins = 0
	for entry in batch:
		var beats_current = current == null or entry["fitness"] > baseline * PROMOTION_MARGIN
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

	var splice_tag = ""
	for i in range(_splice_tags.size()):
		if is_same(_splice_tags[i]["components"], best["components"]):
			splice_tag = _splice_tags[i]["tag"]
			_splice_tags.remove_at(i)
			break
	while _splice_tags.size() > 32:
		_splice_tags.pop_front()
	var new_build = StockBuildMutator.promote(current, best["components"], best.get("profile", ""), splice_tag) if current else StockBuildMutator.establish(template_name, role, rarity, best["components"], slot, best.get("profile", ""))
	new_build.fitness_history = [float(best["fitness"])]
	new_build.times_used = 1
	new_build.total_fitness = float(best["fitness"])
	if current:
		director.stock_builds.erase(current)
	director.stock_builds.append(new_build)
	director.request_save_learned_state()
