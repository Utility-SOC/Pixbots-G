class_name GarageSimulationRunner
extends RefCounted

# Energy-flow simulation (Simulate button) - split out of GarageMenu.gd, see
# SightAndSearch.gd/MagnetSystem.gd for the established composed-RefCounted-
# helper pattern this follows. All state (is_simulating, sim_button,
# grid_renderer, active_component, mech_components, stats_label) stays on
# GarageMenu itself - only the behavior that reads/writes it moved here.
# Lazily constructed the first time the Simulate button is pressed (see
# GarageMenu._on_simulate_pressed's wrapper).
#
# _on_simulate_pressed keeps a thin wrapper on GarageMenu (not moved) -
# it's connected directly as a Callable via
# sim_button.pressed.connect(_on_simulate_pressed) in _setup_ui, so it has
# to be reachable as a plain GarageMenu-level method regardless.

var garage: GarageMenu

func _init(p_garage: GarageMenu):
	garage = p_garage

# --- Timeline Scrubber support (Status.md queue) ---------------------------
# The sim is fully deterministic (process_energy has no RNG anywhere in this
# codebase), so the scrubber doesn't buffer history - it re-runs from a
# cached step-0 snapshot up to whatever step the player drags to. Zero
# growing memory cost, and "scrub backward" is exactly as cheap as "scrub
# forward" since both are just "replay from 0 to N."
#
# _initial_packets_snapshot is captured once per Simulate press, right after
# run_simulation()'s setup phase finishes computing this component's actual
# starting packets (Core Reactor generation + any cross-component transfers)
# - the SAME packets seeded into the live view, just independently copied so
# later live-play mutation never touches the replay anchor.
var _initial_packets_snapshot: Array[EnergyPacket] = []
# How many steps until every packet has exited the grid or died out -
# computed once via a throwaway discovery replay right after the snapshot is
# taken, so "how far can I scrub" is never a guess. Drives the scrubber
# HSlider's max_value.
var total_steps: int = 0
const DISCOVERY_STEP_CAP = 200

