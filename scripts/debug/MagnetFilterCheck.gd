extends Node

# A Mythic Magnet's rarity filter must not narrow the other magnets: if any powered magnet has no filter, the mech
# attracts every rarity; with only filtered magnets the most permissive filter wins.

const MechScript = preload("res://scripts/entities/Mech.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTile = preload("res://scripts/tiles/CoreTile.gd")
const MagnetTile = preload("res://scripts/tiles/MagnetTile.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _mech(filters: Array):
	var mech = MechScript.new()
	mech.is_player = true
	add_child(mech)
	var slots = [HexTile.BodySlot.TORSO, HexTile.BodySlot.ARM_L, HexTile.BodySlot.ARM_R]
	for i in range(filters.size()):
		var comp = ComponentEquipmentScript.new(slots[i], HexTile.Rarity.MYTHIC)
		var core = CoreTile.new()
		core.body_slot = slots[i]
		comp.hex_grid.add_tile(HexCoord.new(0, 0), core)
		var m = MagnetTile.new()
		m.body_slot = slots[i]
		m.rarity = HexTile.Rarity.MYTHIC
		m.min_attract_rarity = filters[i]
		comp.hex_grid.add_tile(HexCoord.new(1, 0), m)
		mech.equip_component(comp)
	return mech

func _ready():
	var m1 = _mech([2])
	m1._recalculate_grid()
	_check("one filtered magnet filters", m1.total_magnetic_power > 0.0 and m1.min_loot_attract_rarity == 2)
	var m2 = _mech([2, -1])
	m2._recalculate_grid()
	_check("an unfiltered magnet beside a filtered one takes everything (%d)" % m2.min_loot_attract_rarity, m2.min_loot_attract_rarity == -1)
	print("MagnetFilterCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
