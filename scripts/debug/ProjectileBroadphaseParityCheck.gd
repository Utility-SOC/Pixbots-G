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
