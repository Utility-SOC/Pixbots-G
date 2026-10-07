class_name TerrainEditor
extends RefCounted

# Runtime terrain editing API over a generated MapGenerator: set biomes, place
# or clear obstacles, carve/fill rects, draw lines, build mazes, snapshot and
# restore regions. Used by scripted set pieces (Frank's maze tutorial, boss
# arenas, map events).
#
# Edits change the map DATA immediately (terrain grid, obstacles dict, nav
# solidity) and are recorded; commit() then syncs the physical side once for
# everything touched: collision bodies, per-cell obstacle nodes, repainted
# ground chunks, flow-field/LOS solidity buffers. Batch many edits between
# commits.
#
# Obstacle names: "Tree" and DestructibleObstacle.OBSTACLE_STATS keys
# (Boulder, Cactus, IceBoulder, LavaRock, StoneWall) spawn destructible nodes;
# any other name (e.g. "Wall") is a solid indestructible block.

const MapScript = preload("res://scripts/core/MapGenerator.gd")
const DestructibleObstacleScript = preload("res://scripts/core/DestructibleObstacle.gd")
const WALL = "Wall"
const OBSTACLE_LAYER = 32
const WATER_LAYER = 2
const MAX_EDIT_CELLS = 40000 # one commit can't touch more than this (guards runaway scripts)

var map
# cell -> {"biome": int, "obstacle": String} as it was before the first edit
var _before: Dictionary = {}
var _dirty: Dictionary = {} # cell -> true
var _cell_bodies: Dictionary = {} # cell -> obstacle StaticBody2D made by this editor
var _water_bodies: Dictionary = {}

func _init(target_map):
	map = target_map

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < map.width and c.y < map.height

func _touch(c: Vector2i) -> bool:
	if not in_bounds(c):
		return false
	if not _before.has(c):
		if _before.size() >= MAX_EDIT_CELLS:
			return false
		_before[c] = {"biome": int(map.terrain[c.y][c.x]), "obstacle": str(map.obstacles.get(c, ""))}
	_dirty[c] = true
	return true

func biome_at(c: Vector2i) -> int:
	return int(map.terrain[c.y][c.x]) if in_bounds(c) else -1

func obstacle_at(c: Vector2i) -> String:
	return str(map.obstacles.get(c, ""))

func set_biome(c: Vector2i, biome: int) -> bool:
	if not _touch(c):
		return false
	map.terrain[c.y][c.x] = biome
	_sync_solid(c)
	return true

func place_obstacle(c: Vector2i, name: String = WALL) -> bool:
	if name == "" or not _touch(c):
		return false
	map.obstacles[c] = name
	_sync_solid(c)
	return true

func clear_obstacle(c: Vector2i) -> bool:
	if not _touch(c):
		return false
	map.obstacles.erase(c)
	_sync_solid(c)
	return true

# Open ground: no obstacle, and water becomes `biome` (default grassland).
func clear_cell(c: Vector2i, biome: int = 0) -> bool:
	if not _touch(c):
		return false
	map.obstacles.erase(c)
	if int(map.terrain[c.y][c.x]) == MapScript.BiomeType.WATER:
		map.terrain[c.y][c.x] = biome
	_sync_solid(c)
	return true

func fill_rect(r: Rect2i, name: String = WALL) -> int:
	var n = 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if place_obstacle(Vector2i(x, y), name):
				n += 1
	return n

func carve_rect(r: Rect2i) -> int:
	var n = 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if clear_cell(Vector2i(x, y)):
				n += 1
	return n

# Hollow rectangle of `name` with `thickness`.
func outline_rect(r: Rect2i, name: String = WALL, thickness: int = 1) -> int:
	var n = 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var edge = x < r.position.x + thickness or x >= r.end.x - thickness or y < r.position.y + thickness or y >= r.end.y - thickness
			if edge and place_obstacle(Vector2i(x, y), name):
				n += 1
	return n

# Bresenham line; name "" clears instead of placing. thickness > 1 widens it.
func line(a: Vector2i, b: Vector2i, name: String = WALL, thickness: int = 1) -> int:
	var n = 0
	var dx = abs(b.x - a.x)
	var dy = -abs(b.y - a.y)
	var sx = 1 if a.x < b.x else -1
	var sy = 1 if a.y < b.y else -1
	var err = dx + dy
	var p = a
	var half = thickness / 2
	while true:
		for oy in range(-half, thickness - half):
			for ox in range(-half, thickness - half):
				var c = p + Vector2i(ox, oy)
				if (place_obstacle(c, name) if name != "" else clear_cell(c)):
					n += 1
		if p == b:
			break
		var e2 = 2 * err
		if e2 >= dy:
			err += dy
			p.x += sx
		if e2 <= dx:
			err += dx
			p.y += sy
	return n

