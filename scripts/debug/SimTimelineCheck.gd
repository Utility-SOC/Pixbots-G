extends Node

# Regression harness for the Garage Simulation Timeline Scrubber + Packet
# Inspector (Status.md queue): the sim replay engine must be genuinely
# deterministic - scrubbing forward, back, and forward again to the SAME
# step must reproduce byte-identical tile/packet state, including on
# tiles with their own mutable simulation state (Resonator path residue,
# Splitter remnant boost, Catalyst gate cadence) - and packet_history must
# stay capped at 5 entries per direction across repeated replays rather
# than silently growing.
#
# Grid: Core Reactor(0,0) -E-> Resonator[Mythic](1,0) -E-> Splitter[Mythic](2,0)
#       -E-> Catalyst(3,0, gate_every_n=2) -E-> Weapon Mount(4,0)
# A straight line keeps every packet on a single deterministic path while
# still exercising all three stateful tile overrides in one run.

const GarageMenuScript = preload("res://scripts/ui/GarageMenu.gd")
const GarageSimulationRunnerScript = preload("res://scripts/ui/GarageSimulationRunner.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")
const ResonatorTileScript = preload("res://scripts/tiles/ResonatorTile.gd")
const SplitterTileScript = preload("res://scripts/tiles/SplitterTile.gd")
const CatalystTileScript = preload("res://scripts/tiles/CatalystTile.gd")
const WeaponMountTileScript = preload("res://scripts/tiles/WeaponMountTile.gd")

func _snapshot_state(comp) -> Dictionary:
	var resonator = comp.hex_grid.get_tile(HexCoord.new(1, 0))
	var splitter = comp.hex_grid.get_tile(HexCoord.new(2, 0))
	var catalyst = comp.hex_grid.get_tile(HexCoord.new(3, 0))
	var mount = comp.hex_grid.get_tile(HexCoord.new(4, 0))
	var mount_total = 0.0
	for item in mount.pending_packets:
		mount_total += item.packet.magnitude
	return {
		"mount_total": mount_total,
		"mount_count": mount.pending_packets.size(),
		"resonator_residue": var_to_str(resonator._path_residue),
		"splitter_remnant": var_to_str(splitter._remnant_magnitudes),
		"catalyst_gate_counter": catalyst._gate_counter,
		"active_packets": comp.get_parent() == null, # placeholder, overwritten below
	}

