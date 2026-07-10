extends Node

# Reproduction test for "turning off Mythic Magnet repel mode stops loot
# attraction" - builds a minimal Core -> Magnet grid directly (no Garage UI
# involved) and reads total_magnetic_power with repel_mode true vs false, to
# find out whether the underlying computation actually differs. Safe to
# delete once the bug is found/fixed.

const MechScript = preload("res://scripts/entities/Mech.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTile = preload("res://scripts/tiles/CoreTile.gd")
const MagnetTile = preload("res://scripts/tiles/MagnetTile.gd")

func _ready():
	var mech = MechScript.new()
	mech.is_player = true
	add_child(mech)

	# Replace the starter torso with a minimal custom one: Core at (0,0)
	# feeding directly into a Mythic Magnet at (1,0) - Core's default active
	# face is direction 0, which is exactly the (1,0) neighbor, so this is a
	# single, unambiguous hop with no conduits/routing ambiguity involved.
	var torso = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.MYTHIC)
	torso.component_name = "TestTorso"

	var core = CoreTile.new()
	core.body_slot = HexTile.BodySlot.TORSO
	torso.hex_grid.add_tile(HexCoord.new(0, 0), core)

	var magnet = MagnetTile.new()
	magnet.body_slot = HexTile.BodySlot.TORSO
	magnet.rarity = HexTile.Rarity.MYTHIC
	torso.hex_grid.add_tile(HexCoord.new(1, 0), magnet)

	mech.equip_component(torso)
	mech._recalculate_grid()
	print("--- repel_mode = false ---")
	print("magnet.repel_mode: ", magnet.repel_mode)
	print("mech.magnet_repel_mode: ", mech.magnet_repel_mode)
	print("mech.total_magnetic_power: ", mech.total_magnetic_power)

	magnet.toggle_repel_mode()
	mech.is_grid_dirty = true
	mech._recalculate_grid()
	print("--- repel_mode = true ---")
	print("magnet.repel_mode: ", magnet.repel_mode)
	print("mech.magnet_repel_mode: ", mech.magnet_repel_mode)
	print("mech.total_magnetic_power: ", mech.total_magnetic_power)

	magnet.toggle_repel_mode()
	mech.is_grid_dirty = true
	mech._recalculate_grid()
	print("--- repel_mode = false again (toggled back off) ---")
	print("magnet.repel_mode: ", magnet.repel_mode)
	print("mech.magnet_repel_mode: ", mech.magnet_repel_mode)
	print("mech.total_magnetic_power: ", mech.total_magnetic_power)

	get_tree().quit()
