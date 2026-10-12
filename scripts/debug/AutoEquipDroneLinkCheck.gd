extends Node

# The Drone Bay's link is real power now (it feeds the drone's reactor, capped by bay rarity): the solver recognises a
# bay backpack and leads its path filler with Amplifiers; the cap table rises with rarity.

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const SolverProfile = preload("res://scripts/ai/SolverProfile.gd")
const AutoEquipSolverScript = preload("res://scripts/core/AutoEquipSolver.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	var solver = AutoEquipSolverScript.new()
	var pack = ComponentEquipmentScript.create_drone_backpack(HexTile.Rarity.RARE)
	_check("a drone backpack is recognised", solver._has_drone_bay_sink(pack))
	var plain = ComponentEquipmentScript.create_starter_torso()
	_check("a torso is not", not solver._has_drone_bay_sink(plain))
	_check("the bay link leads with Amplifiers", solver._straight_tile_priority(null, HexTile.BodySlot.BACKPACK, true)[0] == "Amplifier")
	_check("a torso on a mech with a bay amplifies first, even with a profile", solver._straight_tile_priority(SolverProfile.new(), HexTile.BodySlot.TORSO, false, true)[0] == "Amplifier")
	_check("a plain backpack keeps Catalyst first", solver._straight_tile_priority(null, HexTile.BodySlot.BACKPACK, false)[0] == "Catalyst")
	var inv: Array = []
	for i in range(3):
		var a = AmplifierTile.new()
		a.rarity = HexTile.Rarity.RARE
		inv.append(a)
		var c = CatalystTile.new()
		c.rarity = HexTile.Rarity.RARE
		inv.append(c)
	solver.solve(pack, inv, null)
	var bay_ok = false
	var amp_placed = false
	for coord in pack.hex_grid.grid:
		var t = pack.hex_grid.grid[coord]
		if t.tile_type == "Drone Bay":
			bay_ok = true
		if t.tile_type == "Amplifier":
			amp_placed = true
	_check("solving keeps the Drone Bay in place", bay_ok)
	_check("an Amplifier is placed on the backpack's path", amp_placed)
	var eff = DroneBayTile.LINK_EFFICIENCY_BY_RARITY
	var rising = true
	for i in range(1, eff.size()):
		if eff[i] <= eff[i - 1]:
			rising = false
	_check("transmission efficiency rises with rarity", rising and eff.size() == 5 and eff[4] < 1.0)
	print("AutoEquipDroneLinkCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
