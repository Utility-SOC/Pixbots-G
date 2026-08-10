extends Node

# Regression check for TemplateEvolution.maybe_introduce_experimental_
# template()'s roll weights (mutate 55% / crossover 30% / random 15%,
# widened from the old 35/30/35 - see this session's spawn-perf work:
# every SquadTemplate mints a fresh WarRoomNames identity, which is a
# fresh key in both AutoEquipSolver's topology cache and StockBuild
# Evolution's cache. mutate()/crossover() at least start from an already-
# proven parent's role composition (and set parent_name), so they tend to
# survive past MIN_TRIALS_BEFORE_CULL more often than a from-scratch
# random_template() roll - fewer culls means fewer replacement mints per
# unit time, i.e. more reuse of whatever's already registered).
#
# random_template() is the only one of the three that never sets
# parent_name (stays "" - see SquadTemplate.gd's default), so tallying
# parent_name-empty vs parent_name-set across many trials is a clean,
# print-free way to measure the real mutate+crossover-vs-random split
# without caring which of mutate/crossover fired.

const SquadDirectorScript = preload("res://scripts/ai/SquadDirector.gd")
const TemplateEvolutionScript = preload("res://scripts/ai/TemplateEvolution.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var director = SquadDirectorScript.new()
	director.name = "SquadDirector"
	add_child(director)

	var parent_a = SquadTemplate.new("Proven Alpha", {"brawler": 2, "sniper": 1})
	parent_a.times_deployed = 10
	parent_a.total_fitness = 900.0 # avg 90
	var parent_b = SquadTemplate.new("Proven Beta", {"scout": 1, "jammer": 1})
	parent_b.times_deployed = 10
	parent_b.total_fitness = 800.0 # avg 80

	var trials = 1000
	var from_scratch = 0
	var lineage_preserving = 0
	for i in range(trials):
		var roster: Array[SquadTemplate] = [parent_a, parent_b]
		director.templates = roster
		director.template_evolution.maybe_introduce_experimental_template()
		# Exactly one new template should have been appended (2 candidates,
		# well under MAX_EXPERIMENTAL_TEMPLATES, both non-experimental).
		if director.templates.size() != 3:
			continue
		var minted = director.templates[2]
		if minted.parent_name == "":
			from_scratch += 1
		else:
			lineage_preserving += 1

	var total = from_scratch + lineage_preserving
	var from_scratch_frac = float(from_scratch) / total
	var lineage_frac = float(lineage_preserving) / total
	print("from-scratch (random_template): %d/%d (%.1f%%)  lineage-preserving (mutate/crossover): %d/%d (%.1f%%)" % [
		from_scratch, total, from_scratch_frac * 100.0, lineage_preserving, total, lineage_frac * 100.0])

	_check("from-scratch share lands near the intended 15%% (got %.1f%%)" % (from_scratch_frac * 100.0),
		from_scratch_frac > 0.08 and from_scratch_frac < 0.23)
	_check("lineage-preserving (mutate+crossover) is now the large majority (got %.1f%%)" % (lineage_frac * 100.0),
		lineage_frac > 0.75)

	# The cap itself still works: once MAX_EXPERIMENTAL_TEMPLATES slots are
	# full, no more get minted regardless of roll.
	var full_roster: Array[SquadTemplate] = []
	for i in range(TemplateEvolutionScript.MAX_EXPERIMENTAL_TEMPLATES):
		var t = SquadTemplate.new("Filler %d" % i, {"brawler": 1})
		t.is_experimental = true
		full_roster.append(t)
	director.templates = full_roster
	director.template_evolution.maybe_introduce_experimental_template()
	_check("no new template minted once MAX_EXPERIMENTAL_TEMPLATES slots are full",
		director.templates.size() == TemplateEvolutionScript.MAX_EXPERIMENTAL_TEMPLATES)

	if failures == 0:
		print("PASS: experimental-template introduction favors mutate/crossover reuse over from-scratch generation, and the experimental-slot cap still holds")
	get_tree().quit(0 if failures == 0 else 1)
