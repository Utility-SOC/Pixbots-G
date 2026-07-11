extends Node

# Regression harness for the boxed-in fix (MapGenerator._carve_pocket_corridors
# + TreeObstacle nav-clearing):
#   1. On generated maps, NO walkable pocket of meaningful size may remain
#      sealed behind carvable obstacles - every such pocket must have been
#      corridor-carved into the main continent. (Water/ruin-locked pockets
#      are legitimate and stay.)
#   2. A destroyed tree must clear its obstacles-dict entry and astar
#      solidity (it used to leave an invisible AI wall), and FIRE must do
#      double damage to it.

const MapGeneratorScript = preload("res://scripts/core/MapGenerator.gd")

func _ready():
	var failures = 0
	for attempt in range(3): # three fresh random maps
		var map = MapGeneratorScript.new()
		map.map_type = "Normal"
		add_child(map) # _ready generates + builds nav
		failures += _assert_no_sealed_pockets(map, attempt)
		map.queue_free()
		await get_tree().process_frame

	# --- tree demolition clears nav ---
	var map2 = MapGeneratorScript.new()
	map2.map_type = "Normal"
	add_child(map2)
	var cell = Vector2i(5, 5)
	map2.obstacles[cell] = "Tree"
	map2.astar_grid.set_point_solid(cell, true)
	map2._spawn_tree(Vector2(cell.x * map2.tile_size, cell.y * map2.tile_size))
	var tree = map2.get_children().back()
	if not (tree is TreeObstacle):
		push_error("FAIL: _spawn_tree didn't produce a TreeObstacle")
		failures += 1
	else:
		var hp_before = tree.hp
		tree.apply_damage(hp_before / 2.0 + 1.0, "FIRE") # 2x weakness must kill in one half-HP hit
		await get_tree().process_frame
		if map2.obstacles.has(cell) or map2.astar_grid.is_point_solid(cell):
			push_error("FAIL: destroyed tree left its nav footprint (invisible wall)")
			failures += 1
		else:
			print("tree demolition: FIRE 2x kill cleared obstacles dict + astar solidity")
	map2.queue_free()

	if failures == 0:
		print("PASS: no sealed pockets on 3 generated maps; tree demolition clears nav")
	get_tree().quit(0 if failures == 0 else 1)

# Mirrors the carve pass's region analysis: finds walkable regions, then for
# each non-main pocket >= MIN_POCKET_SIZE checks whether it could reach the
# main region through carvable obstacle cells. If it can, the carve should
# already have connected it - so finding one means the guarantee failed.
func _assert_no_sealed_pockets(map, attempt: int) -> int:
	var visited = {}
	var regions: Array = []
	for y in range(map.height):
		for x in range(map.width):
			var pos = Vector2i(x, y)
			if visited.has(pos) or map.terrain[y][x] == map.BiomeType.WATER or map.obstacles.has(pos):
				continue
			var region = {pos: true}
			visited[pos] = true
			var queue = [pos]
			var head = 0
			while head < queue.size():
				var curr = queue[head]
				head += 1
				for n in [Vector2i(curr.x + 1, curr.y), Vector2i(curr.x - 1, curr.y), Vector2i(curr.x, curr.y + 1), Vector2i(curr.x, curr.y - 1)]:
					if n.x < 0 or n.x >= map.width or n.y < 0 or n.y >= map.height:
						continue
					if visited.has(n) or map.terrain[n.y][n.x] == map.BiomeType.WATER or map.obstacles.has(n):
						continue
					visited[n] = true
					region[n] = true
					queue.append(n)
			regions.append(region)

	regions.sort_custom(func(a, b): return a.size() > b.size())
	if regions.is_empty():
		push_error("FAIL: map %d has no walkable area at all" % attempt)
		return 1
	var main_region = regions[0]
	var sealed = 0
	for i in range(1, regions.size()):
		var region = regions[i]
		if region.size() < map.MIN_POCKET_SIZE:
			continue
		if _can_reach_through_obstacles(map, region, main_region):
			sealed += 1
	if sealed > 0:
		push_error("FAIL: map %d still has %d carvable sealed pocket(s)" % [attempt, sealed])
		return 1
	print("map %d: %d walkable regions, no carvable sealed pockets (main = %d cells)" % [attempt, regions.size(), main_region.size()])
	return 0

func _can_reach_through_obstacles(map, region: Dictionary, main_region: Dictionary) -> bool:
	var start: Vector2i = region.keys()[0]
	var seen = {start: true}
	var queue = [start]
	var head = 0
	while head < queue.size():
		var curr = queue[head]
		head += 1
		for n in [Vector2i(curr.x + 1, curr.y), Vector2i(curr.x - 1, curr.y), Vector2i(curr.x, curr.y + 1), Vector2i(curr.x, curr.y - 1)]:
			if n.x < 0 or n.x >= map.width or n.y < 0 or n.y >= map.height or seen.has(n):
				continue
			if map.terrain[n.y][n.x] == map.BiomeType.WATER:
				continue
			if map.obstacles.get(n, "") == "RuinPart":
				continue
			if main_region.has(n):
				return true
			seen[n] = true
			queue.append(n)
	return false
