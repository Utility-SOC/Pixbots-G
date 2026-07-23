extends Node

# Regression harness for: "I run the simulation in the torso - I stop the
# simulation. I switch to the left arm. I simulate. It works perfectly...
# but then, if I try to start it again there is nothing, no energy is
# entering from the torso anymore. Now I run the torso simulation again,
# stop it, and switch to the left arm, once more it successfully models
# everything."
#
# Root cause: GarageSimulationRunner._compute_initial_packets() runs a
# throwaway "dummy" Mech._simulate_grid() pass over the Torso's REAL,
# persistent hex_grid every single time a non-Torso component is viewed or
# re-simulated (to compute the cross-component transfer). It never reset
# simulation state on those tiles first - so stateful tiles (Resonator/
# Mythic Splitter remnants, Catalyst gate counters) kept drifting further
# from their true value with every Simulate press on a peripheral, with no
# way back short of revisiting the Torso tab (whose own _discover_total_
# steps call happens to reset whatever grid is CURRENTLY active - which
# only coincidentally fixes it because that grid happens to be the Torso's
# at that moment). Fixed by resetting simulation state on every grid right
# before each dummy _simulate_grid pass in _compute_initial_packets, so
# each preview computation is a true, deterministic function of the tiles'
# configured (non-simulation-transient) state, not of how many times the
# player has pressed Simulate before.

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")
const ComponentLinkTileScript = preload("res://scripts/tiles/ComponentLinkTile.gd")
const WeaponMountTileScript = preload("res://scripts/tiles/WeaponMountTile.gd")
const ResonatorTileScript = preload("res://scripts/tiles/ResonatorTile.gd")
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
	# Torso: Core -> (Legendary, non-Mythic) Resonator -> Left Arm Link.
	# The Resonator's baseline-remnant path is the exact stateful mechanic
	# the reported bug depends on - see class comment above.
	var torso = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.COMMON)
	var torso_hexes: Array[HexCoord] = [HexCoord.new(0, 0), HexCoord.new(-1, 0), HexCoord.new(-2, 0)]
	torso.valid_hexes = torso_hexes
	torso._rebuild_valid_hex_set()
	var core = CoreTileScript.new()
	core.body_slot = HexTile.BodySlot.TORSO
	core.active_faces.clear()
	core.active_faces.append(3) # West, toward the Resonator/Arm Link
	torso.hex_grid.add_tile(HexCoord.new(0, 0), core)
	var resonator = ResonatorTileScript.new()
	resonator.body_slot = HexTile.BodySlot.TORSO
	resonator.rarity = HexTile.Rarity.LEGENDARY
	torso.hex_grid.add_tile(HexCoord.new(-1, 0), resonator)
	var l_arm_sink = ComponentLinkTileScript.new(HexTile.BodySlot.ARM_L, true)
	l_arm_sink.body_slot = HexTile.BodySlot.TORSO
	torso.hex_grid.add_tile(HexCoord.new(-2, 0), l_arm_sink)

	var arm = ComponentEquipmentScript.new(HexTile.BodySlot.ARM_L, HexTile.Rarity.COMMON)
	var arm_hexes: Array[HexCoord] = [HexCoord.new(0, 0), HexCoord.new(1, 0)]
	arm.valid_hexes = arm_hexes
	arm._rebuild_valid_hex_set()
	var intake = ComponentLinkTileScript.new()
	intake.tile_type = "Energy Intake"
	arm.hex_grid.add_tile(HexCoord.new(0, 0), intake)
	var mount = WeaponMountTileScript.new()
	arm.hex_grid.add_tile(HexCoord.new(1, 0), mount)

	var garage = GarageMenuScript.new()
	add_child(garage)
	garage.mech_components = {HexTile.BodySlot.TORSO: torso, HexTile.BodySlot.ARM_L: arm}
	garage.stats_label = Label.new()
	garage.add_child(garage.stats_label)
	garage.grid_renderer = GarageGridRendererScript.new()
	garage.add_child(garage.grid_renderer)
	garage.simulation_runner = GarageSimulationRunnerScript.new(garage)

	# Step 1: view + simulate the Torso, then stop (exactly like the report).
	garage.active_component = torso
	garage.grid_renderer.setup(torso.hex_grid, garage, torso.valid_hexes)
	garage.grid_renderer.active_component = torso
	var torso_transfer_magnitude = _sync_run_and_drain(garage)
	garage.is_simulating = false
	_check("the torso's own view produced a real, nonzero transfer packet",
		torso_transfer_magnitude > 0.0)

	# Step 2: switch to the Left Arm (mirrors _on_tab_changed's silent snapshot).
	garage.active_component = arm
	garage.grid_renderer.setup(arm.hex_grid, garage, arm.valid_hexes)
	garage.grid_renderer.active_component = arm
	garage.simulation_runner.run_silent_snapshot()

	# Step 3: first explicit Simulate press on the Arm ("it works perfectly").
	var first_magnitude = _sync_run_and_drain(garage)
	garage.is_simulating = false
	_check("the first Arm simulate receives a real, nonzero transfer from the Torso",
		first_magnitude > 0.0)

	# Step 4: second explicit Simulate press, no tab switch in between - the
	# exact "I try to start it again" step from the report.
	var second_magnitude = _sync_run_and_drain(garage)
	garage.is_simulating = false
	_check("the second Arm simulate STILL receives a real, nonzero transfer",
		second_magnitude > 0.0)
	_check("repeated Arm-only Simulate presses no longer drift the transfer magnitude (Resonator remnant reset each pass)",
		abs(second_magnitude - first_magnitude) < 0.01)

	if failures == 0:
		print("PASS: re-simulating a peripheral repeatedly (without revisiting the Torso) stays deterministic - no more drift, no more energy silently vanishing")
	get_tree().quit(0 if failures == 0 else 1)

# Synchronous equivalent of GarageSimulationRunner.run_simulation() minus
# the async animated step() tail (which needs real engine frames to fire
# its timer) - runs the same _compute_initial_packets/_discover_total_steps
# prefix, which is where the real tile side effects happen, then drains the
# live view the same way the animated playback eventually would. Returns
# the total magnitude of whatever WeaponMountTile.pending_packets ends up
# holding on the arm's Weapon Mount.
func _sync_run_and_drain(garage) -> float:
	garage.is_simulating = true
	var sr = garage.simulation_runner
	var initial_packets = sr._compute_initial_packets()
	for p in initial_packets:
		p.is_active = true
	sr._initial_packets_snapshot = sr._clone_packets(initial_packets)
	sr.total_steps = sr._discover_total_steps()
	garage.grid_renderer.active_packets = initial_packets
	garage.grid_renderer.simulation_step = 0
	var n = 0
	while n < 200 and not garage.grid_renderer.active_packets.is_empty():
		sr._advance_step()
		n += 1

	if garage.active_component.slot_type == HexTile.BodySlot.TORSO:
		var sink = garage.active_component.hex_grid.get_tile(HexCoord.new(-2, 0))
		var total = 0.0
		for p in sink.pending_transfer_packets:
			total += p.magnitude
		return total

	var mount = garage.active_component.hex_grid.get_tile(HexCoord.new(1, 0))
	var total = 0.0
	for entry in mount.pending_packets:
		total += entry.packet.magnitude
	return total
