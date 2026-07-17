class_name TemplateEvolution
extends RefCounted

# Squad-composition evolution: mutate/crossover/cull/graduate/select for
# SquadTemplate. Split out of SquadDirector.gd, which had grown to three
# near-identical evolutionary subsystems (this one, ProfileEvolution,
# BossEvolution) all interleaved in a single 1,200+ line file.
#
# Same composed-RefCounted-helper pattern as Mech.gd's PlayerController/
# BossBrain/StatusEffectRunner: a non-Node object taking its owner as a
# constructor reference, called into from the owner's own methods. The
# `templates` array itself stays on SquadDirector (WarRoomMenu, Squad.gd,
# and Main.gd all read `director.templates` directly as a public field) -
# only the mutate/crossover/cull/select BEHAVIOR moved here.

const SquadTemplateMutator = preload("res://scripts/ai/SquadTemplateMutator.gd")

const MAX_EXPERIMENTAL_TEMPLATES = 7
const MIN_TRIALS_BEFORE_CULL = 3
const CULL_FITNESS_THRESHOLD = 60.0
const GRADUATE_FITNESS_THRESHOLD = 110.0

var director: SquadDirector

func _init(p_director: SquadDirector):
	director = p_director

func _count_experimental() -> int:
	var n = 0
	for t in director.templates:
		if t.is_experimental:
			n += 1
	return n

# Fitness-weighted parent selection for mutation/breeding - templates that
# keep proving themselves in combat get picked as parents more often, which
# is what makes the "borrow from successful past buildouts" loop real.
func _pick_fitness_weighted_parent(candidates: Array) -> SquadTemplate:
	var total = 0.0
	for t in candidates:
		total += max(10.0, t.get_average_fitness())
	var roll = randf() * total
	var acc = 0.0
	for t in candidates:
		acc += max(10.0, t.get_average_fitness())
		if roll <= acc:
			return t
	return candidates[0]

# Introduces one new experimental template, either by mutating an existing
# one or generating a fresh random composition - as long as there's room
# under MAX_EXPERIMENTAL_TEMPLATES. Call this periodically (Main.gd calls it
# every few waves) rather than on every squad spawn, so trials aren't
# constantly getting reset before they've proven anything.
func maybe_introduce_experimental_template():
	if director.templates.is_empty() or _count_experimental() >= MAX_EXPERIMENTAL_TEMPLATES:
		return

	# Three sources of fresh doctrine: mutate one proven parent (35%),
	# crossbreed two proven parents (30%, needs 2+ candidates), or a fully
	# random composition for genetic diversity (35% - nudged up from 30% so
	# the Director keeps stumbling into compositions nobody bred on purpose,
	# not just refinements of what already works).
	var candidates = director.templates.filter(func(t): return not t.is_experimental)
	if candidates.is_empty():
		candidates = director.templates

	var new_template: SquadTemplate = null
	var roll = randf()
	if roll < 0.35:
		new_template = SquadTemplateMutator.mutate(_pick_fitness_weighted_parent(candidates))
	elif roll < 0.65 and candidates.size() >= 2:
		var parent_a = _pick_fitness_weighted_parent(candidates)
		# Distributed evolution: once imports are in the mix, bias crossover
		# toward mixing lineages from DIFFERENT pilots rather than always
		# breeding your own top performers together - a few draws for a
		# cross-origin candidate before falling back to "just pick anyone
		# different" (which is also all that's available before any import
		# has ever happened, since every local template shares origin_pilot
		# == "").
		var parent_b = parent_a
		var found_cross_origin = false
		for i in range(8):
			var candidate = _pick_fitness_weighted_parent(candidates)
			if candidate != parent_a and candidate.origin_pilot != parent_a.origin_pilot:
				parent_b = candidate
				found_cross_origin = true
				break
		if not found_cross_origin:
			for i in range(8): # draw until we get a different second parent (bounded)
				parent_b = _pick_fitness_weighted_parent(candidates)
				if parent_b != parent_a:
					break
		if parent_a == parent_b:
			new_template = SquadTemplateMutator.mutate(parent_a)
		else:
			new_template = SquadTemplateMutator.crossover(parent_a, parent_b)
			var origin_note = " [cross-pilot]" if found_cross_origin else ""
			print("[DIRECTOR] Crossbred '", parent_a.template_name, "' x '", parent_b.template_name, "'", origin_note)
	else:
		new_template = SquadTemplateMutator.random_template()

	if new_template:
		director.register_template(new_template)
		print("[DIRECTOR] New experimental template on trial: '", new_template.template_name, "' roles=", new_template.required_roles)

# Below this water fraction the bias is a no-op - most maps have a pond
# here and there and that shouldn't perturb squad selection at all.
const WATER_BIAS_THRESHOLD = 0.15
# Never fully zero out a non-diver template even on an all-water map - a
# starved-to-zero weight can stall spawning if every registered template
# happens to lack "diver" (e.g. early game before one's ever been rolled).
const WATER_BIAS_FLOOR = 0.15

func select_template_weighted() -> SquadTemplate:
	if director.templates.is_empty():
		return null

	var water_frac: float = director.get_map_water_fraction() if director.has_method("get_map_water_fraction") else 0.0
	var apply_bias = water_frac > WATER_BIAS_THRESHOLD

	var total_weight = 0.0
	var effective_weights: Dictionary = {} # SquadTemplate -> float, keyed by instance
	for t in director.templates:
		var w = t.spawn_weight
		if apply_bias:
			# Water-capable templates get proportionally more likely to spawn
			# the wetter the map is; templates with zero water-capable
			# members get proportionally suppressed (never to zero - see
			# WATER_BIAS_FLOOR) instead of drowning on arrival.
			if t.required_roles.has("diver"):
				w *= 1.0 + water_frac
			else:
				w *= max(WATER_BIAS_FLOOR, 1.0 - water_frac)
		effective_weights[t] = w
		total_weight += w

	var roll = randf() * total_weight
	var current_weight = 0.0
	var selected_template: SquadTemplate = director.templates[0]

	for t in director.templates:
		current_weight += effective_weights[t]
		if roll <= current_weight:
			selected_template = t
			break

	return selected_template

# Cull/graduate one experimental template once it's had a fair trial - this
# is what keeps mutation + merge-derived templates from piling up forever.
# Called from SquadDirector._on_squad_defeated right after the template's
# fitness updates for this deployment.
func evaluate_experimental_template(t: SquadTemplate):
	if not t.is_experimental or t.times_deployed < MIN_TRIALS_BEFORE_CULL:
		return
	var avg = t.get_average_fitness()
	if avg < CULL_FITNESS_THRESHOLD:
		director.templates.erase(t)
		print("[DIRECTOR] Experimental template '", t.template_name, "' culled (avg fitness %.1f < %.1f)" % [avg, CULL_FITNESS_THRESHOLD])
	elif avg >= GRADUATE_FITNESS_THRESHOLD:
		t.is_experimental = false
		print("[DIRECTOR] Experimental template '", t.template_name, "' graduated to permanent rotation! (avg fitness %.1f)" % avg)