# Perfect maze (recursive backtracker) inside `r`. Corridors are `corridor`
# cells wide, walls `wall_w` thick, on a lattice; entrance/exit openings are cut
# in the left/right edge middles. Returns {"entrance", "exit", "path"}: the
# unique solution as a list of cell centres, for guidance markers.
func build_maze(r: Rect2i, rng: RandomNumberGenerator, corridor: int = 3, wall_w: int = 1, wall_name: String = WALL) -> Dictionary:
	var pitch = corridor + wall_w
	var cols = int((r.size.x - wall_w) / pitch)
	var rows = int((r.size.y - wall_w) / pitch)
	if cols < 2 or rows < 2:
		return {}
	fill_rect(Rect2i(r.position, Vector2i(cols * pitch + wall_w, rows * pitch + wall_w)), wall_name)
	var origin = r.position
	var visited: Dictionary = {}
	var parent: Dictionary = {}
	var stack: Array = [Vector2i(0, 0)]
	visited[Vector2i(0, 0)] = true
	_carve_room(origin, Vector2i(0, 0), corridor, wall_w, pitch)
	while not stack.is_empty():
		var cur: Vector2i = stack[stack.size() - 1]
		var opts: Array = []
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx = cur + d
			if nx.x >= 0 and nx.y >= 0 and nx.x < cols and nx.y < rows and not visited.has(nx):
				opts.append(nx)
		if opts.is_empty():
			stack.pop_back()
			continue
		var nxt: Vector2i = opts[rng.randi() % opts.size()]
		visited[nxt] = true
		parent[nxt] = cur
		_carve_room(origin, nxt, corridor, wall_w, pitch)
		_carve_between(origin, cur, nxt, corridor, wall_w, pitch)
		stack.append(nxt)
	var start = Vector2i(0, rows / 2)
	var goal = Vector2i(cols - 1, rows / 2)
	# Solution: walk goal -> root, then reverse path from root -> start is a
	# common prefix; compute start -> goal through the tree.
	var path_cells = _tree_path(parent, start, goal)
	var entrance = origin + Vector2i(0, start.y * pitch + wall_w)
	var exit_c = origin + Vector2i(cols * pitch, goal.y * pitch + wall_w)
	carve_rect(Rect2i(entrance, Vector2i(wall_w, corridor)))
	carve_rect(Rect2i(exit_c, Vector2i(wall_w, corridor)))
	var path: Array = []
	for rc in path_cells:
		path.append(origin + rc * pitch + Vector2i(wall_w + corridor / 2, wall_w + corridor / 2))
	return {"entrance": entrance + Vector2i(0, corridor / 2), "exit": exit_c + Vector2i(wall_w - 1, corridor / 2), "path": path, "cols": cols, "rows": rows}

func _carve_room(origin: Vector2i, rc: Vector2i, corridor: int, wall_w: int, pitch: int) -> void:
	carve_rect(Rect2i(origin + rc * pitch + Vector2i(wall_w, wall_w), Vector2i(corridor, corridor)))

func _carve_between(origin: Vector2i, a: Vector2i, b: Vector2i, corridor: int, wall_w: int, pitch: int) -> void:
	var lo = Vector2i(min(a.x, b.x), min(a.y, b.y))
	if a.y == b.y:
		carve_rect(Rect2i(origin + lo * pitch + Vector2i(wall_w + corridor, wall_w), Vector2i(wall_w, corridor)))
	else:
		carve_rect(Rect2i(origin + lo * pitch + Vector2i(wall_w, wall_w + corridor), Vector2i(corridor, wall_w)))

func _tree_path(parent: Dictionary, a: Vector2i, b: Vector2i) -> Array:
	var up_a: Array = [a]
	var cur = a
	while parent.has(cur):
		cur = parent[cur]
		up_a.append(cur)
	var up_b: Array = [b]
	cur = b
	while parent.has(cur):
		cur = parent[cur]
		up_b.append(cur)
	var set_a: Dictionary = {}
	for i in range(up_a.size()):
		set_a[up_a[i]] = i
	var meet_b = 0
	for i in range(up_b.size()):
		if set_a.has(up_b[i]):
			meet_b = i
			break
	var meet = up_b[meet_b]
	var out: Array = up_a.slice(0, int(set_a[meet]) + 1)
	var down: Array = up_b.slice(0, meet_b)
	down.reverse()
	out.append_array(down)
	return out

# Is there a walkable route between two cells right now (uses the nav grid,
# which reflects uncommitted data edits too)?
func has_path(a: Vector2i, b: Vector2i) -> bool:
	if not in_bounds(a) or not in_bounds(b):
		return false
	return not map.astar_grid.get_id_path(a, b).is_empty()

# ---- snapshots ---------------------------------------------------------------

# Captures the current biome/obstacle of every cell in `r` for restore().
func snapshot(r: Rect2i) -> Dictionary:
	var cells: Dictionary = {}
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c = Vector2i(x, y)
			if in_bounds(c):
				cells[c] = {"biome": int(map.terrain[y][x]), "obstacle": str(map.obstacles.get(c, ""))}
	return cells

