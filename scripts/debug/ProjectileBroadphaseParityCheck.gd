extends Node

# Parity harness for the Rust projectile-broadphase port
# (rust_ext/src/projectile_broadphase.rs + scripts/core/ProjectileBroadphase.
# gd): builds a deterministic set of targets/projectiles exercising direct
# hits, mask filtering, fast/swept tunneling cases, and multi-target pierce
# overlap, runs BOTH the Rust ProjectileBroadphase.query_hits and the
# GDScript ProjectileBroadphase._query_hits_fallback on identical input, and
# asserts the returned pair sets match exactly (order-independent). This is
# the drift tripwire for that port - see
# C:\Users\Utility\.claude\plans\effervescent-exploring-pine.md.
#
# If the loaded rust_ext DLL doesn't expose ProjectileBroadphase yet (not
# built, or the debug DLL is locked while the editor is open), this reports
# SKIP loudly rather than silently passing.

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _pair_set(pairs: Array) -> Dictionary:
	var s: Dictionary = {}
	for p in pairs:
		s["%d:%d" % [int(p["projectile_id"]), int(p["target_id"])]] = true
	return s

func _sets_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a:
		if not b.has(k):
			return false
	return true

func _run_case(label: String, targets: Array, projectiles: Array, expected_pair_count: int, rasterizer):
	var rust_pairs = rasterizer.query_hits(targets, projectiles)
	var fallback_pairs = ProjectileBroadphase._query_hits_fallback(targets, projectiles)
	_check("%s: rust pair count == %d" % [label, expected_pair_count], rust_pairs.size() == expected_pair_count)
	_check("%s: fallback pair count == %d" % [label, expected_pair_count], fallback_pairs.size() == expected_pair_count)
	_check("%s: rust matches fallback exactly" % label, _sets_equal(_pair_set(rust_pairs), _pair_set(fallback_pairs)))
	_check("%s: packed path (static+dynamic split) matches fallback" % label, _sets_equal(_pair_set(_packed_pairs(targets, projectiles, rasterizer)), _pair_set(fallback_pairs)))

# Exercises query_hits_packed + set_static_targets: even-indexed targets go
# through the retained static set, odd-indexed through the per-call arrays.
# Ids are offset above 2^53 (real Godot instance ids can be that large) to
# prove they survive the packed int64 path exactly.
func _packed_pairs(targets: Array, projectiles: Array, rasterizer) -> Array:
	var big = 1 << 60
	var s_ids = PackedInt64Array(); var s_pos = PackedVector2Array(); var s_r = PackedFloat64Array(); var s_l = PackedInt64Array()
	var d_ids = PackedInt64Array(); var d_pos = PackedVector2Array(); var d_r = PackedFloat64Array(); var d_l = PackedInt64Array()
	for i in range(targets.size()):
		var t = targets[i]
		if i % 2 == 0:
			s_ids.append(big + int(t["id"])); s_pos.append(t["pos"]); s_r.append(t["radius"]); s_l.append(int(t["layer"]))
		else:
			d_ids.append(big + int(t["id"])); d_pos.append(t["pos"]); d_r.append(t["radius"]); d_l.append(int(t["layer"]))
	rasterizer.set_static_targets(s_ids, s_pos, s_r, s_l)
	var p_ids = PackedInt64Array(); var p_prev = PackedVector2Array(); var p_curr = PackedVector2Array(); var p_r = PackedFloat64Array(); var p_m = PackedInt64Array()
	for p in projectiles:
		p_ids.append(big + int(p["id"])); p_prev.append(p["prev"]); p_curr.append(p["curr"]); p_r.append(p["radius"]); p_m.append(int(p["mask"]))
	var flat: PackedInt64Array = rasterizer.query_hits_packed(d_ids, d_pos, d_r, d_l, p_ids, p_prev, p_curr, p_r, p_m)
	var out: Array = []
	for i in range(0, flat.size(), 2):
		out.append({"projectile_id": flat[i] - big, "target_id": flat[i + 1] - big})
	return out

