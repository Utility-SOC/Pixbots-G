class_name StockBuildMutator
extends RefCounted

# Pure-static factory for StockBuild records - mirrors SquadTemplateMutator's
# role for SquadTemplate. Deliberately does NOT drive AutoEquipSolver itself:
# the actual solve() sequence (a single shared inventory Array consumed
# across torso -> arm_R -> arm_L, in that order) already lives in
# Mech.build_loadout_for_role and must stay there - re-deriving that
# orchestration here would risk a second, subtly different tile-distribution
# order between the two code paths. This file only wraps an already-solved
# serialized_components payload (produced by Mech.gd, exactly as a live
# spawn already does today) into a proper StockBuild Resource - "mutation"
# for this record type IS a fresh solve() call, which AutoEquipSolver's own
# internal RNG already makes non-deterministic call-to-call (see that
# file's header comment) - there's no separate perturbation algorithm to
# invent on top of that.

const StockBuild = preload("res://scripts/ai/StockBuild.gd")

# The very first build for a (template, role, sub_archetype_slot) - nothing
# to compare against yet, so it's permanent from the start (not experimental).
static func establish(template_name: String, role: String, rarity: int, serialized_components: Dictionary, sub_archetype_slot: int = 0, solver_profile_name: String = "") -> StockBuild:
	var build = StockBuild.new(template_name, role, rarity)
	build.sub_archetype_slot = sub_archetype_slot
	build.solver_profile_name = solver_profile_name
	build.serialized_components = serialized_components
	build.is_experimental = false
	build.base_spawn_weight = 100.0
	build.spawn_weight = 100.0
	return build

# A promoted deviation - replaces an existing build as a new generation.
# Starts non-experimental too: it already won a head-to-head fitness
# comparison against its parent before StockBuildEvolution promotes it (see
# that file's _flush), unlike SquadTemplate/SolverProfile mutants which
# start experimental and have to prove themselves after the fact.
static func promote(parent: StockBuild, serialized_components: Dictionary, solver_profile_name: String = "", splice_from: String = "") -> StockBuild:
	var build = StockBuild.new(parent.template_name, parent.role, parent.rarity)
	build.solver_profile_name = solver_profile_name
	build.sub_archetype_slot = parent.sub_archetype_slot
	build.serialized_components = serialized_components
	build.is_experimental = false
	build.parent_name = parent.template_name + ":" + parent.role
	build.base_spawn_weight = parent.spawn_weight
	build.spawn_weight = parent.spawn_weight
	build.origin_pilot = parent.origin_pilot
	build.splice_from = splice_from if splice_from != "" else parent.splice_from
	return build

# Cross-import breeding: the champion with ONE body slot (arm, leg, torso...)
# swapped for the donor's version, so another pilot's build cleaves in a piece
# at a time and each piece has to win on its own (the result is only a
# deviation candidate; StockBuildEvolution promotes it if it beats the
# champion). Returns null when there is no slot where the two differ.
static func splice(champion: StockBuild, donor: StockBuild, rng: RandomNumberGenerator = null) -> StockBuild:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var slots = []
	for k in donor.serialized_components:
		var dpay = donor.serialized_components[k]
		if not champion.serialized_components.has(k) or dpay.get("tiles", []).is_empty():
			continue
		if JSON.stringify(dpay.get("tiles", [])) != JSON.stringify(champion.serialized_components[k].get("tiles", [])):
			slots.append(k)
	if slots.is_empty():
		return null
	slots.sort()
	var slot = slots[rng.randi() % slots.size()]
	var comps = champion.serialized_components.duplicate(true)
	comps[slot] = donor.serialized_components[slot].duplicate(true)
	var child = StockBuild.new(champion.template_name, champion.role, champion.rarity)
	child.sub_archetype_slot = champion.sub_archetype_slot
	child.solver_profile_name = champion.solver_profile_name
	child.serialized_components = comps
	child.parent_name = champion.template_name + ":" + champion.role
	child.origin_pilot = champion.origin_pilot
	child.splice_from = donor.origin_pilot if donor.origin_pilot != "" else "Unknown Pilot"
	child.base_spawn_weight = champion.spawn_weight
	child.spawn_weight = champion.spawn_weight
	return child