func run_simulation():
	garage._tutorial_notify("event:simulate_pressed")
	if garage.is_simulating:
		garage.is_simulating = false
		if garage.sim_button: garage.sim_button.text = "Simulate Energy Flow"
		return

	if not garage.grid_renderer.hex_grid: return

	garage.is_simulating = true
	if garage.sim_button: garage.sim_button.text = "Stop Simulation"

	var initial_packets: Array[EnergyPacket] = []

	if garage.active_component:
		# Clear pending packets on current grid before simulating
		for t in garage.active_component.hex_grid.get_all_tiles():
			if "pending_packets" in t:
				t.pending_packets.clear()

		# 1. Generate local energy from any Core Reactors in this component's grid

		for h in garage.grid_renderer.hex_grid.grid.keys():
			var tile = garage.grid_renderer.hex_grid.get_tile(h)
			if tile.has_method("generate_energy"):
				var pkts = tile.generate_energy(garage.grid_renderer.hex_grid)
				for p in pkts:
					p.position = HexCoord.new(h.x, h.y)
				initial_packets.append_array(pkts)

		# 2. Add actual transfer packets from Torso to simulate cross-component energy flow
		if garage.active_component.slot_type != HexTile.BodySlot.TORSO:
			if garage.mech_components.has(HexTile.BodySlot.TORSO) and garage.mech_components[HexTile.BodySlot.TORSO]:
				var torso_comp = garage.mech_components[HexTile.BodySlot.TORSO]
				var t_pkts = []
				for h in torso_comp.hex_grid.grid.keys():
					var tile = torso_comp.hex_grid.get_tile(h)
					if tile.has_method("generate_energy"):
						var pkts = tile.generate_energy(torso_comp.hex_grid)
						for p in pkts: p.position = HexCoord.new(h.x, h.y)
						t_pkts.append_array(pkts)

				var dummy_mech = load("res://scripts/entities/Mech.gd").new()
				dummy_mech._simulate_grid(torso_comp.hex_grid, t_pkts)
				var transfers = dummy_mech._collect_transfers(torso_comp)

				if transfers.has(garage.active_component.slot_type):
					for packet in transfers[garage.active_component.slot_type]:
						var dir = 3 # default west
						if garage.active_component.slot_type == HexTile.BodySlot.ARM_L: dir = 3
						elif garage.active_component.slot_type == HexTile.BodySlot.ARM_R: dir = 0
						elif garage.active_component.slot_type == HexTile.BodySlot.HEAD: dir = 5
						elif garage.active_component.slot_type == HexTile.BodySlot.LEG_L or garage.active_component.slot_type == HexTile.BodySlot.LEG_R: dir = 1
						elif garage.active_component.slot_type == HexTile.BodySlot.BACKPACK: dir = 4

						packet.direction = dir
						var opp_dir = (dir + 3) % 6
						packet.position = HexCoord.new(0, 0).neighbor(opp_dir)
						packet.is_active = true
						initial_packets.append(packet)
				dummy_mech.free()

		# 3. If Torso, pull returning energy from Head and Backpack
		if garage.active_component.slot_type == HexTile.BodySlot.TORSO:
			var dummy_mech = load("res://scripts/entities/Mech.gd").new()

			# We need to simulate the Torso first to find out what it sends out!
			var dummy_t_pkts: Array[EnergyPacket] = []
			for p in initial_packets:
				dummy_t_pkts.append(p.copy())
			dummy_mech._simulate_grid(garage.active_component.hex_grid, dummy_t_pkts)
			var dummy_transfers = dummy_mech._collect_transfers(garage.active_component)

			for p_slot in [HexTile.BodySlot.HEAD, HexTile.BodySlot.BACKPACK]:
				if garage.mech_components.has(p_slot) and garage.mech_components[p_slot]:
					var p_comp = garage.mech_components[p_slot]
					var p_pkts: Array[EnergyPacket] = []

					# 3a. Add energy received from Torso
					if dummy_transfers.has(p_slot):
						var incoming = dummy_transfers[p_slot]
						dummy_mech._route_to_peripheral(incoming, p_comp)
						p_pkts.append_array(incoming)

					# 3b. Add generated energy
					for h in p_comp.hex_grid.grid.keys():
						var tile = p_comp.hex_grid.get_tile(h)
						if tile.has_method("generate_energy"):
							var pkts = tile.generate_energy(p_comp.hex_grid)
							for p in pkts: p.position = HexCoord.new(h.x, h.y)
							p_pkts.append_array(pkts)

					dummy_mech._simulate_grid(p_comp.hex_grid, p_pkts)
					var transfers = dummy_mech._collect_transfers(p_comp)

					if transfers.has(HexTile.BodySlot.TORSO):
						# Find Accessory Return on Torso
						var acc_pos = HexCoord.new(0, 0)
						for coord_v in garage.grid_renderer.hex_grid.grid.keys():
							var t = garage.grid_renderer.hex_grid.grid[coord_v]
							if t.tile_type == "Accessory Return":
								acc_pos = HexCoord.new(coord_v.x, coord_v.y)
								break

						for pkt in transfers[HexTile.BodySlot.TORSO]:
							# Start them one step backwards based on their direction, but wait: we want them to enter the Accessory Return.
							# If we just let them enter with a fixed direction like North (2), they will be processed.
							pkt.direction = 2 # Entering from North
							var opp_dir = (pkt.direction + 3) % 6
							pkt.position = acc_pos.neighbor(opp_dir)
							pkt.is_active = true
							initial_packets.append(pkt)
			dummy_mech.free()

			# Clean up any leftover packets on peripheral weapon mounts so they don't leak
			for p_slot in [HexTile.BodySlot.HEAD, HexTile.BodySlot.BACKPACK]:
				if garage.mech_components.has(p_slot) and garage.mech_components[p_slot]:
					for t in garage.mech_components[p_slot].hex_grid.get_all_tiles():
						if t.tile_type == "Weapon Mount" and "pending_packets" in t:
							t.pending_packets.clear()

	for p in initial_packets:
		p.set_meta("source_hex", p.position)
		p.set_meta("target_hex", p.position)
		p.set_meta("anim_progress", 1.0)
		p.is_active = true

	# Snapshot the real step-0 starting point BEFORE anything below mutates
	# it, then run a throwaway discovery pass to find out how far the
	# scrubber can go - both reuse the exact same _advance_step() engine the
	# live view uses, so "total steps" and "what the scrubber can reach" can
	# never disagree.
	_initial_packets_snapshot = _clone_packets(initial_packets)
	total_steps = _discover_total_steps()
	_update_scrubber_range()

	garage.grid_renderer.active_packets = initial_packets
	garage.grid_renderer.simulation_step = 0

	update_stats()
	step()

