extends Node

# Parity harness for the mech-merge/multi-cell Rust tile kinds NOT covered
# by RustGridSimParityCheck's torture grids, because they need a REAL
# component parented under a REAL mech (grid.get_parent() -> component ->
# mech) rather than a bare unparented grid:
#   - Jumpjet (kind 14): merges into mech.jumpjet_energy, sets
#     mech.ignore_terrain / mech.jumpjet_rarity
#   - Actuator (kind 15): merges into mech.actuator_energy AND sets the
#     tile's own current_speed_bonus (last-packet-wins, not cumulative)
#   - Lance Mount (kind 21): multi-cell footprint capture into
#     _face_magnitudes/_fed_packet, checked indirectly via check_face_gate()

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")
const SplitterTileScript = preload("res://scripts/tiles/SplitterTile.gd")
const JumpjetTileScript = preload("res://scripts/tiles/JumpjetTile.gd")
const ActuatorTileScript = preload("res://scripts/tiles/ActuatorTile.gd")
const LanceMountTileScript = preload("res://scripts/tiles/LanceMountTile.gd")
const ThrusterTileScript = preload("res://scripts/tiles/ManeuveringThrusterTile.gd")
const CatalystTileScript = preload("res://scripts/tiles/CatalystTile.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")
const RustGridSimScript = preload("res://scripts/core/RustGridSim.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _close(a: float, b: float) -> bool:
	return abs(a - b) <= 0.0001 * max(1.0, abs(a))

# --- Jumpjet + Actuator: Core fires E and SE into a Jumpjet and an
# Actuator respectively, both real components equipped onto a real mech.
func _build_jump_actuator_mech():
	var mech = MechScript.new()
	mech.is_player = false
	add_child(mech)

	var comp = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.RARE)
	var hexes: Array[HexCoord] = [HexCoord.new(0, 0), HexCoord.new(1, 0), HexCoord.new(0, 1), HexCoord.new(-1, 0)]
	comp.valid_hexes = hexes
	comp._rebuild_valid_hex_set()

	var core = CoreTileScript.new()
	core.active_faces.clear()
	core.active_faces.append(0)
	core.active_faces.append(1)
	core.active_faces.append(3)
	core.set_face_output(0, EnergyPacket.SynergyType.FIRE)
	core.set_face_output(1, EnergyPacket.SynergyType.KINETIC)
	core.set_face_output(3, EnergyPacket.SynergyType.LIGHTNING)
	comp.hex_grid.add_tile(HexCoord.new(0, 0), core)

	var jet = JumpjetTileScript.new()
	jet.rarity = HexTile.Rarity.RARE
	comp.hex_grid.add_tile(HexCoord.new(1, 0), jet)

	var act = ActuatorTileScript.new()
	act.rarity = HexTile.Rarity.RARE
	comp.hex_grid.add_tile(HexCoord.new(0, 1), act)

	var thruster = ThrusterTileScript.new()
	thruster.rarity = HexTile.Rarity.RARE
	comp.hex_grid.add_tile(HexCoord.new(-1, 0), thruster)

	mech.equip_component(comp)
	return {"mech": mech, "comp": comp, "jet": jet, "act": act, "thruster": thruster}

func _gen_packets(comp) -> Array:
	var core = comp.hex_grid.get_tile(HexCoord.new(0, 0))
	var pkts = core.generate_energy(comp.hex_grid)
	for p in pkts:
		p.position = HexCoord.new(0, 0)
	return pkts