func _ready():
	var failures = 0
	var world = Node2D.new()
	add_child(world)

	var garage = GarageMenuScript.new()
	world.add_child(garage) # _ready() builds the full UI tree (grid_renderer, sim_scrubber, ...)

	# --- Build the test grid --------------------------------------------
	var comp = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.RARE)
	world.add_child(comp) # HexGridComponent (comp.hex_grid) needs to be inside the tree for _process

	var core = CoreTileScript.new()
	core.rarity = HexTile.Rarity.RARE
	comp.hex_grid.add_tile(HexCoord.new(0, 0), core)

	var resonator = ResonatorTileScript.new()
	resonator.rarity = HexTile.Rarity.MYTHIC
	comp.hex_grid.add_tile(HexCoord.new(1, 0), resonator)

	var splitter = SplitterTileScript.new()
	splitter.rarity = HexTile.Rarity.MYTHIC
	var single_face: Array[int] = [0] # single output East, keep it a straight line
	splitter.active_faces = single_face
	comp.hex_grid.add_tile(HexCoord.new(2, 0), splitter)

	var catalyst = CatalystTileScript.new()
	catalyst.target_synergy = EnergyPacket.SynergyType.FIRE
	catalyst.gate_every_n = 2 # skip every other packet - exercises _gate_counter across steps
	comp.hex_grid.add_tile(HexCoord.new(3, 0), catalyst)

	var mount = WeaponMountTileScript.new()
	mount.rarity = HexTile.Rarity.UNCOMMON
	comp.hex_grid.add_tile(HexCoord.new(4, 0), mount)

	garage.active_component = comp
	garage.mech_components = {HexTile.BodySlot.TORSO: comp}
	garage.grid_renderer.setup(comp.hex_grid, garage, comp.valid_hexes)

	# --- Run once to seed the snapshot + discover total_steps ------------
	garage.simulation_runner = GarageSimulationRunnerScript.new(garage)
	garage.simulation_runner.run_simulation()
	# Prevent the still-pending timer coroutine (suspended at its first
	# await) from racing with the synchronous assertions below when it
	# eventually wakes up - see step()'s "if not garage.is_simulating" bail.
	garage.is_simulating = false
	var runner = garage.simulation_runner

	if runner.total_steps <= 0 or runner._initial_packets_snapshot.is_empty():
		push_error("FAIL: sim produced no steps/packets - total_steps=%d snapshot=%d" % [runner.total_steps, runner._initial_packets_snapshot.size()])
		get_tree().quit(1)
		return
	print("1) sim ran: total_steps=%d, %d packets at step 0" % [runner.total_steps, runner._initial_packets_snapshot.size()])

	if not garage.sim_scrubber.visible or int(garage.sim_scrubber.max_value) != runner.total_steps:
		push_error("FAIL: scrubber UI not synced (visible=%s max=%s expected=%d)" % [garage.sim_scrubber.visible, garage.sim_scrubber.max_value, runner.total_steps])
		failures += 1
	else:
		print("2) scrubber UI: visible, max_value == total_steps (%d)" % runner.total_steps)

	# --- Determinism: seek to the end, capture state, seek away, seek back ---
	runner.seek_to_step(runner.total_steps)
	var ref_a = _snapshot_state(comp)
	if ref_a.mount_count == 0:
		push_error("FAIL: weapon mount never received any packets by the final step")
		failures += 1

	runner.seek_to_step(1)
	var mid_state = _snapshot_state(comp)
	var actually_changed = mid_state.mount_count != ref_a.mount_count or mid_state.catalyst_gate_counter != ref_a.catalyst_gate_counter
	if not actually_changed:
		push_error("FAIL: scrubbing to step 1 produced identical state to the final step - scrubber isn't actually moving")
		failures += 1
	else:
		print("3) seek(1) genuinely differs from seek(total): mount_count %d -> %d" % [ref_a.mount_count, mid_state.mount_count])

	runner.seek_to_step(runner.total_steps)
	var ref_b = _snapshot_state(comp)
	var identical = (ref_a.mount_total == ref_b.mount_total
		and ref_a.mount_count == ref_b.mount_count
		and ref_a.resonator_residue == ref_b.resonator_residue
		and ref_a.splitter_remnant == ref_b.splitter_remnant
		and ref_a.catalyst_gate_counter == ref_b.catalyst_gate_counter)
	if not identical:
		push_error("FAIL: forward->back->forward replay diverged: %s vs %s" % [ref_a, ref_b])
		failures += 1
	else:
		print("4) determinism: seek(total)->seek(1)->seek(total) reproduces byte-identical tile state")

	# --- Clamping ------------------------------------------------------------
	runner.seek_to_step(999999)
	var clamped_high_ok = garage.grid_renderer.simulation_step <= runner.total_steps
	runner.seek_to_step(-5)
	var clamped_low_ok = garage.grid_renderer.simulation_step == 0
	if not clamped_high_ok or not clamped_low_ok:
		push_error("FAIL: seek_to_step didn't clamp out-of-range targets (high_ok=%s low_ok=%s)" % [clamped_high_ok, clamped_low_ok])
		failures += 1
	else:
		print("5) seek_to_step clamps to [0, total_steps]")

	# --- packet_history stays capped across repeated replays -----------------
	runner.seek_to_step(runner.total_steps)
	var hist_after_one = mount.packet_history.get(3, []).size() # direction 3 = West = entry into the mount from the East-heading chain
	for i in range(5):
		runner.seek_to_step(runner.total_steps)
	var hist_after_many = mount.packet_history.get(3, []).size()
	if hist_after_one > HexTile.PACKET_HISTORY_CAP or hist_after_many > HexTile.PACKET_HISTORY_CAP or hist_after_many != hist_after_one:
		push_error("FAIL: packet_history leaked across replays (after 1 replay: %d, after 6: %d, cap: %d)" % [hist_after_one, hist_after_many, HexTile.PACKET_HISTORY_CAP])
		failures += 1
	else:
		print("6) packet_history stays capped at <= %d entries across repeated replays (%d)" % [HexTile.PACKET_HISTORY_CAP, hist_after_many])

	# --- UI invalidation on grid clear ----------------------------------------
	garage._on_clear_grid_pressed()
	if garage.sim_scrubber.visible:
		push_error("FAIL: clearing the grid didn't hide the scrubber")
		failures += 1
	else:
		print("7) clearing the grid hides the (now-stale) scrubber")

	if failures == 0:
		print("PASS: simulation timeline - deterministic replay, UI sync, packet_history cap, invalidation")
	get_tree().quit(0 if failures == 0 else 1)
