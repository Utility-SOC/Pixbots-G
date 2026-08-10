extends Node

# Verifies ProjectileBatchPool._step_simulate correctly builds/unpacks the
# compute_batch_flat request/response (see B1 of this session's batch-pool
# visual/movement parity plan) - the Rust math itself is already proven
# correct by ProjectileFlightFlatParityCheck.gd, this checks the GDScript
# plumbing around it: request field packing, response unpacking, and
# lightning-state carryover between ticks (segment_index/prev_offset/
# target_offset feed back into the NEXT tick's request - a stale-state bug
# here would only show up after 2+ ticks, not the first).
#
# Method: spawn one pool slot with real ratios (Kinetic + Fire + Vortex +
# Lightning mixed, non-trivial branches), step the pool for several ticks,
# and independently call compute_batch_flat directly each tick with a
# hand-built request mirroring what the pool SHOULD have built (same
# steering_resistance/straighten derivation, same field order) - tracking
# direction/lightning-state ourselves across ticks exactly like the pool
# does. If the pool's internal request-building or response-unpacking has
# a bug (wrong field index, dropped state), its trajectory will diverge
# from this independently-driven reference.

const ProjectileBatchPoolScript = preload("res://scripts/entities/ProjectileBatchPool.gd")
const TOL = 0.001

func _ready():
	var failures = 0
	var rasterizer = ClassDB.instantiate("ProjectileFlight")
	if not rasterizer:
		push_error("FAIL: ProjectileFlight Rust class not available - cannot run this parity check")
		get_tree().quit(1)
		return

	var world = Node2D.new()
	add_child(world)
	var pool = ProjectileBatchPoolScript.new(4)
	world.add_child(pool)

	var ratios = {
		EnergyPacket.SynergyType.KINETIC: 0.3,
		EnergyPacket.SynergyType.FIRE: 0.2,
		EnergyPacket.SynergyType.VORTEX: 0.2,
		EnergyPacket.SynergyType.LIGHTNING: 0.3,
	}
	var start_pos = Vector2(100, 50)
	var start_dir = Vector2.RIGHT
	var speed = 400.0
	var i = pool.spawn(start_pos, start_dir, speed, 10.0, 8.0, 10.0, Color.WHITE, 1.0, true, null, EnergyPacket.SynergyType.LIGHTNING, ratios)

	# Independently-tracked reference state, evolved tick-by-tick the same
	# way the pool's spawn()/_step_simulate should.
	var ref_pos = start_pos
	var ref_dir = start_dir
	var ref_time_alive = 0.0
	var ref_seg = -1.0
	var ref_prev_off = 0.0
	var ref_target_off = 0.0

	var r_kin = ratios[EnergyPacket.SynergyType.KINETIC]
	var r_ice = 0.0
	var r_vamp = 0.0
	var r_fire = ratios[EnergyPacket.SynergyType.FIRE]
	var r_psn = 0.0
	var r_vtx = ratios[EnergyPacket.SynergyType.VORTEX]
	var r_ltg = ratios[EnergyPacket.SynergyType.LIGHTNING]
	var r_prc = 0.0
	var steering_resistance = 1.0 + (3.0 * r_ice)
	var straighten = clamp(1.0 - r_kin, 0.0, 1.0)

	var delta = 1.0 / 60.0
	for tick in range(5):
		pool._step_simulate(delta)

		# Matches Projectile._physics_process_body's own ordering
		# ("time_alive += delta" runs BEFORE the flight-math request is
		# built) and ProjectileBatchPool._step_simulate's mirroring of it
		# (_elapsed[i] += delta happens before this tick's request uses it).
		ref_time_alive += delta

		var req := PackedFloat64Array()
		req.resize(20)
		req[0] = r_kin; req[1] = r_vamp; req[2] = r_fire; req[3] = r_psn; req[4] = r_vtx; req[5] = r_ltg; req[6] = r_prc
		req[7] = ref_dir.x; req[8] = ref_dir.y; req[9] = 0.0; req[10] = 0.0; req[11] = 0.0
		req[12] = speed; req[13] = ref_time_alive; req[14] = delta
		req[15] = steering_resistance; req[16] = straighten
		req[17] = ref_seg; req[18] = ref_prev_off; req[19] = ref_target_off
		var out: PackedFloat64Array = rasterizer.compute_batch_flat(PackedInt64Array([1]), req)
		ref_dir = Vector2(out[0], out[1])
		var velocity = Vector2(out[2], out[3])
		var visual_offset = Vector2(out[4], out[5])
		ref_seg = out[9]; ref_prev_off = out[10]; ref_target_off = out[11]
		ref_pos += velocity * delta

		var pool_pos = pool._position[i]
		var pool_dir = pool._direction[i]
		var pool_visual_offset = pool._visual_offset[i]
		var tick_ok = pool_pos.distance_to(ref_pos) < TOL and pool_dir.distance_to(ref_dir) < TOL and pool_visual_offset.distance_to(visual_offset) < TOL
		if tick_ok:
			print("ok: tick %d - pool position/direction/visual_offset match independently-driven reference" % tick)
		else:
			push_error("FAIL: tick %d diverged - pool_pos=%s ref_pos=%s pool_dir=%s ref_dir=%s pool_vis_off=%s ref_vis_off=%s" % [
				tick, pool_pos, ref_pos, pool_dir, ref_dir, pool_visual_offset, visual_offset])
			failures += 1

	if failures == 0:
		print("PASS: ProjectileBatchPool's request-building/response-unpacking/state-carryover around compute_batch_flat matches an independently-driven reference across multiple ticks")
	get_tree().quit(0 if failures == 0 else 1)