# One tick of pure state transition: no timers, no rendering side effects
# beyond what it always did (mutating grid_renderer.active_packets/
# simulation_step directly, same as before this was split out). Shared by
# the live auto-play loop (step(), below) and the scrubber's replay
# (seek_to_step/_discover_total_steps) - a single source of truth for "what
# does one simulation step do," so scrubbed state and live-played state can
# never drift apart.
func _advance_step() -> void:
	var active = garage.grid_renderer.active_packets
	if active.is_empty(): return

	garage.grid_renderer.simulation_step += 1
	var new_packets: Array[EnergyPacket] = []

	for pkt in active:
		if not pkt.is_active: continue
		var pos = pkt.position

		# Animate to next tile
		var dir = pkt.direction
		var next_pos = pos.neighbor(dir)

		var out_pkts = []
		if garage.grid_renderer.hex_grid.has_tile(next_pos):
			var tile = garage.grid_renderer.hex_grid.get_tile(next_pos)
			var entry_dir = (dir + 3) % 6
			# Packet Inspector history (Status.md queue) - recorded on
			# whatever ENTERED this tile, before process_energy transforms
			# it, so the inspector shows what actually arrived.
			tile.record_packet_history(entry_dir, pkt)
			out_pkts = tile.process_energy(pkt, entry_dir)
			for out in out_pkts:
				if out.magnitude < 0.5:
					out.is_active = false
				out.position = next_pos
				out.set_meta("source_hex", pos)
				out.set_meta("target_hex", next_pos)
				out.set_meta("anim_progress", 0.0)
		else:
			var is_valid_empty = false
			if garage.active_component and "valid_hexes" in garage.active_component:
				for h in garage.active_component.valid_hexes:
					if h.q == next_pos.q and h.r == next_pos.r:
						is_valid_empty = true
						break

			if is_valid_empty:
				# Pass straight through empty hex with 5% loss
				pkt.position = next_pos
				pkt.magnitude *= 0.95
				for k in pkt.synergies.keys():
					pkt.synergies[k] *= 0.95
				pkt.set_meta("source_hex", pos)
				pkt.set_meta("target_hex", next_pos)
				pkt.set_meta("anim_progress", 0.0)
				out_pkts = [pkt]
			else:
				# Bounce off edge of component
				pkt.direction = (dir + 3) % 6
				pkt.set_meta("source_hex", pos)
				pkt.set_meta("target_hex", pos)
				pkt.set_meta("anim_progress", 0.0)
				out_pkts = [pkt]

		new_packets.append_array(out_pkts)

	var merged_packets: Array[EnergyPacket] = []
	var packet_map: Dictionary = {}

	for pkt in new_packets:
		if not pkt.is_active: continue
		var key = str(pkt.position.q) + "_" + str(pkt.position.r) + "_" + str(pkt.direction)
		if packet_map.has(key):
			packet_map[key].merge(pkt)
		else:
			packet_map[key] = pkt
			merged_packets.append(pkt)

	garage.grid_renderer.active_packets = merged_packets

func step():
	_advance_step()
	update_stats()
	_sync_scrubber_to_live_step()

	# Auto step loop
	var tree = garage.get_tree()
	if tree:
		await tree.create_timer(0.5).timeout
		if not garage.is_simulating:
			garage.grid_renderer.active_packets.clear()
			update_stats()
			return

		var still_alive = false
		for p in garage.grid_renderer.active_packets:
			if garage.grid_renderer.hex_grid.has_tile(p.position):
				still_alive = true
				break
		if still_alive:
			step()
		else:
			garage.is_simulating = false
			if garage.sim_button: garage.sim_button.text = "Simulate Energy Flow"

# --- Scrubber engine ---------------------------------------------------
static func _clone_packets(packets: Array) -> Array[EnergyPacket]:
	var out: Array[EnergyPacket] = []
	for p in packets:
		out.append(p.copy())
	return out

func _reset_active_grid_state() -> void:
	if garage.grid_renderer.hex_grid:
		for tile in garage.grid_renderer.hex_grid.get_all_tiles():
			tile.reset_simulation_state()

# Silent replay used only to find where the run naturally ends (every
# packet exited the grid or dropped below the 0.5-magnitude floor). Reuses
# _advance_step so it can never disagree with what the scrubber itself
# reaches - leaves grid_renderer's visible state exactly where it lands
# (drained), which is fine since the caller (run_simulation) always follows
# this with a fresh seed into active_packets right after.
func _discover_total_steps() -> int:
	_reset_active_grid_state()
	garage.grid_renderer.active_packets = _clone_packets(_initial_packets_snapshot)
	garage.grid_renderer.simulation_step = 0
	var n = 0
	while n < DISCOVERY_STEP_CAP and not garage.grid_renderer.active_packets.is_empty():
		_advance_step()
		n += 1
	return n

# Deterministic re-run to an arbitrary step (drag target). Always replays
# from the cached step-0 snapshot rather than stepping incrementally from
# wherever the view currently sits - "scrub backward" and "scrub forward"
# are the identical operation, which is what keeps this correct without
# needing separate rewind logic.
func seek_to_step(target_step: int) -> void:
	target_step = clampi(target_step, 0, total_steps)
	_reset_active_grid_state()
	garage.grid_renderer.active_packets = _clone_packets(_initial_packets_snapshot)
	garage.grid_renderer.simulation_step = 0
	for i in range(target_step):
		if garage.grid_renderer.active_packets.is_empty():
			break
		_advance_step()
	# Instant seek, not a live tween - packets should render already
	# "arrived" at this step rather than mid-flight from a stale anim.
	for p in garage.grid_renderer.active_packets:
		p.set_meta("anim_progress", 1.0)
	update_stats()
	_sync_scrubber_ui(target_step)

