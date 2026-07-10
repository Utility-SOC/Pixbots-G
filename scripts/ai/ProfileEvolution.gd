class_name ProfileEvolution
extends RefCounted

# Loadout-doctrine evolution: build/select/mutate/crossover/cull/graduate
# for SolverProfile, now role-scoped (a sniper doctrine and a brawler
# doctrine no longer compete for the same spawn-weight rotation - see
# SolverProfile.role's own field comment). Split out of SquadDirector.gd,
# see TemplateEvolution.gd's header comment for why. `solver_profiles`
# itself stays on SquadDirector (WarRoomMenu reads it directly); only the
# behavior moved here.

const SquadTemplateMutator = preload("res://scripts/ai/SquadTemplateMutator.gd")
const SolverProfile = preload("res://scripts/ai/SolverProfile.gd")
const WarRoomNames = preload("res://scripts/ai/WarRoomNames.gd")

const MAX_EXPERIMENTAL_PROFILES = 5
const MIN_PROFILE_TRIALS_BEFORE_CULL = 3
const PROFILE_CULL_THRESHOLD = 60.0
const PROFILE_GRADUATE_THRESHOLD = 110.0

var director: SquadDirector

func _init(p_director: SquadDirector):
	director = p_director

# Builds a SolverProfile automatically from what the director has observed
# about the player: which element they lean on (so enemies build toward the
# element that counters the player's shield) and how much shield/HP they're
# packing (so a tanky player build gets answered with Pierce instead of
# just more raw damage). This is the "counters should start proportional to
# the player" default - get_active_solver_profile()/maybe_introduce_
# experimental_profile() below are what make it "evolvy" over time rather
# than static.
func build_reactive_profile(role: String = "") -> SolverProfile:
	var profile = SolverProfile.new("Reactive")
	profile.role = role

	if director.total_damage_taken > 200.0:
		var top_element = ""
		var top_ratio = 0.0
		for element in director.player_element_usage.keys():
			var ratio = director.player_element_usage[element] / director.total_damage_taken
			if ratio > top_ratio:
				top_ratio = ratio
				top_element = element

		if top_element != "" and director.SHIELD_COUNTER_WHEEL.has(top_element):
			profile.favored_synergy = director._element_string_to_synergy(director.SHIELD_COUNTER_WHEEL[top_element])

	var players = director.get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		var p = players[0]
		var tankiness = 0.0
		if "max_shield_hp" in p:
			tankiness += p.max_shield_hp
		if "max_hp" in p:
			tankiness += max(0.0, p.max_hp - 100.0) # 100 is the baseline starting max_hp
		if tankiness > 100.0:
			profile.pierce_priority = clamp(0.3 + tankiness / 600.0, 0.3, 0.9)

	return profile

# Weighted pick between an always-fresh reactive baseline (recomputed from
# current telemetry every call, so it never goes stale) and whatever
# experimental profiles have been mutated in, scoped to `role`. This is
# what "evolvy" means for the solver: over time, mutated profiles that
# outperform the plain reactive baseline get selected more often, and
# underperformers get culled the same way experimental squad templates are.
func get_active_solver_profile(role: String = "") -> SolverProfile:
	var reactive = build_reactive_profile(role)
	reactive.spawn_weight = 100.0

	# Role-scoped pool: only profiles tuned for THIS role compete for the
	# spawn roll (see SolverProfile.role's field comment). A brand new role
	# with no profiles bred for it yet just gets the reactive baseline until
	# maybe_introduce_experimental_profile()'s coverage-seeking creates some.
	var role_candidates: Array = director.solver_profiles.filter(func(p): return p.role == role)
	if role_candidates.is_empty():
		return reactive

	var candidates: Array = role_candidates.duplicate()
	candidates.append(reactive)

	var total_weight = 0.0
	for p in candidates: total_weight += p.spawn_weight
	var roll = randf() * total_weight
	var acc = 0.0
	for p in candidates:
		acc += p.spawn_weight
		if roll <= acc:
			return p
	return reactive

func _count_experimental_profiles() -> int:
	var n = 0
	for p in director.solver_profiles:
		if p.is_experimental:
			n += 1
	return n

