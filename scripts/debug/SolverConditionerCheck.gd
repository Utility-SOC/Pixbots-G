extends Node

const CompScript = preload("res://scripts/core/ComponentEquipment.gd")
const SolverScript = preload("res://scripts/core/AutoEquipSolver.gd")
const CatalystScript = preload("res://scripts/tiles/CatalystTile.gd")
const AmpScript = preload("res://scripts/tiles/AmplifierTile.gd")
const InfuserScript = preload("res://scripts/tiles/InfuserTile.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _inv() -> Array:
	var inv: Array = []
	for i in range(3):
		inv.append(CatalystScript.new())
		inv.append(AmpScript.new())
		inv.append(InfuserScript.new())
	return inv

func _types(comp) -> Array:
	var out = []
	for t in comp.hex_grid.get_all_tiles():
		out.append(t.tile_type)
	return out

func _ready():
	var solver = SolverScript.new()
	var pack = CompScript.create_starter_backpack("", HexTile.Rarity.RARE)
	var inv = _inv()
	solver.solve(pack, inv)
	var types = _types(pack)
	_check("backpack gets conditioner tiles (%s)" % str(types), types.has("Catalyst") or types.has("Amplifier") or types.has("Elemental Infuser"))
	if types.has("Catalyst") or types.has("Amplifier") or types.has("Elemental Infuser"):
		var first_cond = ""
		for t in types:
			if t in ["Catalyst", "Amplifier", "Elemental Infuser"]:
				first_cond = t
				break
		_check("catalyst is preferred on the backpack (%s)" % first_cond, types.has("Catalyst"))
	var head = CompScript.create_starter_head("", HexTile.Rarity.RARE)
	var inv2 = _inv()
	solver.solve(head, inv2)
	_check("head solves without losing its fixed tiles", _types(head).has("Torso Return") and _types(head).has("Energy Intake"))
	# different slots must not share cached topology
	var arm = CompScript.create_starter_backpack("", HexTile.Rarity.RARE)
	var k1 = solver._topology_cache_key(pack, _inv(), null)
	pack.slot_type = HexTile.BodySlot.HEAD
	var k2 = solver._topology_cache_key(pack, _inv(), null)
	_check("cache key distinguishes slots", k1 != k2)
	print("solver conditioner check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
