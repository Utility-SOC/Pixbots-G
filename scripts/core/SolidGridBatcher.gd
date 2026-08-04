extends Node

# Phase 1 of the AI-tactics Rust-cutover plan (see
# C:\Users\Utility\.claude\plans\effervescent-drifting-kazoo.md) - owns a
# flattened obstacle-solidity buffer (obstacles.has(cell) -> solid) and a
# batched grid-marched line-of-sight primitive, replacing the direct
# per-mech PhysicsRayQueryParameters2D calls in SightAndSearch.gd (sight
# check, search-leg avoidance) and BossBrain.gd (_pick_retreat_dir).
#
# DELIBERATE BEHAVIOR CHANGE (2026-08-03 planning decision, not a pure parity
# port): every one of those real raycasts passed collision_mask=1 (Env/
# map-boundary layer only - confirmed by reading every
# PhysicsRayQueryParameters2D.create call site in the codebase), so
# trees/boulders/ruins (layer 32, "Obstacles") never actually blocked
# sight/search-avoidance/retreat-picking before this. The user explicitly
# chose to fix that alongside the port rather than faithfully replicate the
# boundary-only quirk - mechs now genuinely can't see/path through solid
# terrain.
#
# Full-map buffer, NOT a moving window like MapGenerator's flow field -
# sight/retreat checks happen anywhere combat is, not just near the player.
# Obstacle destruction is rare (a handful of times per match at most), so
# rebuilding the whole ~100KB (400x250 map) buffer on change is dirt cheap;
# no periodic cadence needed at all, just a size() comparison each tick to
# detect a destroyed obstacle (Dictionary.erase always shrinks it - same
# "don't add a second invalidation path" piggyback the plan calls for,
# without needing to touch TreeObstacle.gd/DestructibleObstacle.gd).

var _checked: bool = false
var _rasterizer = null
var _map: MapGenerator = null
var _last_obstacle_count: int = -1

func _ensure_rust():
	if not _checked:
		_checked = true
		if ClassDB.class_exists("SolidGridRs"):
			_rasterizer = ClassDB.instantiate("SolidGridRs")

func _find_map() -> MapGenerator:
	if _map and is_instance_valid(_map):
		return _map
	var maps = get_tree().get_nodes_in_group("map_generator")
	if maps.is_empty():
		return null
	_map = maps[0]
	return _map

func _physics_process(_delta: float):
	if not _rasterizer:
		return # GDScript fallback path (below) reads map.obstacles directly every call instead of maintaining its own buffer - nothing to keep in sync here
	var map = _find_map()
	if not map:
		return
	if map.obstacles.size() != _last_obstacle_count:
		_last_obstacle_count = map.obstacles.size()
		_rebuild_grid(map)

func _rebuild_grid(map: MapGenerator):
	var solidity = PackedByteArray()
	solidity.resize(map.width * map.height)
	for pos in map.obstacles.keys():
		if pos.x >= 0 and pos.x < map.width and pos.y >= 0 and pos.y < map.height:
			solidity[pos.y * map.width + pos.x] = 1
	_rasterizer.set_grid(solidity, map.width, map.height, float(map.tile_size))

# Forces a grid rebuild before the first-ever query lands, same as
# _physics_process would do next tick - shared by every batch_* query below
# so none of them have to duplicate the freshness check.
func _sync_grid_if_rust() -> MapGenerator:
	var map = _find_map()
	if _rasterizer and map and _last_obstacle_count != map.obstacles.size():
		_last_obstacle_count = map.obstacles.size()
		_rebuild_grid(map)
	return map

# `queries`: Array of {from: Vector2, to: Vector2} (world-space). Returns
# Array[bool], same order - true = clear line of sight.
func batch_line_of_sight(queries: Array) -> Array:
	_ensure_rust()
	var map = _sync_grid_if_rust()
	if _rasterizer:
		return _rasterizer.batch_line_of_sight(queries)

	var out: Array = []
	for q in queries:
		if not map:
			out.append(true)
		else:
			out.append(_line_of_sight_fallback(map, q.from, q.to))
	return out

