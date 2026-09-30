extends Node

const MapGeneratorScript = preload("res://scripts/core/MapGenerator.gd")
const TerrainEditorScript = preload("res://scripts/core/TerrainEditor.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	var map = MapGeneratorScript.new()
	map.map_type = "Open Field"
	map.map_seed = 12345
	add_child(map)
	var ed = TerrainEditorScript.new(map)
	var a = Vector2i(60, 60)
	var b = Vector2i(120, 60)
	_check("open field is walkable a->b", ed.has_path(a, b))

	# wall across the field blocks, a gap reopens it
	ed.fill_rect(Rect2i(90, 0, 2, 250), "Wall")
	_check("wall blocks the path (nav data)", not ed.has_path(a, b))
	ed.clear_cell(Vector2i(90, 60))
	ed.clear_cell(Vector2i(91, 60))
	_check("gap reopens the path", ed.has_path(a, b))
	var n = ed.commit()
	_check("commit reports touched cells (%d)" % n, n >= 400)
	_check("commit leaves nothing pending", ed.pending_count() == 0)
	_check("obstacles dict has wall, not gap", map.obstacles.has(Vector2i(90, 45)) and not map.obstacles.has(Vector2i(90, 60)))
	_check("solid flag in astar", map.astar_grid.is_point_solid(Vector2i(90, 45)) and not map.astar_grid.is_point_solid(Vector2i(90, 60)))
	_check("is_world_walkable agrees", not map.is_world_walkable(Vector2(90.5 * 32, 45.5 * 32)) and map.is_world_walkable(Vector2(90.5 * 32, 60.5 * 32)))
	await get_tree().process_frame
	var bodies = 0
	for ch in map.get_children():
		if ch is StaticBody2D and not ch.is_queued_for_deletion() and ch.collision_layer == 32:
			bodies += 1
	_check("wall has collision bodies (%d)" % bodies, bodies > 0)

	# carve a cell out of a baked merged run (Forest-ish): place via editor then carve the middle
	ed.fill_rect(Rect2i(30, 100, 10, 1), "Wall")
	ed.commit()
	ed.clear_obstacle(Vector2i(35, 100))
	ed.commit()
	await get_tree().process_frame
	var covers = 0
	for ch in map.get_children():
		if ch is StaticBody2D and not ch.is_queued_for_deletion() and ch.collision_layer == 32:
			var half = ch.get_child(0).shape.size.x / 64.0
			var mid = ch.position.x / 32.0
			if int(ch.position.y / 32) == 100 and mid - half < 36.0 and mid + half > 35.0:
				covers += 1
	_check("cleared cell has no collision left", covers == 0)
	_check("neighbours still solid", map.astar_grid.is_point_solid(Vector2i(34, 100)) and map.astar_grid.is_point_solid(Vector2i(36, 100)))

	# snapshot / restore
	var r = Rect2i(150, 150, 10, 10)
	var snap = ed.snapshot(r)
	ed.outline_rect(r, "Wall", 2)
	ed.commit()
	_check("outline placed", map.obstacles.has(Vector2i(150, 150)))
	ed.restore(snap)
	ed.commit()
	_check("restore removes the outline", not map.obstacles.has(Vector2i(150, 150)) and not map.astar_grid.is_point_solid(Vector2i(150, 150)))

	# revert pending
	ed.place_obstacle(Vector2i(10, 10), "Boulder")
	ed.revert_pending()
	_check("revert_pending undoes uncommitted edit", not map.obstacles.has(Vector2i(10, 10)) and not map.astar_grid.is_point_solid(Vector2i(10, 10)))

	# destructible + tree spawning and removal
	ed.place_obstacle(Vector2i(20, 20), "Boulder")
	ed.place_obstacle(Vector2i(22, 20), "Tree")
	ed.commit()
	await get_tree().process_frame
	var found = 0
	for ch in map.get_children():
		if (ch is DestructibleObstacle or ch is TreeObstacle) and ch.cell in [Vector2i(20, 20), Vector2i(22, 20)]:
			found += 1
	_check("boulder and tree nodes spawned", found == 2)
	ed.clear_obstacle(Vector2i(20, 20))
	ed.clear_obstacle(Vector2i(22, 20))
	ed.commit()
	await get_tree().process_frame
	found = 0
	for ch in map.get_children():
		if (ch is DestructibleObstacle or ch is TreeObstacle) and not ch.is_queued_for_deletion() and ch.cell in [Vector2i(20, 20), Vector2i(22, 20)]:
			found += 1
	_check("their nodes are removed on clear", found == 0)

	# line
	var ln = ed.line(Vector2i(200, 20), Vector2i(230, 35), "Wall", 1)
	_check("line places cells (%d)" % ln, ln >= 30)
	ed.revert_pending()

	# maze: solvable, solution path walkable, entrance -> exit connected
	var rng = RandomNumberGenerator.new()
	rng.seed = 99
	var region = Rect2i(200, 100, 41, 25)
	var maze = ed.build_maze(region, rng, 3, 1)
	_check("maze built", not maze.is_empty() and maze["path"].size() >= 2)
	_check("entrance connects to exit", ed.has_path(maze["entrance"], maze["exit"]))
	var path_ok = true
	for c in maze["path"]:
		if map.obstacles.has(c):
			path_ok = false
	_check("solution path cells are open", path_ok)
	var walls = 0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			if map.obstacles.has(Vector2i(x, y)):
				walls += 1
	_check("maze has real walls (%d)" % walls, walls > 100)
	# consecutive solution cells are adjacent rooms (distance == pitch)
	var step_ok = true
	for i in range(maze["path"].size() - 1):
		var d = maze["path"][i + 1] - maze["path"][i]
		if abs(d.x) + abs(d.y) != 4:
			step_ok = false
	_check("solution steps are lattice-adjacent", step_ok)
	ed.commit()

	# determinism: same seed -> same obstacle layout
	var map2 = MapGeneratorScript.new()
	map2.map_type = "Forest"
	map2.map_seed = 777
	add_child(map2)
	var map3 = MapGeneratorScript.new()
	map3.map_type = "Forest"
	map3.map_seed = 777
	add_child(map3)
	_check("seeded maps are identical", map2.obstacles.size() == map3.obstacles.size() and map2.obstacles.size() > 0 and str(map2.obstacles.keys().slice(0, 50)) == str(map3.obstacles.keys().slice(0, 50)))
	var map4 = MapGeneratorScript.new()
	map4.map_type = "Forest"
	map4.map_seed = 778
	add_child(map4)
	_check("different seed differs", map4.obstacles.size() != map2.obstacles.size() or str(map4.obstacles.keys().slice(0, 50)) != str(map2.obstacles.keys().slice(0, 50)))

	print("terrain editor check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
