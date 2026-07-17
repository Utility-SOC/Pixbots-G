class_name BossEvolution
extends RefCounted

# Boss-kit evolution: seed/select/mutate/cull/graduate for BossProfile, so
# bosses stop being 6 fixed hand-picked archetypes and become a mutating,
# fitness-selected pool like everything else the director evolves (base_
# role/ability_pool/enrage_style/position_style/hp_mult). Split out of
# SquadDirector.gd, see TemplateEvolution.gd's header comment for why.
# `boss_profiles` itself stays on SquadDirector (WarRoomMenu reads it
# directly); only the behavior moved here.

const BossProfile = preload("res://scripts/ai/BossProfile.gd")
const WarRoomNames = preload("res://scripts/ai/WarRoomNames.gd")

const MAX_EXPERIMENTAL_BOSS_PROFILES = 6
const MIN_BOSS_PROFILE_TRIALS_BEFORE_CULL = 2 # boss fights are rarer events than squad wipes - don't demand as many trials
const BOSS_PROFILE_CULL_THRESHOLD = 60.0
const BOSS_PROFILE_GRADUATE_THRESHOLD = 110.0

var director: SquadDirector

func _init(p_director: SquadDirector):
	director = p_director

# The 6 original hand-picked archetypes, now as the PERMANENT (non-
# experimental) seed of the boss_profiles pool rather than a flat const
# array Main.gd picked from directly. Mutation/crossover grow the pool from
# here; these six never get culled (is_experimental stays false) so there's
# always a stable baseline even if every experiment underperforms.
func register_defaults():
	var seeds = [
		{"name": "Warhulk", "role": "brawler", "ability": "shockwave", "enrage": "juggernaut", "position": "aggressive", "hp_mult": 1.0},
		{"name": "Longshot", "role": "sniper", "ability": "railgun", "enrage": "berserker", "position": "kiter", "hp_mult": 2.3},
		{"name": "Specter", "role": "ambusher", "ability": "blink_strike", "enrage": "berserker", "position": "aggressive", "hp_mult": 1.5},
		{"name": "Incinerator", "role": "flamethrower", "ability": "fire_pool", "enrage": "unstable", "position": "aggressive", "hp_mult": 1.2},
		{"name": "Warden", "role": "jammer", "ability": "jam_burst", "enrage": "vampiric", "position": "kiter", "hp_mult": 0.55},
		{"name": "Overlord", "role": "commander", "ability": "rally", "enrage": "vampiric", "position": "circler", "hp_mult": 0.45},
	]
	for s in seeds:
		var bp = BossProfile.new(s.name, s.role)
		bp.ability_pool = [s.ability]
		bp.enrage_style = s.enrage
		bp.position_style = s.position
		bp.hp_mult = s.hp_mult
		director.boss_profiles.append(bp)

# Fitness-weighted pick among the registered boss profiles (the 6 permanent
# seeds plus whatever's been mutated in). Unlike get_active_solver_profile,
# there's no "always-fresh reactive baseline" here - boss_profiles is never
# empty (see register_defaults), so a plain weighted pick is enough.
func get_active_boss_profile() -> BossProfile:
	if director.boss_profiles.is_empty():
		return BossProfile.new()
	var total_weight = 0.0
	for bp in director.boss_profiles: total_weight += bp.spawn_weight
	var roll = randf() * total_weight
	var acc = 0.0
	for bp in director.boss_profiles:
		acc += bp.spawn_weight
		if roll <= acc:
			return bp
	return director.boss_profiles[0]

func _count_experimental_boss_profiles() -> int:
	var n = 0
	for bp in director.boss_profiles:
		if bp.is_experimental:
			n += 1
	return n

func maybe_introduce_experimental_boss_profile():
	if _count_experimental_boss_profiles() >= MAX_EXPERIMENTAL_BOSS_PROFILES or director.boss_profiles.is_empty():
		return
	var parent = director.boss_profiles[randi() % director.boss_profiles.size()]
	var mutant = _mutate_boss_profile(parent)
	director.boss_profiles.append(mutant)
	print("[DIRECTOR] New experimental boss profile on trial: '", mutant.profile_name, "' role=", mutant.base_role, " abilities=", mutant.ability_pool, " enrage=", mutant.enrage_style, " position=", mutant.position_style)

