extends Node

# Golden-fixture check for the save / loadout component format: seeded solver-built components serialize to the
# exact JSON on disk, and deserialize -> serialize is stable. Keeps the format byte-compatible through the Rust
# port (serde) and any refactor of SaveManager. See SAVE_FORMAT_VERSION in SaveManager.gd for the format log.
#   run:      godot --headless --path . res://scripts/debug/SaveGoldenCheck.tscn
#   re-bless: PIXBOTS_UPDATE_GOLDEN=1 godot --headless --path . res://scripts/debug/SaveGoldenCheck.tscn
# Fixture: golden/save_golden.json. Re-bless ONLY for a deliberate format change (and bump SAVE_FORMAT_VERSION).

const SolverGolden = preload("res://scripts/debug/SolverGoldenCheck.gd")
const SolverScript = preload("res://scripts/core/AutoEquipSolver.gd")
const SaveManagerScript = preload("res://scripts/core/SaveManager.gd")
const FIXTURE_PATH = "res://scripts/debug/golden/save_golden.json"
const SEED = 20261009

var failures = 0

func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _norm(v):
	match typeof(v):
		TYPE_FLOAT:
			if v == 0.0 or is_nan(v) or is_inf(v):
				return v
			return snappedf(v, pow(10.0, floor(log(absf(v)) / log(10.0)) - 5.0))
		TYPE_DICTIONARY:
			var d = {}
			for k in v:
				d[str(k)] = _norm(v[k])
			return d
		TYPE_ARRAY:
			var a = []
			for x in v:
				a.append(_norm(x))
			return a
		_:
			return v

func _ser(sm, comp) -> String:
	return JSON.stringify(_norm(sm._serialize_component(comp)), "", true)

func _ready():
	var sm = SaveManagerScript.new()
	var sg = SolverGolden.new()
	var cases = sg._cases()
	var produced: Dictionary = {}
	for name in cases:
		SolverScript._topology_cache.clear()
		SimRng.seed_all(SEED)
		var comp = cases[name][0].call()
		SolverScript.new().solve(comp, sg._inv(), cases[name][1])
		var text = _ser(sm, comp)
		produced[name] = JSON.parse_string(text)
		var back = sm._deserialize_component(sm._serialize_component(comp))
		_check("%s: serialize -> deserialize -> serialize is stable" % name, back != null and _ser(sm, back) == text)
	SimRng.unseed()
	_check("component format carries no version drift (SAVE_FORMAT_VERSION=%d)" % SaveManagerScript.SAVE_FORMAT_VERSION, SaveManagerScript.SAVE_FORMAT_VERSION == 6)

	if OS.get_environment("PIXBOTS_UPDATE_GOLDEN") == "1":
		var f = FileAccess.open(FIXTURE_PATH, FileAccess.WRITE)
		f.store_string(JSON.stringify(produced, "\t", true))
		f.close()
		print("blessed %d save golden cases -> %s" % [produced.size(), FIXTURE_PATH])
	elif not FileAccess.file_exists(FIXTURE_PATH):
		_check("fixture file exists (run with PIXBOTS_UPDATE_GOLDEN=1 once)", false)
	else:
		var expected = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH))
		for name in produced:
			_check("%s matches golden fixture" % name, expected.has(name) and JSON.stringify(produced[name], "", true) == JSON.stringify(expected[name], "", true))
	print("save golden check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
