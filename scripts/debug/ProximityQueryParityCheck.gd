extends Node

# Regression harness for task #33 ("batch homing-target search + vortex
# pull queries into Rust") - ProximityQueryRs.batch_radius_query vs
# ProjectileTargetingBatcher._batch_radius_query_fallback. Hand-built cases,
# same structure as ProjectileBroadphaseParityCheck.gd/SolidGridLosCheck.gd:
# assert both implementations agree with each other AND with a
# hand-verified expected result.

const BatcherScript = preload("res://scripts/core/ProjectileTargetingBatcher.gd")

func _ready():
	var failures = 0
	var batcher = BatcherScript.new()
	batcher._ensure_rust()
	var have_rust = batcher._rasterizer != null
	if not have_rust:
		print("NOTE: ProximityQueryRs not built (DLL missing) - only the GDScript fallback is being tested.")

	# Candidates: 5 points spaced 100 units apart along the x-axis, ids 1-5.
	var candidates: Array = []
	for i in range(5):
		candidates.append({"id": i + 1, "pos": Vector2(i * 100.0, 0.0)})

	# Basic range query: query id 10 never matches candidate id 1 (distinct
	# ids), so the candidate AT the query's own position (distance 0, id 1)
	# is a legitimate hit, not a self-exclusion case - confirms distance-0
	# hits work. Self-exclusion (matching ids) is tested separately below.
	var got1 = _run(batcher, have_rust, 10, Vector2(0.0, 0.0), 250.0, candidates)
	failures += _assert_hits("radius 250 from origin (0,100,200 in range)", got1, [1, 2, 3])

	# Empty result: radius too small to catch anything.
	var got2 = _run(batcher, have_rust, 11, Vector2(1000.0, 1000.0), 50.0, candidates)
	failures += _assert_hits("far query, small radius - no hits", got2, [])

	# Self-exclusion: a query sharing an id with a candidate never matches itself.
	var self_candidates = candidates.duplicate(true)
	self_candidates.append({"id": 99, "pos": Vector2(0.0, 0.0)})
	var got3 = _run(batcher, have_rust, 99, Vector2(0.0, 0.0), 250.0, self_candidates)
	failures += _assert_hits("self-exclusion: query id 99 matches candidate id 99 at distance 0, must be excluded", got3, [1, 2, 3])

	# Ordering: results must be sorted ascending by distance. Query
	# position deliberately chosen (260, not the more obvious 250) so no
	# two candidates tie exactly - a tie's ORDER would depend on sort
	# stability/bucket-iteration order, which could legitimately differ
	# between Rust's HashMap and GDScript's Dictionary without being a
	# real bug, so the test avoids that ambiguity entirely.
	# distances from (260,0): id1=260, id2=160, id3=60, id4=40, id5=140 - all within radius 300.
	var got4 = _run(batcher, have_rust, 12, Vector2(260.0, 0.0), 300.0, candidates)
	failures += _assert_hits("multi-hit query sorted ascending by distance", got4, [4, 3, 5, 2, 1])

	# --- batch_find_best (Phase 2 of task #33: homing-target search only
	# ever needs the single closest/furthest match, not a full hits array) ---
	failures += _assert_best("closest of 3 in-range candidates", batcher, have_rust, 10, Vector2(0.0, 0.0), 250.0, false, candidates, true, 1, 0.0)
	failures += _assert_best("furthest of 3 in-range candidates", batcher, have_rust, 10, Vector2(0.0, 0.0), 250.0, true, candidates, true, 3, 200.0)
	failures += _assert_best("no candidates in range", batcher, have_rust, 11, Vector2(1000.0, 1000.0), 50.0, false, candidates, false, -1, -1.0)
	var self_candidates2 = candidates.duplicate(true)
	self_candidates2.append({"id": 99, "pos": Vector2(0.0, 0.0)})
	failures += _assert_best("self-exclusion (closest)", batcher, have_rust, 99, Vector2(0.0, 0.0), 250.0, false, self_candidates2, true, 1, 0.0)

	if failures == 0:
		print("PASS: ProximityQueryParityCheck - all cases correct%s" % (" (rust + fallback agree)" if have_rust else " (fallback only)"))
	get_tree().quit(0 if failures == 0 else 1)

func _assert_best(label: String, batcher, have_rust: bool, qid: int, qpos: Vector2, radius: float, prefer_furthest: bool, candidates: Array, expect_found: bool, expect_id: int, expect_dist: float) -> int:
	var failures = 0
	var queries = [{"id": qid, "pos": qpos, "radius": radius, "prefer_furthest": prefer_furthest}]
	var fallback = batcher._batch_find_best_fallback(queries, candidates)[0]
	failures += _check_best_result("fallback", label, fallback, expect_found, expect_id, expect_dist)

	if have_rust:
		var rust = batcher._rasterizer.batch_find_best(queries, candidates)[0]
		failures += _check_best_result("rust", label, rust, expect_found, expect_id, expect_dist)
		var rust_found = bool(rust.found)
		var fallback_found = bool(fallback.found)
		if rust_found != fallback_found or (rust_found and int(rust.best_id) != int(fallback.best_id)):
			push_error("FAIL [parity] %s: rust=%s fallback=%s disagree" % [label, rust, fallback])
			failures += 1

	if failures == 0:
		print("PASS: %s" % label)
	return failures

func _check_best_result(source: String, label: String, result: Dictionary, expect_found: bool, expect_id: int, expect_dist: float) -> int:
	if bool(result.found) != expect_found:
		push_error("FAIL [%s] %s: found=%s, want %s" % [source, label, result.found, expect_found])
		return 1
	if expect_found:
		if int(result.best_id) != expect_id:
			push_error("FAIL [%s] %s: best_id=%d, want %d" % [source, label, int(result.best_id), expect_id])
			return 1
		if absf(float(result.dist) - expect_dist) > 0.01:
			push_error("FAIL [%s] %s: dist=%.3f, want %.3f" % [source, label, float(result.dist), expect_dist])
			return 1
	return 0

func _run(batcher, have_rust: bool, qid: int, qpos: Vector2, radius: float, candidates: Array) -> Dictionary:
	var queries = [{"id": qid, "pos": qpos, "radius": radius}]
	var fallback_result = batcher._batch_radius_query_fallback(queries, candidates)[0]
	var rust_result = fallback_result
	if have_rust:
		rust_result = batcher._rasterizer.batch_radius_query(queries, candidates)[0]
	return {"fallback": fallback_result, "rust": rust_result, "have_rust": have_rust}

func _assert_hits(label: String, result: Dictionary, expected_ids_sorted: Array) -> int:
	var failures = 0
	var fallback_ids = []
	for h in result.fallback.hits:
		fallback_ids.append(int(h.id))
	if fallback_ids != expected_ids_sorted:
		push_error("FAIL [fallback] %s: got %s, want %s" % [label, fallback_ids, expected_ids_sorted])
		failures += 1

	if result.have_rust:
		var rust_ids = []
		for h in result.rust.hits:
			rust_ids.append(int(h.id))
		if rust_ids != expected_ids_sorted:
			push_error("FAIL [rust] %s: got %s, want %s" % [label, rust_ids, expected_ids_sorted])
			failures += 1
		if rust_ids != fallback_ids:
			push_error("FAIL [parity] %s: rust=%s fallback=%s disagree" % [label, rust_ids, fallback_ids])
			failures += 1

	if failures == 0:
		print("PASS: %s" % label)
	return failures