func _update_scrubber_range() -> void:
	if garage.sim_scrubber:
		garage.sim_scrubber.max_value = total_steps
		garage.sim_scrubber.visible = total_steps > 0
	_sync_scrubber_ui(0)

# Called from the live auto-play loop so the slider tracks playback without
# the user having to touch it - guarded by _scrubber_syncing so this
# programmatic move doesn't loop back through _on_sim_scrubber_changed and
# trigger a redundant (if harmless) re-seek.
func _sync_scrubber_to_live_step() -> void:
	_sync_scrubber_ui(garage.grid_renderer.simulation_step)

func _sync_scrubber_ui(step_value: int) -> void:
	if not garage.sim_scrubber:
		return
	garage._scrubber_syncing = true
	garage.sim_scrubber.value = step_value
	garage._scrubber_syncing = false
	if garage.sim_step_label:
		garage.sim_step_label.text = "Step: %d / %d" % [step_value, total_steps]

# Compact display for the stats panel's numbers. Stays readable at any
# magnitude: plain integers below 1000, a K/M/B/T suffix ladder up through
# the trillions (covers every sane in-game build), and true scientific
# notation beyond that - Natalia's own suggestion, and the only thing that
# stays legible once a stacked Amplifier/Resonator build (or, previously, the
# EnergyPacket synergies/magnitude decoupling bug - see EnergyPacket.gd's
# _sync_synergies_to_magnitude) pushes a number into the 1e15+ range. Built
# from plain arithmetic + %f/%d rather than relying on "%e" so it doesn't
# depend on GDScript's sprintf coverage.
static func _format_magnitude(val: float) -> String:
	if val == 0:
		return "0"
	var sign_str = "-" if val < 0 else ""
	var abs_val = abs(val)
	if abs_val < 1000.0:
		return sign_str + str(int(round(abs_val)))
	if abs_val >= 1e15:
		var exponent = int(floor(log(abs_val) / log(10.0)))
		var mantissa = abs_val / pow(10.0, exponent)
		# Rounding the mantissa can carry it up to 10.0 (e.g. 9.996 -> "10.00")
		# which would print as "10.00e5" instead of "1.00e6" - bump the
		# exponent and rescale when that happens.
		mantissa = snapped(mantissa, 0.01)
		if mantissa >= 10.0:
			mantissa /= 10.0
			exponent += 1
		return "%s%se%d" % [sign_str, str(mantissa), exponent]
	var suffixes = [
		{"v": 1e12, "s": "T"},
		{"v": 1e9, "s": "B"},
		{"v": 1e6, "s": "M"},
		{"v": 1e3, "s": "K"},
	]
	for suf in suffixes:
		if abs_val >= suf.v:
			return "%s%s%s" % [sign_str, str(snapped(abs_val / suf.v, 0.01)), suf.s]
	return sign_str + str(int(round(abs_val)))

func update_stats():
	var total_nrg = 0.0
	for p in garage.grid_renderer.active_packets:
		total_nrg += p.magnitude

	var grid_size = garage.grid_renderer.hex_grid.get_all_tiles().size() if garage.grid_renderer.hex_grid else 0

	# Aggregate synergies from all Weapon Mounts/Accessory Returns
	var synergy_totals = {}
	var total_output = 0.0
	if garage.grid_renderer.hex_grid:
		for t in garage.grid_renderer.hex_grid.get_all_tiles():
			if "pending_packets" in t:
				for item in t.pending_packets:
					var p = item.packet
					total_output += p.magnitude
					for k in p.synergies:
						synergy_totals[k] = synergy_totals.get(k, 0.0) + p.synergies[k]

	var syn_str = ""
	var SynergyType = EnergyPacket.SynergyType
	var syn_names = SynergyType.keys()
	for k in synergy_totals.keys():
		var val = synergy_totals[k]
		if val > 0:
			var syn_name = "UNKNOWN"
			for key_name in syn_names:
				if SynergyType[key_name] == k:
					syn_name = key_name
					break
			syn_str += "%s: %s\n" % [syn_name, _format_magnitude(val)]

	if syn_str == "":
		syn_str = "None\n"

	var nrg_str = _format_magnitude(total_nrg)
	var out_str = _format_magnitude(total_output)

	garage.stats_label.text = "=== COMPONENT INFO ===\nTiles Used: %d\n\n=== OUTPUT ===\nTotal Damage: %s\n%s\n=== SIMULATION ===\nStep: %d\nActive Packets: %d\nMoving Energy: %s" % [
		grid_size,
		out_str,
		syn_str,
		garage.grid_renderer.simulation_step,
		garage.grid_renderer.active_packets.size(),
		nrg_str
	]
