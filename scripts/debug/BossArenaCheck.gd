extends Node

const MapScript = preload("res://scripts/core/MapGenerator.gd")
const ArenaScript = preload("res://scripts/core/BossArena.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	var map = MapScript.new()
	add_child(map)
	await get_tree().process_frame
	map.tile_size = 32
	map.width = 60
	map.height = 60
	map.obstacles = {}
	map.terrain = []
	for y in range(60):
		var row = []
		for x in range(60):
			row.append(map.BiomeType.WATER if x < 6 else map.BiomeType.GRASSLAND)
		map.terrain.append(row)
	var before_obstacles = map.obstacles.size()
	var centre = Vector2(30.5 * 32, 30.5 * 32)
	var player = Vector2(30.5 * 32 + 8 * 32, 30.5 * 32) # standing right on the ring
	var arena = ArenaScript.build(map, centre, player)
	_check("an arena is built", not arena.is_empty())
	var cells: Array = arena["cells"]
	_check("pillars are whole 2x2 blocks (%d cells)" % cells.size(), cells.size() > 0 and cells.size() % 4 == 0 and cells.size() <= ArenaScript.PILLARS * 4)
	_check("pillars are hard cover", map.obstacles[cells[0]] == "StoneWall")
	var clear = true
	for c in cells:
		if Vector2(c).distance_to(Vector2(player.x / 32.0, player.y / 32.0)) < ArenaScript.PLAYER_CLEAR_TILES - 1.5:
			clear = false
	_check("nothing is raised on top of the player", clear)
	_check("the ring is open between pillars (fewer than half the ring is walled)", cells.size() < 8 * 4 + 1)
	# the centre stays open and reachable
	_check("boss spawn point stays clear", not map.obstacles.has(Vector2i(30, 30)))
	ArenaScript.dismantle(arena)
	_check("dismantling restores the map exactly (%d obstacles)" % map.obstacles.size(), map.obstacles.size() == before_obstacles)
	# near water: no pillar in water
	var edge_arena = ArenaScript.build(map, Vector2(10.5 * 32, 30.5 * 32), Vector2(50 * 32, 50 * 32))
	var wet = false
	if not edge_arena.is_empty():
		for c in edge_arena["cells"]:
			if map.terrain[c.y][c.x] == map.BiomeType.WATER:
				wet = true
		ArenaScript.dismantle(edge_arena)
	_check("no pillar is placed in water", not wet)
	var mega = ArenaScript.build(map, centre, Vector2(0, 0), true)
	_check("a mega boss gets a larger, denser ring", not mega.is_empty() and mega["cells"].size() > cells.size())
	ArenaScript.dismantle(mega)
	print("boss arena check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
