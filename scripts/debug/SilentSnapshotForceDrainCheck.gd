extends Node

# Regression harness for a real bug in the earlier silent-snapshot fix:
# "the instant I enter the garage, the simulation is already running" /
# "I go to any component, a random packet shows up... when I go back to
# the torso it is already simulating, even if I stopped it before
# switching components."
#
# run_silent_snapshot() reused _discover_total_steps(), whose
# DISCOVERY_STEP_CAP (200) only guarantees active_packets ends up empty
# when the sim naturally finishes within that many steps - fine for its
# original job (an APPROXIMATE scrubber range), wrong for "leave it fully
# at rest." A build complex enough (or, as tested here, a genuine closed
# bounce loop that never naturally terminates - same class of problem
# Mech._simulate_grid's own step cap exists for) left real mid-flight
# packets visible, which read as "still actively simulating" even though
# nothing was ever started.

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")
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

func _ready():
	# A deliberately unwinnable 1-hex component: the Core's only active
	# face (0/East) has no neighbor in its own 1-tile valid_hexes, so every
	# step hits the "edge bounce: reflect 180 degrees" branch, which never
	# reduces magnitude - the packet alternates direction forever and can
	# never reach the 0.5-magnitude death floor or find a real exit. This
	# guarantees _discover_total_steps() hits its DISCOVERY_STEP_CAP
	# without ever draining naturally, exactly the case the old code got
	# wrong.
	var torso = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.COMMON)
	var only_hex: Array[HexCoord] = [HexCoord.new(0, 0)]
	torso.valid_hexes = only_hex
	torso._rebuild_valid_hex_set()
	var core = CoreTileScript.new()
	core.body_slot = HexTile.BodySlot.TORSO
	torso.hex_grid.add_tile(HexCoord.new(0, 0), core)

	var garage = GarageMenuScript.new()
	add_child(garage)
	garage.mech_components = {HexTile.BodySlot.TORSO: torso}
	garage.active_component = torso
	garage.stats_label = Label.new()
	garage.add_child(garage.stats_label)

	garage.grid_renderer = GarageGridRendererScript.new()
	garage.add_child(garage.grid_renderer)
	garage.grid_renderer.setup(torso.hex_grid, garage, torso.valid_hexes)
	garage.grid_renderer.active_component = torso

	garage.simulation_runner = GarageSimulationRunnerScript.new(garage)
	garage.simulation_runner.run_silent_snapshot()

	_check("the never-draining bounce loop actually hit the discovery step cap (proves this scenario doesn't naturally finish)",
		garage.simulation_runner.total_steps >= GarageSimulationRunnerScript.DISCOVERY_STEP_CAP)
	_check("run_silent_snapshot() force-clears active_packets even when the replay never naturally drained",
		garage.grid_renderer.active_packets.is_empty())
	_check("run_silent_snapshot() resets simulation_step to 0 (nothing visibly 'still running')",
		garage.grid_renderer.simulation_step == 0)
	_check("is_simulating stays false throughout - this was never a real animated run",
		garage.is_simulating == false)

	if failures == 0:
		print("PASS: the silent snapshot never leaves stray mid-flight packets visible, even on a build that can't naturally drain")
	get_tree().quit(0 if failures == 0 else 1)
