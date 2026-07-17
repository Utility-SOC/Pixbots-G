extends Node

# Regression harness for Velocity Works' MobilityCoreTile (Corporate
# Sponsorships, task #17): the self-contained-reactor grant works
# UNCONDITIONALLY from mere equipped presence - no energy routing required,
# unlike every other ability tile in the game.

const MechScript = preload("res://scripts/entities/Mech.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")
const MobilityCoreTileScript = preload("res://scripts/tiles/brands/MobilityCoreTile.gd")

var failures = 0

func _check(label: String, actual, expected):
	if actual != expected:
		push_error("FAIL: %s - got %s, expected %s" % [label, actual, expected])
		failures += 1
	else:
		print("ok: %s = %s" % [label, actual])

func _ready():
	var world = Node2D.new()
	add_child(world)

	# --- 1. Equipping grants jumpjet/thruster capacity with ZERO energy
	# routed - the whole point of "self-contained reactor" ------------------
	var mech = MechScript.new()
	mech.is_player = false
	world.add_child(mech)
	mech.set_physics_process(false)

	# A deliberately EMPTY backpack aside from the Core + mobility tile - no
	# Splitter/Reflector to route power anywhere, no packets will ever reach
	# this tile through the grid.
	var backpack = ComponentEquipmentScript.new(HexTile.BodySlot.BACKPACK, HexTile.Rarity.MYTHIC)
	backpack.generate_shape()
	var core = CoreTileScript.new()
	core.rarity = HexTile.Rarity.MYTHIC
	backpack.hex_grid.add_tile(HexCoord.new(0, 0), core)
	var mobility = MobilityCoreTileScript.new()
	mobility.rarity = HexTile.Rarity.MYTHIC
	mobility.brand_id = "mobility"
	backpack.hex_grid.add_tile(HexCoord.new(1, 0), mobility)
	mech.equip_component(backpack)
	mech._recalculate_grid()

	_check("jumpjet_rarity granted unconditionally", mech.jumpjet_rarity, HexTile.Rarity.MYTHIC)
	_check("thruster_accel_bonus granted unconditionally", mech.thruster_accel_bonus, HexTile.Rarity.MYTHIC)
	_check("_has_jumpjets() reflects the unconditional grant", mech._has_jumpjets(), true)

	# --- 2. Unequipping resets it (no stale grant survives a loadout change) ---
	mech.unequip_component(HexTile.BodySlot.BACKPACK)
	mech._recalculate_grid()
	_check("unequipping clears jumpjet_rarity", mech.jumpjet_rarity, -1)
	_check("unequipping clears thruster_accel_bonus", mech.thruster_accel_bonus, -1)
	_check("_has_jumpjets() reflects the loss", mech._has_jumpjets(), false)

	# --- 3. A tile with the SAME tile_type but no brand_id must NOT grant
	# anything - only a real brand-tagged drop should trigger this ----------
	var plain_mech = MechScript.new()
	plain_mech.is_player = false
	world.add_child(plain_mech)
	plain_mech.set_physics_process(false)
	var plain_backpack = ComponentEquipmentScript.new(HexTile.BodySlot.BACKPACK, HexTile.Rarity.RARE)
	plain_backpack.generate_shape()
	var plain_core = CoreTileScript.new()
	plain_core.rarity = HexTile.Rarity.RARE
	plain_backpack.hex_grid.add_tile(HexCoord.new(0, 0), plain_core)
	var unbranded = MobilityCoreTileScript.new() # same script, but brand_id left ""
	unbranded.rarity = HexTile.Rarity.RARE
	plain_backpack.hex_grid.add_tile(HexCoord.new(1, 0), unbranded)
	plain_mech.equip_component(plain_backpack)
	plain_mech._recalculate_grid()
	_check("an unbranded MobilityCoreTile grants nothing", plain_mech.jumpjet_rarity, -1)

	if failures == 0:
		print("PASS: Velocity Works (Mobility brand) self-contained-reactor grant verified")
	get_tree().quit(0 if failures == 0 else 1)
