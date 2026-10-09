extends Node

# Golden-fixture check for AutoEquipSolver: with SimRng seeded, a fixed component + inventory + profile must
# always produce the same placements. Guards the solver rework and the Rust port (docs/RUST_MIGRATION_ROADMAP.md,
# Status.md prerequisites). Fixtures live in golden/solver_golden.json.
#   run:      godot --headless --path . res://scripts/debug/SolverGoldenCheck.tscn
#   re-bless: PIXBOTS_UPDATE_GOLDEN=1 godot --headless --path . res://scripts/debug/SolverGoldenCheck.tscn
# Only re-bless after a deliberate solver change, and review the JSON diff.

const CompScript = preload("res://scripts/core/ComponentEquipment.gd")
const SolverScript = preload("res://scripts/core/AutoEquipSolver.gd")
const CatalystScript = preload("res://scripts/tiles/CatalystTile.gd")
const AmpScript = preload("res://scripts/tiles/AmplifierTile.gd")
const InfuserScript = preload("res://scripts/tiles/InfuserTile.gd")
const FIXTURE_PATH = "res://scripts/debug/golden/solver_golden.json"
const SEED = 20261009

var failures = 0

func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _inv() -> Array:
	var inv: Array = []
	for i in range(3):
		var c = CatalystScript.new()
		c.rarity = HexTile.Rarity.UNCOMMON + (i % 2)
		inv.append(c)
		var a = AmpScript.new()
		a.rarity = HexTile.Rarity.COMMON + i
		inv.append(a)
		var f = InfuserScript.new()
		f.rarity = HexTile.Rarity.UNCOMMON
		inv.append(f)
	return inv

func _profile(favored: int, pierce: float, secondary: int, mix: float) -> SolverProfile:
	var p = SolverProfile.new()
	p.favored_synergy = favored
	p.pierce_priority = pierce
	p.secondary_synergy = secondary
	p.secondary_mix = mix
	return p

# One case = name -> [component factory, profile]. Everything deterministic given SEED.
func _cases() -> Dictionary:
	var U = HexTile.Rarity.UNCOMMON
	var R = HexTile.Rarity.RARE
	return {
		"arm_uncommon_default": [func(): return CompScript.create_starter_arm(true, "", U), null],
		"arm_rare_default": [func(): return CompScript.create_starter_arm(true, "", R), null],
		"torso_rare_default": [func(): return CompScript.create_starter_torso("", R), null],
		"leg_rare_default": [func(): return CompScript.create_starter_leg(false, "", R), null],
		"head_rare_default": [func(): return CompScript.create_starter_head("", R), null],
		"backpack_rare_default": [func(): return CompScript.create_starter_backpack("", R), null],
		"arm_rare_fire_profile": [func(): return CompScript.create_starter_arm(true, "", R), _profile(EnergyPacket.SynergyType.FIRE, 0.5, EnergyPacket.SynergyType.ICE, 0.5)],
		"torso_rare_pierce_profile": [func(): return CompScript.create_starter_torso("", R), _profile(-1, 0.7, -1, 0.0)],
	}

func _snapshot(comp) -> Array:
	var rows: Array = []
	for t in comp.hex_grid.get_all_tiles():
		var row = {"type": t.tile_type, "rarity": int(t.rarity), "q": t.grid_position.q if t.grid_position else null, "r": t.grid_position.r if t.grid_position else null}
		if "active_faces" in t:
			row["faces"] = t.active_faces.duplicate()
		rows.append(row)
	rows.sort_custom(func(a, b): return [a["q"], a["r"], a["type"]] < [b["q"], b["r"], b["type"]])
	return rows

func _ready():
	var cases = _cases()
	var produced: Dictionary = {}
	for name in cases:
		# The topology cache is static and shared: clear it so each case is a genuine fresh solve.
		SolverScript._topology_cache.clear()
		SimRng.seed_all(SEED)
		var comp = cases[name][0].call()
		SolverScript.new().solve(comp, _inv(), cases[name][1])
		produced[name] = _snapshot(comp)
		# Same seed must reproduce a fresh solve exactly before we compare to disk.
		SolverScript._topology_cache.clear()
		SimRng.seed_all(SEED)
		var comp2 = cases[name][0].call()
		SolverScript.new().solve(comp2, _inv(), cases[name][1])
		_check("%s: fresh solve is deterministic under SimRng" % name, JSON.stringify(_snapshot(comp2)) == JSON.stringify(produced[name]))
		# Cache replay of the plan just stored (no clear) - report only, see Status.md.
		var comp3 = cases[name][0].call()
		SolverScript.new().solve(comp3, _inv(), cases[name][1])
		if JSON.stringify(_snapshot(comp3)) != JSON.stringify(produced[name]):
			print("NOTE: %s: cached-plan replay differs from the fresh solve" % name)
		_check("%s: produced a non-trivial grid (%d tiles)" % [name, produced[name].size()], produced[name].size() >= 2)
	SimRng.unseed()

	if OS.get_environment("PIXBOTS_UPDATE_GOLDEN") == "1":
		var f = FileAccess.open(FIXTURE_PATH, FileAccess.WRITE)
		f.store_string(JSON.stringify(produced, "\t", true))
		f.close()
		print("blessed %d solver golden cases -> %s" % [produced.size(), FIXTURE_PATH])
	else:
		if not FileAccess.file_exists(FIXTURE_PATH):
			_check("fixture file exists (run with PIXBOTS_UPDATE_GOLDEN=1 once)", false)
		else:
			var expected = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH))
			for name in produced:
				var got = JSON.parse_string(JSON.stringify(produced[name]))
				_check("%s matches golden fixture" % name, expected.has(name) and JSON.stringify(got) == JSON.stringify(expected[name]))
	print("solver golden check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
