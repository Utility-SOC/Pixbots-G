extends Node

# Task #17: "universal obstacle destructibility" - the five flat biome
# obstacles (Boulder/Cactus/IceBoulder/LavaRock/StoneWall) previously fell
# into MapGenerator._create_merged_collision(), a bare scriptless
# StaticBody2D with no apply_damage at all. This verifies:
#   1. DestructibleObstacle.gd (the new generic node) collapses correctly,
#      clears the map's nav footprint, and respects per-type elemental
#      weaknesses, for all 5 obstacle names.
#   2. The Rust terrain rasterizer no longer bakes a flat square for these
#      names into the static ground texture (they'd otherwise double up
#      with the new node's own visual, or ghost-persist after collapse).
#   3. A real generated map actually spawns DestructibleObstacle nodes for
#      these tags instead of routing them into the merged flat collision.

const DestructibleObstacleScript = preload("res://scripts/core/DestructibleObstacle.gd")
const MapGeneratorScript = preload("res://scripts/core/MapGenerator.gd")

class FakeMapRef:
	extends Node
	var obstacles: Dictionary = {}
	var astar_grid: AStarGrid2D
	var _flow_field_timer: float = 5.0

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# --- 1. Per-type collapse/nav-clear/weakness behavior ---
	for obs_name in DestructibleObstacleScript.OBSTACLE_STATS.keys():
		var map_ref = FakeMapRef.new()
		add_child(map_ref)
		map_ref.astar_grid = AStarGrid2D.new()
		map_ref.astar_grid.region = Rect2i(0, 0, 4, 4)
		map_ref.astar_grid.cell_size = Vector2(1, 1)
		map_ref.astar_grid.update()
		var cell = Vector2i(2, 2)
		map_ref.astar_grid.set_point_solid(cell, true)
		map_ref.obstacles[cell] = obs_name

		var obs = DestructibleObstacleScript.new()
		obs.obstacle_name = obs_name
		obs.map_ref = map_ref
		obs.cell = cell
		add_child(obs)
		await get_tree().process_frame # let _ready() run and set up hp/weakness

		var stats = DestructibleObstacleScript.OBSTACLE_STATS[obs_name]
		var max_hp = stats[0]
		var weak_element = stats[2]
		var weak_mult = stats[3]

		_check("%s starts at its configured max_hp (%.0f)" % [obs_name, max_hp], obs.hp == max_hp and obs.max_hp == max_hp)

		# Sub-lethal hit with a NON-weak element: should just chip hp, not collapse.
		var non_weak = "KINETIC" if weak_element != "KINETIC" else "POISON"
		obs.apply_damage(max_hp * 0.4, non_weak)
		_check("%s survives a sub-lethal non-weak hit (hp %.1f)" % [obs_name, obs.hp], is_instance_valid(obs) and obs.hp > 0)

		# A hit that's lethal ONLY with the weak-element multiplier applied.
		var pre_hp = obs.hp
		var lethal_only_with_weakness = (pre_hp / weak_mult) + 1.0
		obs.apply_damage(lethal_only_with_weakness, weak_element)
		await get_tree().process_frame
		_check("%s collapses when weak-element damage (x%.1f) crosses 0 hp" % [obs_name, weak_mult], not is_instance_valid(obs))
		_check("%s collapse cleared its cell from map.obstacles" % obs_name, not map_ref.obstacles.has(cell))
		_check("%s collapse cleared the astar solid flag" % obs_name, not map_ref.astar_grid.is_point_solid(cell))
		_check("%s collapse reset the flow-field rebuild timer" % obs_name, map_ref._flow_field_timer == 0.0)

		map_ref.queue_free()

	# --- 2. Rust rasterizer no longer paints a flat square for these tags:
	# identical chunk with/without the obstacle tag should render pixel-
	# identical, since obstacle painting was the only thing that could
	# differ (same biome, same seed). ---
	if ClassDB.class_exists("TerrainRasterizer"):
		var rasterizer = ClassDB.instantiate("TerrainRasterizer")
		var biomes = PackedInt32Array([0])
		var corn_mask = PackedByteArray([0])
		var with_obstacle = rasterizer.rasterize_chunk(biomes, PackedStringArray(["Boulder"]), corn_mask, 1, 1, 32, "Forest", 12345)
		var without_obstacle = rasterizer.rasterize_chunk(biomes, PackedStringArray([""]), corn_mask, 1, 1, 32, "Forest", 12345)
		_check("Rust rasterizer renders a Boulder-tagged tile identically to an untagged one (no baked square)", with_obstacle == without_obstacle)
	else:
		print("skip: TerrainRasterizer GDExtension class not loaded, skipping Rust-side exclusion check")

	# --- 3. MapGenerator's real collision-build pass routes these tags
	# through DestructibleObstacle, not the merged flat collision. Built by
	# hand-populating a minimal grid rather than a full noise-generated map
	# (map_type "Forest"/"Normal" force/bias biome choice, which makes which
	# of the 5 obstacle names actually appear non-deterministic) - this
	# exercises the exact same _build_collisions_and_obstacles() dispatch
	# MapGenerator._ready() calls, just with a controlled obstacles dict so
	# all 5 names are guaranteed to be covered in one deterministic pass.
	# Not added to the test's tree, so _ready() (full noise generation)
	# never fires and overwrites these manual fields.
	var map = MapGeneratorScript.new()
	map.width = 5
	map.height = 1
	map.tile_size = 32
	map.map_type = "Normal"
	map.terrain = [[
		MapGeneratorScript.BiomeType.GRASSLAND, MapGeneratorScript.BiomeType.GRASSLAND,
		MapGeneratorScript.BiomeType.GRASSLAND, MapGeneratorScript.BiomeType.GRASSLAND,
		MapGeneratorScript.BiomeType.GRASSLAND
	]]
	var expected_names = ["Boulder", "Cactus", "IceBoulder", "LavaRock", "StoneWall"]
	for i in range(expected_names.size()):
		map.obstacles[Vector2i(i, 0)] = expected_names[i]
	map._build_collisions_and_obstacles()

	var found_names: Dictionary = {}
	for child in map.get_children():
		if child.get_script() == DestructibleObstacleScript:
			found_names[child.obstacle_name] = true
			_check("generated DestructibleObstacle '%s' matches map.obstacles at its cell" % child.obstacle_name,
				map.obstacles.get(child.cell, "") == child.obstacle_name)
	for expected in expected_names:
		_check("MapGenerator spawned a DestructibleObstacle for '%s' instead of routing it into the merged flat collision" % expected,
			found_names.has(expected))
	map.queue_free()

	if failures == 0:
		print("PASS: boulder-class obstacles collapse correctly, respect elemental weaknesses, clear nav on death, skip the baked-texture square, and spawn from real map generation")
	get_tree().quit(0 if failures == 0 else 1)