# Coverage-seeking: picks whichever combat role currently has the FEWEST
# registered profiles (ties broken randomly), so new experimental doctrine
# growth spreads across every role instead of all piling onto whichever
# role happened to get lucky first. "diver"/"piercing_jammer" aren't in
# this canonical list - they're rare enough to grow reactively/via the
# per-bot jitter in SquadDirector._spawn_bot_for_role instead of being
# proactively seeded.
func _pick_role_needing_profiles() -> String:
	var counts: Dictionary = {}
	for r in SquadTemplateMutator.ALL_ROLES:
		counts[r] = 0
	for p in director.solver_profiles:
		if counts.has(p.role):
			counts[p.role] += 1
	var min_count = 999999
	var candidates: Array = []
	for r in counts:
		if counts[r] < min_count:
			min_count = counts[r]
			candidates = [r]
		elif counts[r] == min_count:
			candidates.append(r)
	return candidates[randi() % candidates.size()]

func maybe_introduce_experimental_profile():
	if _count_experimental_profiles() >= MAX_EXPERIMENTAL_PROFILES:
		return
	var role = _pick_role_needing_profiles()
	var role_pool: Array = director.solver_profiles.filter(func(p): return p.role == role)

	var mutant: SolverProfile = null
	# 30% crossbreed when two same-role profiles exist to breed from
	if role_pool.size() >= 2 and randf() < 0.3:
		var a = role_pool[randi() % role_pool.size()]
		var b = a
		for i in range(8):
			b = role_pool[randi() % role_pool.size()]
			if b != a:
				break
		mutant = _crossover_profiles(a, b) if a != b else _mutate_profile(a)
	else:
		var parent = role_pool[randi() % role_pool.size()] if not role_pool.is_empty() else build_reactive_profile(role)
		mutant = _mutate_profile(parent)
	mutant.role = role
	director.solver_profiles.append(mutant)
	print("[DIRECTOR] New experimental solver profile on trial: '", mutant.profile_name, "' role=", role, " favored=", mutant.favored_synergy, " pierce=", "%.2f" % mutant.pierce_priority)

# Loadout-doctrine breeding: averaged priorities with a little noise,
# favored element from the fitter parent - same shape as squad crossover.
# Role is set by the caller (maybe_introduce_experimental_profile) since
# both parents are already guaranteed same-role by that point.
func _crossover_profiles(a: SolverProfile, b: SolverProfile) -> SolverProfile:
	var fitter = a if a.get_average_fitness() >= b.get_average_fitness() else b
	var child = SolverProfile.new(WarRoomNames.designation(), fitter.favored_synergy)
	child.pierce_priority = clamp((a.pierce_priority + b.pierce_priority) / 2.0 + randf_range(-0.05, 0.05), 0.0, 1.0)
	child.amplify_priority = clamp((a.amplify_priority + b.amplify_priority) / 2.0 + randf_range(-0.05, 0.05), 0.1, 2.0)
	child.is_experimental = true
	child.base_spawn_weight = 65.0
	child.spawn_weight = 65.0
	return child

func _mutate_profile(parent: SolverProfile) -> SolverProfile:
	var mutant = SolverProfile.new(WarRoomNames.designation(), parent.favored_synergy)
	mutant.pierce_priority = clamp(parent.pierce_priority + randf_range(-0.3, 0.3), 0.0, 1.0)
	mutant.amplify_priority = clamp(parent.amplify_priority + randf_range(-0.3, 0.3), 0.1, 2.0)
	if randf() < 0.3:
		mutant.favored_synergy = randi() % EnergyPacket.SynergyType.size()
	mutant.is_experimental = true
	mutant.base_spawn_weight = 60.0
	mutant.spawn_weight = 60.0
	return mutant

# Cull/graduate experimental profiles - called from SquadDirector.
# credit_bot_death, same trigger shape as squad-template evolution.
func evaluate_experimental_profile(p: SolverProfile):
	if not p.is_experimental or p.times_used < MIN_PROFILE_TRIALS_BEFORE_CULL:
		return
	var avg = p.get_average_fitness()
	if avg < PROFILE_CULL_THRESHOLD:
		director.solver_profiles.erase(p)
		print("[DIRECTOR] Experimental solver profile '", p.profile_name, "' culled (avg fitness %.1f < %.1f)" % [avg, PROFILE_CULL_THRESHOLD])
	elif avg >= PROFILE_GRADUATE_THRESHOLD:
		p.is_experimental = false
		print("[DIRECTOR] Experimental solver profile '", p.profile_name, "' graduated to permanent rotation! (avg fitness %.1f)" % avg)
