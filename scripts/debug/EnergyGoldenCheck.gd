extends Node

# Golden-fixture check for the hex-grid energy simulation: fixed grids -> the Rust sim's captures, transfers,
# stores, magnet power, shield synergies, remnants and residues must not drift. Grids are the parity check's
# hand-built torture grids plus the seeded solver cases. Rust-vs-GDScript parity is RustGridSimParityCheck's job;
# this pins the result to disk so the pixbots_core port (docs/RUST_MIGRATION_ROADMAP.md) has a fixed target.
#   run:      godot --headless --path . res://scripts/debug/EnergyGoldenCheck.tscn
#   re-bless: PIXBOTS_UPDATE_GOLDEN=1 godot --headless --path . res://scripts/debug/EnergyGoldenCheck.tscn
# Fixture: golden/energy_golden.json. Floats are stored to 6 significant digits.

const Parity = preload("res://scripts/debug/RustGridSimParityCheck.gd")
const SolverGolden = preload("res://scripts/debug/SolverGoldenCheck.gd")
const RustGridSimScript = preload("res://scripts/core/RustGridSim.gd")
const SolverScript = preload("res://scripts/core/AutoEquipSolver.gd")
const FIXTURE_PATH = "res://scripts/debug/golden/energy_golden.json"
const SEED = 20261009

var failures = 0

func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

# Recursively make a harvest JSON-stable: floats to 6 significant digits, dictionary keys to strings.
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

# Torso-style cores generate their own packets; limb grids start at an Energy Intake that is fed from the torso, so
# those get one plain 10,000 RAW packet entering through the intake's first active face.
func _packets(parity, comp) -> Array:
	var core = comp.hex_grid.get_tile(HexCoord.new(0, 0))
	if core.has_method("generate_energy"):
		return parity._gen_packets(comp)
	var pkt = EnergyPacket.new(10000.0, HexCoord.new(0, 0))
	pkt.direction = int(core.active_faces[0]) if "active_faces" in core and core.active_faces.size() > 0 else 0
	return [pkt]

func _simulate(parity, comp) -> Variant:
	var handled = RustGridSimScript.try_simulate(comp.hex_grid, _packets(parity, comp), true)
	if not handled:
		return null
	return _norm(parity._harvest(comp))

func _ready():
	if not RustGridSimScript.is_available():
		print("SKIP: rust_ext not available")
		get_tree().quit(0)
		return
	var parity = Parity.new()
	var builders = {
		"parity_a": parity._build_component_a, "parity_b": parity._build_component_b,
		"parity_c": parity._build_component_c, "parity_d": parity._build_component_d,
		"parity_e": parity._build_component_e,
	}
	var produced: Dictionary = {}
	for name in builders:
		# Tiles roll a sync shift when their rarity is set (SimRng "tile" stream): seed before every build.
		SimRng.seed_all(SEED)
		var comp = builders[name].call()
		var got = _simulate(parity, comp)
		_check("%s: Rust handled the grid" % name, got != null)
		if got != null:
			produced[name] = got
			SimRng.seed_all(SEED)
			var again = _simulate(parity, builders[name].call())
			var same = JSON.stringify(again, "", true) == JSON.stringify(got, "", true)
			_check("%s: repeat run is identical" % name, same)
			if not same:
				print("DBG1 ", JSON.stringify(got, "", true).left(900))
				print("DBG2 ", JSON.stringify(again, "", true).left(900))
	# Solver-built grids (same seeded cases as SolverGoldenCheck).
	var sg = SolverGolden.new()
	var cases = sg._cases()
	for name in cases:
		SolverScript._topology_cache.clear()
		SimRng.seed_all(SEED)
		var comp = cases[name][0].call()
		SolverScript.new().solve(comp, sg._inv(), cases[name][1])
		var got = _simulate(parity, comp)
		if got == null:
			print("skip: %s is outside the Rust-routed subset" % name)
			continue
		produced["solver_" + name] = got
	SimRng.unseed()
	_check("collected %d energy cases" % produced.size(), produced.size() >= 5)

	if OS.get_environment("PIXBOTS_UPDATE_GOLDEN") == "1":
		var f = FileAccess.open(FIXTURE_PATH, FileAccess.WRITE)
		f.store_string(JSON.stringify(produced, "\t", true))
		f.close()
		print("blessed %d energy golden cases -> %s" % [produced.size(), FIXTURE_PATH])
	elif not FileAccess.file_exists(FIXTURE_PATH):
		_check("fixture file exists (run with PIXBOTS_UPDATE_GOLDEN=1 once)", false)
	else:
		var expected = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH))
		for name in produced:
			var got = JSON.parse_string(JSON.stringify(produced[name]))
			_check("%s matches golden fixture" % name, expected.has(name) and JSON.stringify(got, "", true) == JSON.stringify(expected[name], "", true))
		for name in expected:
			_check("%s still produced" % name, produced.has(name))
	print("energy golden check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
