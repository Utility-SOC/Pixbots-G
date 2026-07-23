extends Node

# Regression harness for: "drone bay present does not populate drone bay
# tab." Root cause: DroneBayTile.find_all_in_backpack (and every caller
# built on it - GarageMenu's Drone tab population, Main.gd's drone
# spawning, ComponentDiagramView's satellite callout) only ever looked in
# the equipped BACKPACK's hex grid. Nothing actually restricts where a
# Drone Bay tile can be placed - forbidden_tile_types is a Black-Market
# drawback blacklist, not a slot-type allowlist, and a looted Drone Bay is
# just a tile the player manually places in any valid hex of any
# component. A bay placed in the Torso (as in the reported screenshot) or
# an Arm/Leg/Head was completely invisible to all three systems - not just
# the Garage's tab list, but ALSO real combat drone-spawning.

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const DroneBayTileScript = preload("res://scripts/tiles/DroneBayTile.gd")
const GarageMenuScript = preload("res://scripts/ui/GarageMenu.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var torso = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.MYTHIC)
	var torso_hexes: Array[HexCoord] = [HexCoord.new(0, 0), HexCoord.new(1, 0)]
	torso.valid_hexes = torso_hexes
	torso._rebuild_valid_hex_set()

	# A Drone Bay placed in the TORSO - not the Backpack. Nothing in the
	# game actually prevents this (see class comment above).
	var bay = DroneBayTileScript.new()
	bay.rarity = HexTile.Rarity.MYTHIC
	bay.body_slot = HexTile.BodySlot.TORSO
	torso.hex_grid.add_tile(HexCoord.new(1, 0), bay)

	var components = {HexTile.BodySlot.TORSO: torso}

	_check("find_all_in_mech finds a Drone Bay placed in the Torso, not just the Backpack",
		DroneBayTileScript.find_all_in_mech(components).size() == 1)

	# The Garage's actual tab-population helper, exercised directly.
	var garage = GarageMenuScript.new()
	add_child(garage)
	garage.mech_components = components
	_check("GarageMenu._find_all_drone_bay_tiles() sees the Torso-placed bay",
		garage._find_all_drone_bay_tiles().size() == 1)

	# spawn_drones_for (the real-combat path) - a fake owner_mech exposing
	# just enough surface (components + global_position) to exercise it.
	var owner_stub = Node2D.new()
	owner_stub.set_script(_make_owner_stub_script())
	owner_stub.components = components
	add_child(owner_stub)
	var parent_node = Node.new()
	add_child(parent_node)
	var spawned = DroneBayTileScript.spawn_drones_for(owner_stub, parent_node)
	_check("spawn_drones_for() spawns a real drone for a Torso-placed Drone Bay",
		spawned.size() == 1)
	for d in spawned:
		d.queue_free()

	if failures == 0:
		print("PASS: a Drone Bay works from any component, not just the Backpack")
	get_tree().quit(0 if failures == 0 else 1)

func _make_owner_stub_script() -> GDScript:
	var src = GDScript.new()
	src.source_code = "extends Node2D\nvar components: Dictionary = {}\n"
	src.reload()
	return src