func _ready():
	if not ClassDB.class_exists("ProjectileBroadphaseRs"):
		print("SKIP: rust_ext DLL doesn't expose ProjectileBroadphaseRs (not built, or debug DLL locked while editor is open).")
		get_tree().quit(0)
		return
	var rasterizer = ClassDB.instantiate("ProjectileBroadphaseRs")

	# Case 1: direct straight-line hit.
	_run_case(
		"direct hit",
		[{"id": 1, "pos": Vector2(100, 0), "radius": 10.0, "layer": 4}],
		[{"id": 100, "prev": Vector2(0, 0), "curr": Vector2(200, 0), "radius": 5.0, "mask": 4}],
		1, rasterizer
	)

	# Case 2: geometrically overlapping but mask doesn't match layer -> no hit.
	_run_case(
		"mask mismatch",
		[{"id": 1, "pos": Vector2(100, 0), "radius": 10.0, "layer": 4}],
		[{"id": 100, "prev": Vector2(0, 0), "curr": Vector2(200, 0), "radius": 5.0, "mask": 8}],
		0, rasterizer
	)

	# Case 3: fast/tunneling - prev and curr both far from the target's
	# point-in-time position, but the swept SEGMENT passes through it. A
	# point-only check (no sweep) would miss this entirely.
	_run_case(
		"swept tunneling hit",
		[{"id": 1, "pos": Vector2(500, 500), "radius": 15.0, "layer": 32}],
		[{"id": 100, "prev": Vector2(300, 300), "curr": Vector2(700, 700), "radius": 5.0, "mask": 32}],
		1, rasterizer
	)

	# Case 4: multi-target pierce - one projectile's segment overlaps THREE
	# targets in a row (Rust/fallback should both report all three; dedup
	# across ticks is Projectile._handled_targets' job, not this layer's).
	_run_case(
		"multi-target pierce sweep",
		[
			{"id": 1, "pos": Vector2(100, 0), "radius": 10.0, "layer": 4},
			{"id": 2, "pos": Vector2(200, 0), "radius": 10.0, "layer": 4},
			{"id": 3, "pos": Vector2(300, 0), "radius": 10.0, "layer": 4},
			{"id": 4, "pos": Vector2(9000, 9000), "radius": 10.0, "layer": 4}, # decoy, out of range
		],
		[{"id": 100, "prev": Vector2(0, 0), "curr": Vector2(400, 0), "radius": 5.0, "mask": 4}],
		3, rasterizer
	)

	# Case 5: layer 32 (obstacle) target hit by an enemy-fired projectile
	# (mask 8|1|32, per Projectile.gd's real non-player mask).
	_run_case(
		"obstacle layer hit (enemy-fired mask)",
		[{"id": 1, "pos": Vector2(50, 0), "radius": 12.0, "layer": 32}],
		[{"id": 100, "prev": Vector2(0, 0), "curr": Vector2(100, 0), "radius": 5.0, "mask": 8 | 1 | 32}],
		1, rasterizer
	)

	# Case 6: empty everything -> empty result, no crash.
	_run_case("empty input", [], [], 0, rasterizer)

	# Case 7: many targets, one projectile that hits none of them (a
	# realistic-scale negative case, since MVP scope is a flat O(n*m) loop -
	# this exercises that loop at a nontrivial size without any real hits).
	var many_targets: Array = []
	for i in range(50):
		many_targets.append({"id": 1000 + i, "pos": Vector2(i * 100, 5000), "radius": 8.0, "layer": 4})
	_run_case(
		"large target set, no overlap",
		many_targets,
		[{"id": 100, "prev": Vector2(0, 0), "curr": Vector2(100, 0), "radius": 5.0, "mask": 4}],
		0, rasterizer
	)

	print("")
	if failures == 0:
		print("PASS: Rust projectile broadphase is pair-identical to the GDScript fallback across all cases")
	get_tree().quit(0 if failures == 0 else 1)
