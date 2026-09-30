extends Node

# Regression check for the AI credit/normalisation fixes: FitnessPar
# (per role:tier par), champion baseline from RECENT credited fitness with a
# minimum-sample gate and promotion margin, solver-profile provenance carried
# through promotion, and the wave-tier rarity gate on SquadDirector.
# Uses a fake director (no tree, no user:// writes) like StockBuildPrewarmCheck.

const StockBuildScript = preload("res://scripts/ai/StockBuild.gd")
const EvoScript = preload("res://scripts/ai/StockBuildEvolution.gd")
const ParScript = preload("res://scripts/ai/FitnessPar.gd")
const DirectorScript = preload("res://scripts/ai/SquadDirector.gd")

class FakeDirector:
	var stock_builds: Array = []
	var templates: Array = []
	func request_save_learned_state():
		pass

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# --- FitnessPar
	var par = ParScript.new()
	_check("first sample normalizes to 100", is_equal_approx(par.normalize_and_update("sniper:0", 500.0), 100.0))
	var hi = par.normalize_and_update("sniper:0", 1000.0)
	_check("2x par scores ~200 (%.0f)" % hi, hi > 190.0 and hi < 210.0)
	var other = par.normalize_and_update("sniper:3", 5000.0)
	_check("a different tier bucket has its own par (first sample = 100)", is_equal_approx(other, 100.0))
	var rt = ParScript.new()
	rt.from_dict(par.to_dict())
	_check("par survives to_dict/from_dict", is_equal_approx(rt.par_for("sniper:0"), par.par_for("sniper:0")))

	# --- StockBuild provenance round trip
	var sb = StockBuildScript.new("T", "sniper", 1)
	sb.solver_profile_name = "Exp-7"
	var sb2 = StockBuildScript.new()
	sb2.from_dict(sb.to_dict())
	_check("solver_profile_name round-trips", sb2.solver_profile_name == "Exp-7")

	# --- _flush gating
	var fd = FakeDirector.new()
	var evo = EvoScript.new(fd)
	var champ = StockBuildScript.new("T", "sniper", 1)
	champ.serialized_components = {0: {"x": 1}}
	fd.stock_builds.append(champ)
	for i in range(3):
		evo.record_deviation_result("T", "sniper", 1, {0: {"x": 2}}, 200.0, 0, "P-new")
	evo.flush_all_pending()
	_check("champion with <MIN samples keeps its seat (no promotion on 0 baseline)", fd.stock_builds.size() == 1 and fd.stock_builds[0] == champ)
	for i in range(6):
		champ.update_fitness(100.0)
	for i in range(4):
		evo.record_deviation_result("T", "sniper", 1, {0: {"x": 3}}, 103.0, 0, "P-weak")
	evo.flush_all_pending()
	_check("deviation inside the margin does not promote", fd.stock_builds[0] == champ)
	for i in range(8):
		evo.record_deviation_result("T", "sniper", 1, {0: {"x": 4}}, 140.0, 0, "P-strong")
	var promoted = evo.get_stock_build("T", "sniper", 1, 0)
	_check("clear winner promotes", promoted != champ and fd.stock_builds.size() == 1)
	_check("promotion carries the producing profile", promoted.solver_profile_name == "P-strong")
	_check("promoted build starts with its winning sample as baseline", promoted.fitness_history.size() == 1 and is_equal_approx(evo.champion_recent_fitness(promoted), 140.0))

	# --- rarity gate
	var d = DirectorScript.new()
	_check("wave 0 is COMMON", d.rarity_ceiling_for_wave(0, "sniper") == 0)
	_check("wave 8 unlocks UNCOMMON for elites", d.rarity_ceiling_for_wave(8, "sniper") == 1)
	_check("brawlers unlock later than snipers at wave 8", d.rarity_ceiling_for_wave(8, "brawler") == 0)
	_check("wave 20 brawler is UNCOMMON", d.rarity_ceiling_for_wave(20, "brawler") == 1)
	_check("wave 40 sniper is LEGENDARY", d.rarity_ceiling_for_wave(40, "sniper") == 3)
	_check("wave 74 sniper is not yet MYTHIC", d.rarity_ceiling_for_wave(74, "sniper") == 3)
	_check("wave 75 sniper is MYTHIC", d.rarity_ceiling_for_wave(75, "sniper") == 4)
	d.free()

	# --- PlayerModel: shift detection, pressure ratchet
	var PM = load("res://scripts/ai/PlayerModel.gd")
	var pm = PM.new()
	for w in range(12):
		for i in range(40):
			pm.log_damage("FIRE", 20.0)
			pm.log_kill("FIRE")
		pm.end_wave(10.0, 500.0) # barely scratched every wave
	_check("a dominated player ratchets pressure up (%.2f)" % pm.pressure, pm.pressure > 1.0)
	_check("pure-FIRE habit: recent share ~1", pm.recent_damage_share("FIRE") > 0.99)
	var p_before = pm.pressure
	var shifted_once = false
	for w in range(8):
		for i in range(40):
			pm.log_damage("ICE", 20.0)
			pm.log_kill("ICE")
		var r = pm.end_wave(10.0, 500.0)
		shifted_once = shifted_once or r["shifted"]
	_check("switching to ICE is detected as a playstyle shift", shifted_once and pm.shift_count >= 1)
	_check("recent model now targets ICE", pm.recent_top_damage_element() == "ICE")
	var pm2 = PM.new()
	for w in range(6):
		pm2.log_damage("FIRE", 400.0)
		pm2.end_wave(450.0, 500.0) # nearly dead each wave
	_check("a struggling player gets relief (pressure stays ~0: %.2f)" % pm2.pressure, pm2.pressure < 0.2)
	var pm3 = PM.new()
	pm3.from_dict(pm.to_dict())
	_check("player model round-trips", is_equal_approx(pm3.pressure, pm.pressure) and pm3.shift_count == pm.shift_count)
	_check("pressure is bounded", pm.pressure <= PM.MAX_PRESSURE)

	# --- lineage + cull cleanup
	var dir2 = DirectorScript.new()
	var SquadTemplateScript = load("res://scripts/ai/SquadTemplate.gd")
	var parent_t = SquadTemplateScript.new()
	parent_t.template_name = "Parent"
	parent_t.required_roles = {"sniper": 1, "brawler": 2}
	var child_t = SquadTemplateScript.new()
	child_t.template_name = "Child"
	child_t.parent_name = "Parent"
	child_t.required_roles = {"sniper": 1, "jammer": 1}
	for spec in [["sniper", 0], ["brawler", 0], ["brawler", 1]]:
		var b = StockBuildScript.new("Parent", spec[0], 1)
		b.sub_archetype_slot = spec[1]
		b.serialized_components = {0: {"x": spec[0]}}
		b.solver_profile_name = "P1"
		dir2.stock_builds.append(b)
	var n = dir2.inherit_parent_builds(child_t)
	_check("child inherits only roles it shares (sniper), got %d" % n, n == 1)
	var inh = dir2.stock_builds[dir2.stock_builds.size() - 1]
	_check("inherited build is a copy under the child's name with provenance", inh.template_name == "Child" and inh.role == "sniper" and inh.solver_profile_name == "P1" and inh.parent_name == "Parent:sniper")
	inh.serialized_components[0]["x"] = "mutated"
	_check("inherited build does not alias the parent's data", dir2.stock_builds[0].serialized_components[0]["x"] == "sniper")
	dir2.drop_stock_builds_for("Child")
	_check("dropping a culled template's builds leaves the parent's intact", dir2.stock_builds.size() == 3)
	dir2.free()

	print("credit check done, failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
