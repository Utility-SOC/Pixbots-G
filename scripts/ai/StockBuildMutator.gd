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

# The very first build for a (template, role) - nothing to compare against
# yet, so it's permanent from the start (not experimental).
static func establish(template_name: String, role: String, serialized_components: Dictionary) -> StockBuild:
	var build = StockBuild.new(template_name, role)
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
static func promote(parent: StockBuild, serialized_components: Dictionary) -> StockBuild:
	var build = StockBuild.new(parent.template_name, parent.role)
	build.serialized_components = serialized_components
	build.is_experimental = false
	build.parent_name = parent.template_name + ":" + parent.role
	build.base_spawn_weight = parent.spawn_weight
	build.spawn_weight = parent.spawn_weight
	build.origin_pilot = parent.origin_pilot
	return build