func _check_jump_actuator():
	var gd_rig = _build_jump_actuator_mech()
	gd_rig.mech._simulate_grid(gd_rig.comp.hex_grid, _gen_packets(gd_rig.comp), true) # forced GDScript

	var rust_rig = _build_jump_actuator_mech()
	var handled = RustGridSimScript.try_simulate(rust_rig.comp.hex_grid, _gen_packets(rust_rig.comp), true)
	_check("Jumpjet/Actuator grid is fully inside the routed subset", handled)
	if not handled:
		return

	# Note: JumpjetTile.gd's own `if "ignore_terrain" in mech: mech.
	# ignore_terrain = true` is dead code - Mech.gd has no such field
	# anymore (terrain-crossing moved to the OBSTACLE_LAYER collision-mask
	# toggle in _jets_firing/collision_mask). The "in" guard makes it a
	# silent no-op in the GDScript path too, so the Rust bridge faithfully
	# mirrors that no-op rather than inventing a field that doesn't exist.
	_check("Jumpjet: mech.jumpjet_rarity matches (%d vs %d)" % [gd_rig.mech.jumpjet_rarity, rust_rig.mech.jumpjet_rarity],
		gd_rig.mech.jumpjet_rarity == rust_rig.mech.jumpjet_rarity)
	_check("Jumpjet: mech.jumpjet_energy.magnitude matches (%f vs %f)" % [gd_rig.mech.jumpjet_energy.magnitude, rust_rig.mech.jumpjet_energy.magnitude],
		gd_rig.mech.jumpjet_energy != null and rust_rig.mech.jumpjet_energy != null
		and _close(gd_rig.mech.jumpjet_energy.magnitude, rust_rig.mech.jumpjet_energy.magnitude))

	_check("Actuator: mech.actuator_energy.magnitude matches (%f vs %f)" % [gd_rig.mech.actuator_energy.magnitude, rust_rig.mech.actuator_energy.magnitude],
		gd_rig.mech.actuator_energy != null and rust_rig.mech.actuator_energy != null
		and _close(gd_rig.mech.actuator_energy.magnitude, rust_rig.mech.actuator_energy.magnitude))
	_check("Actuator: tile.current_speed_bonus matches (%f vs %f)" % [gd_rig.act.current_speed_bonus, rust_rig.act.current_speed_bonus],
		_close(gd_rig.act.current_speed_bonus, rust_rig.act.current_speed_bonus) and gd_rig.act.current_speed_bonus > 0.0)

	_check("Maneuvering Thruster: mech.thruster_accel_bonus matches (%d vs %d)" % [gd_rig.mech.thruster_accel_bonus, rust_rig.mech.thruster_accel_bonus],
		gd_rig.mech.thruster_accel_bonus == rust_rig.mech.thruster_accel_bonus and gd_rig.mech.thruster_accel_bonus == HexTile.Rarity.RARE)

	gd_rig.mech.queue_free()
	rust_rig.mech.queue_free()

# --- Catalyst gate_every_n: the counter is STATE that must persist across
# repeated Simulate presses (not reset each call) - a single-pass grid
# can't exercise this, so it's tested here across 3 separate try_simulate
# calls on the SAME tile, matching how a player would press Simulate
# repeatedly on an unchanged build.
func _check_catalyst_gate_counter():
	var comp = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.RARE)
	var hexes: Array[HexCoord] = [HexCoord.new(0, 0), HexCoord.new(1, 0), HexCoord.new(2, 0)]
	comp.valid_hexes = hexes
	comp._rebuild_valid_hex_set()
	var core = CoreTileScript.new()
	core.active_faces.clear()
	core.active_faces.append(0)
	core.set_face_output(0, EnergyPacket.SynergyType.FIRE)
	comp.hex_grid.add_tile(HexCoord.new(0, 0), core)
	var cat = CatalystTileScript.new()
	cat.target_synergy = EnergyPacket.SynergyType.ICE
	cat.gate_every_n = 3 # only every 3rd qualifying packet actually converts
	comp.hex_grid.add_tile(HexCoord.new(1, 0), cat)
	var mount = load("res://scripts/tiles/WeaponMountTile.gd").new()
	comp.hex_grid.add_tile(HexCoord.new(2, 0), mount)

	var results: Array = []
	for i in range(3):
		mount.clear_pending()
		RustGridSimScript.try_simulate(comp.hex_grid, _gen_packets(comp), true)
		var converted = false
		for item in mount.pending_packets:
			if item.packet.synergies.has(EnergyPacket.SynergyType.ICE):
				converted = true
		results.append(converted)
	_check("gate_every_n=3 across 3 calls: only the 3rd call actually converts (got %s)" % [results],
		results == [false, false, true])

# --- Lance Mount: 3-cell footprint, fed from 3 different directions across
# 3 different cells, so _face_magnitudes accumulates several distinct keys.
func _build_lance_mech():
	var mech = MechScript.new()
	mech.is_player = false
	add_child(mech)

	var comp = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.RARE)
	var hexes: Array[HexCoord] = [
		HexCoord.new(0, 0), HexCoord.new(1, 0), HexCoord.new(2, 0), HexCoord.new(3, 0),
		HexCoord.new(1, -1), HexCoord.new(2, -1), HexCoord.new(1, 1), HexCoord.new(2, 1),
	]
	comp.valid_hexes = hexes
	comp._rebuild_valid_hex_set()

	var core = CoreTileScript.new()
	core.active_faces.clear()
	core.active_faces.append(0)
	comp.hex_grid.add_tile(HexCoord.new(0, 0), core)

	# footprint_offsets are relative to the anchor: cell_idx 0 = anchor
	# (1,0), cell_idx 1 = anchor+(1,0) = (2,0), cell_idx 2 = anchor+(2,0) =
	# (3,0) - a straight 3-hex line, matching how a real Lance gets placed.
	var lance = LanceMountTileScript.new()
	lance.footprint_offsets = [Vector2i(1, 0), Vector2i(2, 0)]
	comp.hex_grid.add_tile(HexCoord.new(1, 0), lance)

	mech.equip_component(comp)
	return {"mech": mech, "comp": comp, "lance": lance}

