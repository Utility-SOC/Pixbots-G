extends Node

# Regression harness for: "simulate energy flow is broken for extremities
# again." Drives the REAL Garage flow (GarageSimulationRunner._compute_
# initial_packets, the exact code the "Simulate Energy Flow" button and the
# silent per-tab snapshot both call) against an auto-generated starter torso
# + arm, instead of a hand-built grid - to catch anything the torso-link
# spoke-tip placement change (or the newly-enabled Rust sim path) broke
# specifically for cross-component (Torso -> peripheral) transfers.

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const GarageMenuScript = preload("res://scripts/ui/GarageMenu.gd")
const GarageGridRendererScript = preload("res://scripts/ui/GarageGridRenderer.gd")
const GarageSimulationRunnerScript = preload("res://scripts/ui/GarageSimulationRunner.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _make_garage(torso, peripheral, slot):
	var garage = GarageMenuScript.new()
	add_child(garage)
	garage.mech_components = {HexTile.BodySlot.TORSO: torso, slot: peripheral}
	garage.active_component = peripheral
	garage.stats_label = Label.new()
	garage.add_child(garage.stats_label)
	garage.grid_renderer = GarageGridRendererScript.new()
	garage.add_child(garage.grid_renderer)
	garage.grid_renderer.setup(peripheral.hex_grid, garage, peripheral.valid_hexes)
	garage.grid_renderer.active_component = peripheral
	garage.simulation_runner = GarageSimulationRunnerScript.new(garage)
	return garage

func _ready():
	var HexTileCls = load("res://scripts/core/HexTile.gd")

	# Every limb, aimed via the Core's active face at that limb's own spoke
	# direction (mirrors a player routing power there) - the exact spoke
	# mapping ComponentEquipment.create_starter_torso now uses.
	var spoke_dirs := {
		HexTile.BodySlot.ARM_R: 0, HexTile.BodySlot.LEG_R: 1, HexTile.BodySlot.LEG_L: 2,
		HexTile.BodySlot.ARM_L: 3, HexTile.BodySlot.HEAD: 4, HexTile.BodySlot.BACKPACK: 5,
	}
	var limb_ctors = {
		HexTile.BodySlot.ARM_L: func(): return ComponentEquipmentScript.create_starter_arm(true),
		HexTile.BodySlot.ARM_R: func(): return ComponentEquipmentScript.create_starter_arm(false),
		HexTile.BodySlot.LEG_L: func(): return ComponentEquipmentScript.create_starter_leg(true),
		HexTile.BodySlot.LEG_R: func(): return ComponentEquipmentScript.create_starter_leg(false),
		HexTile.BodySlot.HEAD: func(): return ComponentEquipmentScript.create_starter_head(),
	}

	for limb in limb_ctors:
		var torso = ComponentEquipmentScript.create_starter_torso()
		var core = torso.hex_grid.get_tile(HexCoord.new(0, 0))
		core.active_faces.clear()
		core.active_faces.append(spoke_dirs[limb])

		var peripheral = limb_ctors[limb].call()
		var garage = _make_garage(torso, peripheral, limb)

		var packets = garage.simulation_runner._compute_initial_packets()
		var slot_name = HexTileCls.BodySlot.keys()[limb]
		_check("[%s] Simulate produces a nonzero transfer packet from the Torso" % slot_name,
			not packets.is_empty() and packets.any(func(p): return p.magnitude > 0.0))

	if failures == 0:
		print("PASS: every limb receives a real Torso->peripheral transfer through the actual Garage Simulate flow")
	get_tree().quit(0 if failures == 0 else 1)