func restore(snap: Dictionary) -> int:
	var n = 0
	for c in snap:
		var st = snap[c]
		if not _touch(c):
			continue
		map.terrain[c.y][c.x] = int(st["biome"])
		if str(st["obstacle"]) == "":
			map.obstacles.erase(c)
		else:
			map.obstacles[c] = str(st["obstacle"])
		_sync_solid(c)
		n += 1
	return n

# Undo everything since the last commit (data only; nothing physical changed yet).
func revert_pending() -> void:
	var snap: Dictionary = {}
	for c in _dirty:
		snap[c] = _before[c]
	for c in snap:
		map.terrain[c.y][c.x] = int(snap[c]["biome"])
		if str(snap[c]["obstacle"]) == "":
			map.obstacles.erase(c)
		else:
			map.obstacles[c] = str(snap[c]["obstacle"])
		_sync_solid(c)
	_dirty.clear()
	_before.clear()

# ---- physical sync -------------------------------------------------------------

func _sync_solid(c: Vector2i) -> void:
	map.terrain_version += 1 # every runtime terrain write ends here: per-mech terrain caches must refresh
	var solid = int(map.terrain[c.y][c.x]) == MapScript.BiomeType.WATER or map.obstacles.has(c)
	map.astar_grid.set_point_solid(c, solid)

func pending_count() -> int:
	return _dirty.size()

func commit() -> int:
	if _dirty.is_empty():
		return 0
	var cells: Array = _dirty.keys()
	var nodes = _index_obstacle_nodes()
	var chunks: Dictionary = {}
	for c in cells:
		_remove_obstacle_physics(c, nodes)
		_remove_from_runs(OBSTACLE_LAYER, c)
		_remove_from_runs(WATER_LAYER, c)
		for reg in [_cell_bodies, _water_bodies]:
			if reg.has(c):
				if is_instance_valid(reg[c]):
					reg[c].queue_free()
				reg.erase(c)
	for c in cells:
		var name = str(map.obstacles.get(c, ""))
		if name != "":
			_add_obstacle_physics(c, name)
		if int(map.terrain[c.y][c.x]) == MapScript.BiomeType.WATER:
			_water_bodies[c] = _single_body(c, WATER_LAYER)
		chunks[Vector2i(c.x / map.CHUNK_TILES, c.y / map.CHUNK_TILES)] = true
	for ck in chunks:
		map._build_terrain_chunk(ck.x, ck.y, 20, Color(0.1, 0.4, 0.9))
	# Count-based caches elsewhere only notice size changes; force rebuilds.
	map._flow_field_grid_obstacle_count = -1
	map._flow_field_timer = 0.0
	if map.is_inside_tree():
		var batcher = map.get_tree().root.get_node_or_null("SolidGridBatcher")
		if batcher and "_last_obstacle_count" in batcher:
			batcher._last_obstacle_count = -1
	var n = cells.size()
	_dirty.clear()
	_before.clear()
	return n

func _index_obstacle_nodes() -> Dictionary:
	var idx: Dictionary = {}
	for ch in map.get_children():
		if ch is TreeObstacle or ch is DestructibleObstacle:
			idx[ch.cell] = ch
	return idx

func _remove_obstacle_physics(c: Vector2i, nodes: Dictionary) -> void:
	if nodes.has(c) and is_instance_valid(nodes[c]):
		if nodes[c] is TreeObstacle and map.has_method("unregister_tree_visual"):
			map.unregister_tree_visual(nodes[c].position)
		nodes[c].queue_free()
		nodes.erase(c)

func _add_obstacle_physics(c: Vector2i, name: String) -> void:
	var pos = Vector2(c.x * map.tile_size, c.y * map.tile_size)
	if name == "Tree":
		map._spawn_tree(pos)
	elif DestructibleObstacleScript.OBSTACLE_STATS.has(name):
		map._spawn_destructible_obstacle(pos, name)
	else:
		_cell_bodies[c] = _single_body(c, OBSTACLE_LAYER)

func _single_body(c: Vector2i, layer: int) -> StaticBody2D:
	var body = StaticBody2D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(map.tile_size, map.tile_size)
	shape.shape = rect
	body.position = Vector2(c.x * map.tile_size + map.tile_size / 2.0, c.y * map.tile_size + map.tile_size / 2.0)
	body.add_child(shape)
	map.add_child(body)
	return body

# Splits any merged collision run covering `c` into the pieces left/right of it.
func _remove_from_runs(layer: int, c: Vector2i) -> void:
	if not map._runs.has(layer) or not map._runs[layer].has(c.y):
		return
	var rows: Array = map._runs[layer][c.y]
	for i in range(rows.size()):
		var run = rows[i]
		if c.x >= run["x"] and c.x < run["x"] + run["n"]:
			rows.remove_at(i)
			if is_instance_valid(run["body"]):
				run["body"].queue_free()
			var left = c.x - run["x"]
			var right = run["x"] + run["n"] - c.x - 1
			if left > 0:
				map._create_merged_collision(run["x"], c.y, left, layer)
			if right > 0:
				map._create_merged_collision(c.x + 1, c.y, right, layer)
			return
