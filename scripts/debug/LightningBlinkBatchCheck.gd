extends Node

# Regression check for the Lightning blink-hop performance fix (live
# playtest: 4-6fps whenever firing a Lightning-heavy weapon with entities
# on screen, fine with none - every Lightning-ratio Projectile was
# independently linear-scanning the WHOLE enemy/player pool every
# BLINK_INTERVAL, O(shots x entities)). Projectile._update_blink now
# submits a request to ProjectileTargetingBatcher instead of scanning
# inline; ProjectileTargetingBatcher._resolve_blink batches all pending
# requests through the same grid-bucket _batch_find_best_fallback homing
# already proved (23.9% win), extended with a per-query "exclude" set.
#
# Covers the pure batched-query logic directly (precise, fast, no physics-
# frame waits) plus one real end-to-end integration case (mirrors
# ProjectileTargetingBatcherCheck.gd's real-Mech/real-Projectile style) to
# confirm the request/cache/consume wiring and the exact motion formula
# are both actually correct, not just the isolated function.

const ProjectileScript = preload("res://scripts/entities/Projectile.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# --- 1: correct nearest target, un-excluded -----------------------------
	var q1 = [{"id": 1, "pos": Vector2(0, 0), "radius": 500.0, "prefer_furthest": false, "exclude": {}}]
	var c1 = [{"id": 100, "pos": Vector2(50, 0)}, {"id": 200, "pos": Vector2(20, 0)}]
	var r1 = ProjectileTargetingBatcher._batch_find_best_fallback(q1, c1)
	_check("finds the true nearest candidate (id 200 at dist 20, not id 100 at dist 50)",
		r1[0].found and int(r1[0].best_id) == 200)

	# --- 2: exclusion set removes an already-hit target ---------------------
	var q2 = [{"id": 1, "pos": Vector2(0, 0), "radius": 500.0, "prefer_furthest": false, "exclude": {200: true}}]
	var r2 = ProjectileTargetingBatcher._batch_find_best_fallback(q2, c1)
	_check("excludes an already-hit target even though it's nearest by raw distance (falls back to id 100)",
		r2[0].found and int(r2[0].best_id) == 100)

	# --- 3: nothing beyond the query radius is ever selected -----------------
	var q3 = [{"id": 1, "pos": Vector2(0, 0), "radius": 500.0, "prefer_furthest": false, "exclude": {}}]
	var c3 = [{"id": 300, "pos": Vector2(1000, 0)}]
	var r3 = ProjectileTargetingBatcher._batch_find_best_fallback(q3, c3)
	_check("a candidate beyond the query radius is correctly not found",
		not r3[0].found)

	# --- 4: multiple concurrent queries resolve independently ---------------
	var q4 = [
		{"id": 1, "pos": Vector2(0, 0), "radius": 500.0, "prefer_furthest": false, "exclude": {}},
		{"id": 2, "pos": Vector2(1000, 0), "radius": 500.0, "prefer_furthest": false, "exclude": {}},
	]
	var c4 = [{"id": 100, "pos": Vector2(10, 0)}, {"id": 200, "pos": Vector2(1010, 0)}]
	var r4 = ProjectileTargetingBatcher._batch_find_best_fallback(q4, c4)
	var found_map = {}
	for r in r4:
		found_map[int(r.id)] = int(r.best_id) if r.found else -1
	_check("two concurrent queries each resolve to their OWN nearest, not cross-contaminated",
		found_map.get(1, -1) == 100 and found_map.get(2, -1) == 200)

	# --- 5: zero eligible candidates resolves to not-found -------------------
	var q5 = [{"id": 1, "pos": Vector2(0, 0), "radius": 500.0, "prefer_furthest": false, "exclude": {}}]
	var r5 = ProjectileTargetingBatcher._batch_find_best_fallback(q5, [])
	_check("an empty candidate pool correctly resolves to not-found",
		not r5[0].found)

	# --- 6: grid-boundary correctness (the classic bucket-grid bug) ---------
	# radius=500 -> cell_size = max(32, 500) = 500. Query at x=495 sits in
	# cell 0; a same-cell candidate at x=100 (dist 395) is deliberately
	# FARTHER than a candidate at x=505 (dist 10), which sits in the
	# ADJACENT cell (floor(505/500)=1). If the neighbor-cell scan were
	# broken (only checking the query's own cell), this would wrongly
	# return the same-cell-but-farther candidate instead.
	var q6 = [{"id": 1, "pos": Vector2(495, 0), "radius": 500.0, "prefer_furthest": false, "exclude": {}}]
	var c6 = [{"id": 1, "pos": Vector2(100, 0)}, {"id": 2, "pos": Vector2(505, 0)}]
	var r6 = ProjectileTargetingBatcher._batch_find_best_fallback(q6, c6)
	_check("the true nearest target is found even when it sits in an adjacent grid cell (got best_id=%s)" % [r6[0].get("best_id", "none")],
		r6[0].found and int(r6[0].best_id) == 2)

	# --- 7: end-to-end wiring + exact motion formula (real Projectile/Mech) -
	var world = Node2D.new()
	add_child(world)

	var target = MechScript.new()
	target.is_player = false
	target.global_position = Vector2(300.0, 0.0)
	world.add_child(target)

	var proj = ProjectileScript.new()
	proj.synergies = {EnergyPacket.SynergyType.LIGHTNING: 5.0} # sole synergy -> ratio 1.0 (full teleport, easiest exact case to check)
	proj.damage = 10.0
	proj.fired_by_player = true
	proj.collision_mask = 4
	proj.global_position = Vector2.ZERO
	world.add_child(proj)

	var target_pos_before = target.global_position
	var dist_before = proj.global_position.distance_to(target_pos_before)
	# Minimum window for the pipeline: one tick to submit the request, the
	# same tick's end for the batcher to resolve it (priority 998, after
	# projectiles), one more tick for the projectile to consume the cached
	# result and apply the hop. Kept short deliberately - this test isolates
	# the blink-hop wiring, not Projectile.gd's full flight stack (normal
	# forward-flight movement also runs every tick and is expected to add a
	# little independent drift on top; the point is confirming the ~300-unit
	# hop itself landed, not chasing an exact post-flight position).
	for i in range(3):
		await get_tree().physics_frame

	var dist_after = proj.global_position.distance_to(target_pos_before)
	_check("the projectile closed almost the entire original 300-unit gap to the target in one hop - full pipeline wired correctly (dist %.1f -> %.1f)" % [dist_before, dist_after],
		dist_after < 30.0)

	if failures == 0:
		print("PASS: Lightning blink-hop batched targeting is correct (nearest-target, exclusion, range limit, multi-query isolation, empty pool, grid-boundary correctness) and the real request/resolve/consume pipeline actually moves a projectile")
	get_tree().quit(0 if failures == 0 else 1)
