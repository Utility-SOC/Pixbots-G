extends Node

# Phase Shifter: activates only when Mythic and fed; drains all flow 5% per obstacle piece per tick (additive pieces,
# frame-rate independent), recovers when clear; counts distinct obstacle pieces from real physics shapes; drops the
# obstacle bit from the mech's collision mask; weapons and shields read the flow.

const MechScript = preload("res://scripts/entities/Mech.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTile = preload("res://scripts/tiles/CoreTile.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _shifter_mech(rarity: int, fed: bool):
	var mech = MechScript.new()
	mech.is_player = true
	add_child(mech)
	var comp = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.MYTHIC)
	var core = CoreTile.new()
	core.body_slot = HexTile.BodySlot.TORSO
	comp.hex_grid.add_tile(HexCoord.new(0, 0), core)
	var t = PhaseShifterTile.new()
	t.body_slot = HexTile.BodySlot.TORSO
	t.rarity = rarity
	comp.hex_grid.add_tile(HexCoord.new(1 if fed else 3, 0), t)
	mech.equip_component(comp)
	mech.is_grid_dirty = true
	mech._recalculate_grid()
	return mech

func _ready():
	_check("one tick in one piece costs 2%", is_equal_approx(PhaseDrain.drained(1.0, 1, 1.0 / 60.0), 0.98))
	_check("three pieces in one tick cost 6%", is_equal_approx(PhaseDrain.drained(1.0, 3, 1.0 / 60.0), 0.94))
	_check("frame-rate independent: two half-ticks equal one tick", is_equal_approx(PhaseDrain.drained(PhaseDrain.drained(1.0, 2, 1.0 / 120.0), 2, 1.0 / 120.0), PhaseDrain.drained(1.0, 2, 1.0 / 60.0)))
	_check("no pieces, no drain", PhaseDrain.drained(0.7, 0, 1.0) == 0.7)
	_check("a second inside three pieces cuts the flow to a few percent", PhaseDrain.drained(1.0, 3, 1.0) < 0.03)
	_check("it never goes negative", PhaseDrain.drained(1.0, 20, 5.0) >= 0.0)
	_check("flow recovers when clear", is_equal_approx(PhaseDrain.recovered(0.2, 0.5), 0.7) and PhaseDrain.recovered(0.9, 5.0) == 1.0)

	var on = _shifter_mech(HexTile.Rarity.MYTHIC, true)
	_check("a fed Mythic shifter is active", on.phase_shifter_active)
	var unfed = _shifter_mech(HexTile.Rarity.MYTHIC, false)
	_check("an unfed shifter does nothing", not unfed.phase_shifter_active)
	var rare = _shifter_mech(HexTile.Rarity.RARE, true)
	_check("a non-Mythic shifter does nothing", not rare.phase_shifter_active)

	# the obstacle bit leaves the mask while phasing
	on._update_obstacle_phasing()
	_check("obstacle layer dropped from the mask", (on.collision_mask & 32) == 0)
	rare._update_obstacle_phasing()
	_check("obstacle layer kept for a normal mech", (rare.collision_mask & 32) != 0)

	# real physics shapes: one body with two shapes + a second body = three pieces
	var rock = StaticBody2D.new()
	rock.collision_layer = 32
	for off in [Vector2(-6, 0), Vector2(6, 0)]:
		var cs = CollisionShape2D.new()
		var sh = CircleShape2D.new()
		sh.radius = 14.0
		cs.shape = sh
		cs.position = off
		rock.add_child(cs)
	add_child(rock)
	var rock2 = StaticBody2D.new()
	rock2.collision_layer = 32
	var cs2 = CollisionShape2D.new()
	var sh2 = CircleShape2D.new()
	sh2.radius = 14.0
	cs2.shape = sh2
	rock2.add_child(cs2)
	rock2.position = Vector2(0, 8)
	add_child(rock2)
	var wall = StaticBody2D.new()
	wall.collision_layer = 1 # map border layer: must not count
	var cs3 = CollisionShape2D.new()
	var sh3 = CircleShape2D.new()
	sh3.radius = 14.0
	cs3.shape = sh3
	wall.add_child(cs3)
	add_child(wall)
	var probe = Node2D.new()
	add_child(probe)
	probe.global_position = Vector2.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	var n = PhaseDrain.pieces_touching(probe)
	_check("three obstacle pieces counted, the wall layer ignored (%d)" % n, n == 3)
	probe.global_position = Vector2(500, 500)
	_check("clear ground touches nothing", PhaseDrain.pieces_touching(probe) == 0)

	on.set_physics_process(false)
	on.global_position = Vector2.ZERO
	await get_tree().physics_frame
	on.phase_flow = 1.0
	PhaseDrain.tick(on, 1.0 / 60.0)
	_check("a tick inside three pieces drains 6%% (%.3f)" % on.phase_flow, absf(on.phase_flow - 0.94) < 0.001)
	on.global_position = Vector2(500, 500)
	PhaseDrain.tick(on, 0.25)
	_check("and it recovers once clear (%.2f)" % on.phase_flow, on.phase_flow > 0.94)

	# Actuator speed, thruster-style consumers and the drone link read the flow
	var fast = MechScript.new()
	fast.is_player = true
	add_child(fast)
	fast.base_move_speed = 250.0
	fast.actuator_speed_bonus = 100.0
	fast.phase_flow = 0.5
	fast.update_status_effects(0.0)
	var full = MechScript.new()
	full.is_player = true
	add_child(full)
	full.base_move_speed = 250.0
	full.actuator_speed_bonus = 100.0
	full.update_status_effects(0.0)
	_check("a drained mech loses its Actuator speed bonus, not its base speed (%.1f vs %.1f)" % [fast.current_move_speed, full.current_move_speed], fast.current_move_speed < full.current_move_speed and fast.current_move_speed > full.current_move_speed * 0.6)
	var bay = DroneBayTile.new()
	bay.stored_energy = 100.0
	_check("a drone bay link is cut by the owner's flow", is_equal_approx(bay.get_bay_energy(0.4), 40.0) and bay.stored_energy == 0.0)
	var drone = Drone.new()
	_check("a drone keeps its own full flow regardless of any owner", drone.phase_flow == 1.0 and not drone.phase_shifter_active)
	drone.free()

	# the link feeds the drone's core reactor, cut by the owner's flow
	var core2 = CoreTile.new()
	var base_pkts = core2.generate_energy(null)
	var base_total = 0.0
	for pk in base_pkts:
		base_total += pk.magnitude
	core2.link_energy = 60.0
	var linked_total = 0.0
	for pk in core2.generate_energy(null):
		linked_total += pk.magnitude
	_check("link energy adds to the core's output (%.1f -> %.1f)" % [base_total, linked_total], is_equal_approx(linked_total - base_total, 60.0))

	var owner_m = MechScript.new()
	owner_m.is_player = true
	add_child(owner_m)
	var bay2 = DroneBayTile.new()
	bay2.rarity = HexTile.Rarity.COMMON
	bay2.link_energy = 40.0
	var d2 = Drone.new()
	d2.setup(owner_m, bay2.get_or_build_loadout(), bay2.rarity, bay2.visual_class, bay2)
	add_child(d2)
	var d2_cores = []
	for comp in d2.components.values():
		for tl in comp.hex_grid.get_all_tiles():
			if "link_energy" in tl and tl.has_method("generate_energy"):
				d2_cores.append(tl)
	d2._refresh_link()
	_check("a drone's core receives the bay link (%s)" % str(d2_cores.size()), d2_cores.size() > 0 and is_equal_approx(d2_cores[0].link_energy, 40.0))
	owner_m.phase_flow = 0.25
	d2._refresh_link()
	_check("the owner's drain cuts the link, not the core", is_equal_approx(d2_cores[0].link_energy, 10.0))
	owner_m.phase_flow = 1.0
	bay2.link_energy = 1.0e9
	d2._refresh_link()
	_check("the link is capped by bay rarity (%.0f)" % d2_cores[0].link_energy, is_equal_approx(d2_cores[0].link_energy, DroneBayTile.link_cap_for(d2.drone_rarity)) and DroneBayTile.link_cap_for(4) > DroneBayTile.link_cap_for(0))

	print("PhaseDrainCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