# Nudges ONE facet of the parent per mutation (same "targeted tweak, not a
# full reroll" philosophy as ProfileEvolution._mutate_profile) so it's
# possible to tell which change is responsible for a fitness swing over
# several generations:
#   - swap enrage style
#   - swap position style
#   - grow/reroll the ability pool (a boss with 2 abilities alternates
#     between them - this is the actual "more evolution options" lever)
#   - nudge hp_mult +-15%
#   - small chance to re-roll the underlying role entirely (changes stats
#     AND visuals/backpack - the most dramatic mutation, kept rare)
func _mutate_boss_profile(parent: BossProfile) -> BossProfile:
	var mutant = BossProfile.new(WarRoomNames.designation(), parent.base_role)
	mutant.ability_pool = parent.ability_pool.duplicate()
	mutant.enrage_style = parent.enrage_style
	mutant.position_style = parent.position_style
	mutant.hp_mult = parent.hp_mult
	mutant.is_experimental = true
	mutant.base_spawn_weight = 60.0
	mutant.spawn_weight = 60.0
	mutant.parent_name = parent.profile_name

	var roll = randf()
	if roll < 0.25:
		mutant.enrage_style = BossProfile.ALL_ENRAGE_STYLES[randi() % BossProfile.ALL_ENRAGE_STYLES.size()]
	elif roll < 0.5:
		mutant.position_style = BossProfile.ALL_POSITION_STYLES[randi() % BossProfile.ALL_POSITION_STYLES.size()]
	elif roll < 0.8:
		if mutant.ability_pool.size() < 2 and randf() < 0.6:
			var addable = BossProfile.ALL_ABILITIES.filter(func(a): return not mutant.ability_pool.has(a))
			if addable.size() > 0:
				mutant.ability_pool.append(addable[randi() % addable.size()])
		elif mutant.ability_pool.size() > 0:
			var idx = randi() % mutant.ability_pool.size()
			mutant.ability_pool[idx] = BossProfile.ALL_ABILITIES[randi() % BossProfile.ALL_ABILITIES.size()]
	else:
		mutant.hp_mult = clamp(mutant.hp_mult * randf_range(0.8, 1.2), 0.2, 4.0)

	# Rare, dramatic: rebuild on a different role's stat block entirely.
	if randf() < 0.15:
		mutant.base_role = BossProfile.ALL_ROLES[randi() % BossProfile.ALL_ROLES.size()]

	return mutant

func _evaluate_experimental_boss_profile(bp: BossProfile):
	if not bp.is_experimental or bp.times_used < MIN_BOSS_PROFILE_TRIALS_BEFORE_CULL:
		return
	var avg = bp.get_average_fitness()
	if avg < BOSS_PROFILE_CULL_THRESHOLD:
		director.boss_profiles.erase(bp)
		print("[DIRECTOR] Experimental boss profile '", bp.profile_name, "' culled (avg fitness %.1f < %.1f)" % [avg, BOSS_PROFILE_CULL_THRESHOLD])
	elif avg >= BOSS_PROFILE_GRADUATE_THRESHOLD:
		bp.is_experimental = false
		print("[DIRECTOR] Experimental boss profile '", bp.profile_name, "' graduated to permanent rotation! (avg fitness %.1f)" % avg)

# Called from SquadDirector._on_boss_defeated (Main._on_boss_died's own
# trigger point) once the boss's own fitness is computed (see Mech.
# get_boss_fitness) - same trigger shape as squad/profile evolution.
func on_boss_defeated(profile: BossProfile, fitness_score: float):
	if not profile:
		return
	profile.update_fitness(fitness_score)
	print("[DIRECTOR] Boss Defeated! Profile: '", profile.profile_name, "' | Fitness: ", "%.1f" % fitness_score, " | New Weight: ", "%.1f" % profile.spawn_weight)
	_evaluate_experimental_boss_profile(profile)
	director.save_learned_state()