# Feeds all three footprint cells from three DIFFERENT directions (the Core
# hits the anchor from the West; two synthetic packets are injected
# starting adjacent to the other two cells) so _face_magnitudes accumulates
# multiple distinct cell_idx:direction keys - not just a single hit.
func _lance_packets(comp) -> Array:
	var pkts: Array = []
	var core = comp.hex_grid.get_tile(HexCoord.new(0, 0))
	var core_pkts = core.generate_energy(comp.hex_grid)
	for p in core_pkts:
		p.position = HexCoord.new(0, 0)
	pkts.append_array(core_pkts)
	# cell_idx 1 (2,0): a packet starting at (2,1) traveling NW lands on
	# (2,0), entering from the SE face.
	var p2 = EnergyPacket.new(40.0, HexCoord.new(2, 1))
	p2.direction = 4
	pkts.append(p2)
	# cell_idx 2 (3,0): a packet starting at (4,-1) traveling SW lands on
	# (3,0), entering from the NE face.
	var p3 = EnergyPacket.new(60.0, HexCoord.new(4, -1))
	p3.direction = 2
	pkts.append(p3)
	return pkts

func _check_lance():
	var gd_rig = _build_lance_mech()
	gd_rig.mech._simulate_grid(gd_rig.comp.hex_grid, _lance_packets(gd_rig.comp), true)
	gd_rig.lance.check_face_gate()

	var rust_rig = _build_lance_mech()
	var handled = RustGridSimScript.try_simulate(rust_rig.comp.hex_grid, _lance_packets(rust_rig.comp), true)
	_check("Lance grid is fully inside the routed subset", handled)
	if not handled:
		return
	rust_rig.lance.check_face_gate()

	var gd_keys = gd_rig.lance._face_magnitudes.keys(); gd_keys.sort()
	var rust_keys = rust_rig.lance._face_magnitudes.keys(); rust_keys.sort()
	_check("Lance _face_magnitudes has the same keys (gd=%s rust=%s)" % [gd_keys, rust_keys], gd_keys == rust_keys)
	_check("Lance _face_magnitudes has real accumulated data (not vacuous)", gd_keys.size() >= 2)
	var vals_match = true
	for k in gd_keys:
		if not _close(gd_rig.lance._face_magnitudes[k], rust_rig.lance._face_magnitudes.get(k, -999.0)):
			vals_match = false
			print("    MISMATCH _face_magnitudes[%s]: gd=%f rust=%f" % [k, gd_rig.lance._face_magnitudes[k], rust_rig.lance._face_magnitudes.get(k, -999.0)])
	_check("Lance _face_magnitudes values match", vals_match)
	_check("Lance _fed_packet magnitude matches (%f vs %f)" % [gd_rig.lance._fed_packet.magnitude if gd_rig.lance._fed_packet else -1.0, rust_rig.lance._fed_packet.magnitude if rust_rig.lance._fed_packet else -1.0],
		gd_rig.lance._fed_packet != null and rust_rig.lance._fed_packet != null
		and _close(gd_rig.lance._fed_packet.magnitude, rust_rig.lance._fed_packet.magnitude))
	_check("Lance ready_to_fire gate matches (gd=%s rust=%s)" % [gd_rig.lance.ready_to_fire, rust_rig.lance.ready_to_fire],
		gd_rig.lance.ready_to_fire == rust_rig.lance.ready_to_fire)

	gd_rig.mech.queue_free()
	rust_rig.mech.queue_free()

func _ready():
	if not RustGridSimScript.is_available():
		print("SKIP: rust_ext DLL is the pre-port stub (debug DLL locked while the Godot editor is open).")
		get_tree().quit(0)
		return

	_check_jump_actuator()
	_check_lance()
	_check_catalyst_gate_counter()

	if failures == 0:
		print("PASS: Jumpjet/Actuator/Thruster mech-merges, Lance Mount multi-cell capture, and Catalyst gate-counter state all match across engines")
	get_tree().quit(0 if failures == 0 else 1)