# Phase 4 (BossBrain._pick_retreat_dir) candidate - unlike
# batch_line_of_sight's boolean, returns how far (world units) each
# from->to segment gets before hitting a solid cell, capped at the
# segment's own length if never blocked - matches the real raycast's
# `clearance = probe_dist if clear else distance_to_hit` semantics closely
# enough for a soft repositioning heuristic (same disclosed grid-vs-physics
# approximation tier as batch_line_of_sight; see SolidGridRs.march's comment
# for the exact tradeoff).
#
# `queries`: Array of {from: Vector2, to: Vector2}. Returns Array[float].
func batch_probe_clearance(queries: Array) -> Array:
	_ensure_rust()
	var map = _sync_grid_if_rust()
	if _rasterizer:
		var results = _rasterizer.batch_probe_clearance(queries)
		return Array(results) # PackedFloat64Array -> plain Array, same convention callers already expect from batch_line_of_sight

	var out: Array = []
	for q in queries:
		if not map:
			out.append(q.from.distance_to(q.to))
		else:
			out.append(_probe_clearance_fallback(map, q.from, q.to))
	return out

# Pure-GDScript reference implementation of SolidGridRs.march's Amanatides &
# Woo DDA grid march - the fallback contract every Rust-ported system in
# this codebase keeps (see SeparationBatcher._batch_compute_separation_fallback).
# Returns the 0..1 t-parameter along from->to at which the first solid cell
# was entered, or null if the ray reaches the destination cell clear.
# Endpoints themselves are never tested (only cells strictly between from
# and to), same as the Rust side, so a mech standing on/adjacent to
# obstacle-cell geometry - or a target inside one - doesn't spuriously
# block its own sight/probe.
func _march_fallback(map: MapGenerator, from: Vector2, to: Vector2):
	var ts = float(map.tile_size)
	var x0 = from.x / ts
	var y0 = from.y / ts
	var x1 = to.x / ts
	var y1 = to.y / ts
	var cx = floori(x0)
	var cy = floori(y0)
	var end_cx = floori(x1)
	var end_cy = floori(y1)
	var dx = x1 - x0
	var dy = y1 - y0
	var step_x = 1 if dx > 0.0 else (-1 if dx < 0.0 else 0)
	var step_y = 1 if dy > 0.0 else (-1 if dy < 0.0 else 0)
	var t_delta_x = (1.0 / absf(dx)) if dx != 0.0 else INF
	var t_delta_y = (1.0 / absf(dy)) if dy != 0.0 else INF

	var t_max_x = INF
	if step_x > 0:
		t_max_x = ((cx + 1.0) - x0) * t_delta_x
	elif step_x < 0:
		t_max_x = (x0 - cx) * t_delta_x
	var t_max_y = INF
	if step_y > 0:
		t_max_y = ((cy + 1.0) - y0) * t_delta_y
	elif step_y < 0:
		t_max_y = (y0 - cy) * t_delta_y

	var max_steps = absi(end_cx - cx) + absi(end_cy - cy) + 2
	for i in range(max_steps):
		if cx == end_cx and cy == end_cy:
			break
		var t_here: float
		if t_max_x < t_max_y:
			cx += step_x
			t_here = t_max_x
			t_max_x += t_delta_x
		else:
			cy += step_y
			t_here = t_max_y
			t_max_y += t_delta_y
		if cx == end_cx and cy == end_cy:
			break
		if map.obstacles.has(Vector2i(cx, cy)):
			return clampf(t_here, 0.0, 1.0)
	return null

func _line_of_sight_fallback(map: MapGenerator, from: Vector2, to: Vector2) -> bool:
	return _march_fallback(map, from, to) == null

func _probe_clearance_fallback(map: MapGenerator, from: Vector2, to: Vector2) -> float:
	var full_len = from.distance_to(to)
	var t = _march_fallback(map, from, to)
	if t == null:
		return full_len
	return t * full_len
