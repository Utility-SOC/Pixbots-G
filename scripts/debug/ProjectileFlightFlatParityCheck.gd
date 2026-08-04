extends Node

# Verifies the 2026-08-03 flat-array rewrite of the projectile flight-math
# batch call (rust_ext/src/projectile_flight.rs's compute_batch_flat)
# produces IDENTICAL results to the original Dictionary-array compute_batch
# it replaced in the real hot path (ProjectileManager.gd). compute_batch
# itself stays in the tree as the reference implementation for exactly this
# check - see that file's module comment.
#
# Builds a set of hand-varied synthetic requests (spanning every synergy
# ratio the math branches on: kinetic, vampiric/homing, fire, poison,
# vortex, lightning, pierce, plus a couple of "everything zero" and
# "everything maxed" edge cases) in BOTH the old Dictionary shape and the
# new flat-array shape from the SAME underlying values, calls both Rust
# entry points, and asserts every output field matches within float
# tolerance.

func _ready():
	var failures = 0
	var rasterizer = ClassDB.instantiate("ProjectileFlight")
	if not rasterizer:
		push_error("FAIL: ProjectileFlight Rust class not available - cannot run this parity check")
		get_tree().quit(1)
		return

	# Each case: [r_kin, r_vamp, r_fire, r_psn, r_vtx, r_ltg, r_prc,
	#   direction, target_direction, has_homing_target,
	#   final_speed, time_alive, delta, steering_resistance, straighten,
	#   lightning_segment_index, lightning_prev_offset, lightning_target_offset,
	#   instance_id]
	var cases = [
		[0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, Vector2.RIGHT, Vector2.ZERO, false, 500.0, 0.0, 1.0/60.0, 1.0, 1.0, -1, 0.0, 0.0, 1001],
		[0.8, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, Vector2.RIGHT, Vector2(0.7, 0.7).normalized(), false, 600.0, 0.5, 1.0/60.0, 1.0, 0.2, -1, 0.0, 0.0, 1002],
		[0.0, 0.9, 0.0, 0.0, 0.0, 0.0, 0.0, Vector2.RIGHT, Vector2.UP, true, 500.0, 0.3, 1.0/60.0, 1.0, 1.0, -1, 0.0, 0.0, 1003],
		[0.4, 0.6, 0.0, 0.0, 0.0, 0.0, 0.3, Vector2.RIGHT, Vector2.DOWN, true, 500.0, 0.3, 1.0/60.0, 1.0, 0.6, -1, 0.0, 0.0, 1004],
		[0.0, 0.0, 0.9, 0.0, 0.0, 0.0, 0.0, Vector2.RIGHT, Vector2.ZERO, false, 700.0, 1.2, 1.0/60.0, 1.0, 1.0, -1, 0.0, 0.0, 1005],
		[0.0, 0.0, 0.9, 0.0, 0.0, 0.0, 0.8, Vector2.RIGHT, Vector2.ZERO, false, 700.0, 1.2, 1.0/60.0, 1.0, 1.0, -1, 0.0, 0.0, 1006],
		[0.0, 0.0, 0.0, 0.7, 0.0, 0.0, 0.0, Vector2.RIGHT, Vector2.ZERO, false, 500.0, 0.8, 1.0/60.0, 1.0, 1.0, -1, 0.0, 0.0, 1007],
		[0.0, 0.0, 0.0, 0.0, 0.8, 0.0, 0.0, Vector2.RIGHT, Vector2.ZERO, false, 500.0, 0.4, 1.0/60.0, 1.0, 1.0, -1, 0.0, 0.0, 1008],
		[0.0, 0.0, 0.0, 0.0, 0.0, 0.9, 0.0, Vector2.RIGHT, Vector2.ZERO, false, 500.0, 0.09, 1.0/60.0, 1.0, 1.0, 1, -0.3, 0.6, 1009],
		[0.0, 0.0, 0.0, 0.0, 0.0, 0.9, 0.0, Vector2.RIGHT, Vector2.ZERO, false, 500.0, 0.02, 1.0/60.0, 1.0, 1.0, 1, -0.3, 0.6, 1009],
		[1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, Vector2(0.6, 0.8), Vector2(-0.6, 0.8), true, 900.0, 2.5, 1.0/60.0, 4.0, 0.0, 5, 0.9, -0.9, 999999999],
		[0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, Vector2.RIGHT, Vector2.ZERO, false, 500.0, 0.0, 1.0/30.0, 2.5, 0.5, -1, 0.0, 0.0, -12345],
	]

	# Old-shape Dictionary batch
	var dict_requests: Array = []
	for c in cases:
		dict_requests.append({
			"instance_id": c[18],
			"ratios": {"r_kin": c[0], "r_vamp": c[1], "r_fire": c[2], "r_psn": c[3], "r_vtx": c[4], "r_ltg": c[5], "r_prc": c[6]},
			"direction": c[7], "target_direction": c[8], "has_homing_target": c[9],
			"final_speed": c[10], "time_alive": c[11], "delta": c[12],
			"steering_resistance": c[13], "straighten": c[14],
			"lightning_state": {"segment_index": c[15], "prev_offset": c[16], "target_offset": c[17]},
		})
	var dict_results = rasterizer.compute_batch(dict_requests)

	# New-shape flat arrays, same underlying values, same order
	var instance_ids := PackedInt64Array()
	var requests_flat := PackedFloat64Array()
	for c in cases:
		instance_ids.append(c[18])
		var row := PackedFloat64Array()
		row.resize(20)
		row[0] = c[0]; row[1] = c[1]; row[2] = c[2]; row[3] = c[3]; row[4] = c[4]; row[5] = c[5]; row[6] = c[6]
		row[7] = c[7].x; row[8] = c[7].y; row[9] = c[8].x; row[10] = c[8].y
		row[11] = 1.0 if c[9] else 0.0
		row[12] = c[10]; row[13] = c[11]; row[14] = c[12]; row[15] = c[13]; row[16] = c[14]
		row[17] = float(c[15]); row[18] = c[16]; row[19] = c[17]
		requests_flat.append_array(row)
	var flat_results: PackedFloat64Array = rasterizer.compute_batch_flat(instance_ids, requests_flat)

	const TOL = 0.0001
	for i in cases.size():
		var d = dict_results[i]
		var base = i * 12
		var checks = [
			["direction.x", d["direction"].x, flat_results[base]],
			["direction.y", d["direction"].y, flat_results[base + 1]],
			["velocity.x", d["velocity"].x, flat_results[base + 2]],
			["velocity.y", d["velocity"].y, flat_results[base + 3]],
			["visual_offset.x", d["visual_offset"].x, flat_results[base + 4]],
			["visual_offset.y", d["visual_offset"].y, flat_results[base + 5]],
			["current_speed", d["current_speed"], flat_results[base + 6]],
			["gravity_velocity.x", d["gravity_velocity"].x, flat_results[base + 7]],
			["gravity_velocity.y", d["gravity_velocity"].y, flat_results[base + 8]],
			["lightning_segment_index", float(d["lightning_segment_index"]), flat_results[base + 9]],
			["lightning_prev_offset", d["lightning_prev_offset"], flat_results[base + 10]],
			["lightning_target_offset", d["lightning_target_offset"], flat_results[base + 11]],
		]
		var case_ok = true
		for chk in checks:
			if abs(chk[1] - chk[2]) > TOL:
				push_error("FAIL case %d (%s): dict=%.6f flat=%.6f" % [i, chk[0], chk[1], chk[2]])
				case_ok = false
				failures += 1
		if case_ok:
			print("ok: case %d matches (dict == flat)" % i)

	if failures == 0:
		print("PASS: ProjectileFlightFlatParityCheck - compute_batch_flat matches compute_batch exactly across %d cases" % cases.size())
	get_tree().quit(0 if failures == 0 else 1)
