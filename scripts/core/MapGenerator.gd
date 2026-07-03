class_name MapGenerator
extends Node2D

var width: int = 400
var height: int = 250
var tile_size: int = 32

var noise: FastNoiseLite
var moisture_noise: FastNoiseLite

var terrain: Array = []
var obstacles: Dictionary = {}

var main_continent_tiles: Dictionary = {}
var astar_grid: AStarGrid2D = AStarGrid2D.new()
var map_type: String = "Normal" # Can be "Arena"

enum BiomeType { GRASSLAND, WATER, DESERT, FOREST, TUNDRA, VOLCANO, DUNGEON }

func _ready():
	add_to_group("map_generator")
	
	noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.frequency = 0.05
	
	moisture_noise = FastNoiseLite.new()
	moisture_noise.seed = randi()
	moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	moisture_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	moisture_noise.fractal_octaves = 4
	moisture_noise.frequency = 0.04
	
	_generate_map()
	_draw_map_to_texture()
	_build_navigation()
	
	if get_tree().root.has_node("ProceduralMusic"):
		ProceduralMusic.set_biome(map_type)

func _generate_map():
	var map_valid = false
	var required_size = width * height * 0.3 # 30% of map
	
	while not map_valid:
		terrain.clear()
		obstacles.clear()
		
		# Generate a new seed on each retry
		noise.seed = randi()
		moisture_noise.seed = randi()
		
		var arena_center = Vector2(width / 2.0, height / 2.0)
		var rx = 100.0 # 200 tiles wide
		var ry = 60.0  # 120 tiles tall
		
		for y in range(height):
			var row = []
			for x in range(width):
				var biome = BiomeType.GRASSLAND
				
				if map_type == "Arena":
					var dx = x - arena_center.x
					var dy = y - arena_center.y
					var val = (dx*dx)/(rx*rx) + (dy*dy)/(ry*ry)
					
					if val > 1.0:
						biome = BiomeType.DUNGEON
					elif val > 0.9: # Inner edge of the wall, to give it some visual border if needed
						pass # Keep it grass for now, we'll handle wall generation later
				elif map_type == "Open Field":
					biome = BiomeType.GRASSLAND
				elif map_type == "Desert":
					biome = BiomeType.DESERT
				elif map_type == "Forest":
					biome = BiomeType.FOREST
				elif map_type == "Tundra":
					biome = BiomeType.TUNDRA
				elif map_type == "Volcano":
					biome = BiomeType.VOLCANO
				elif map_type == "Dungeon":
					biome = BiomeType.DUNGEON
				elif map_type == "Water":
					biome = BiomeType.WATER
				else:
					var elev = noise.get_noise_2d(x, y)
					var moist = moisture_noise.get_noise_2d(x, y)
					biome = _get_biome(elev, moist)
					
				row.append(biome)
				
				if map_type not in ["Arena", "Open Field"] and _should_spawn_obstacle(biome, randf()):
					if not _is_near_existing_mech(x, y):
						obstacles[Vector2i(x, y)] = _get_obstacle_name(biome)
			terrain.append(row)
			
		main_continent_tiles = _analyze_connectivity()
		if map_type != "Normal" or main_continent_tiles.size() >= required_size:
			map_valid = true

func _analyze_connectivity() -> Dictionary:
	var visited = {}
	var largest_continent = {}
	var max_size = 0
	
	for y in range(height):
		for x in range(width):
			var pos = Vector2i(x, y)
			if visited.has(pos) or terrain[y][x] == BiomeType.WATER or obstacles.has(pos):
				continue
				
			var current_continent = {}
			var queue = [pos]
			current_continent[pos] = true
			visited[pos] = true
			
			while queue.size() > 0:
				var curr = queue.pop_front()
				
				var neighbors = [
					Vector2i(curr.x + 1, curr.y),
					Vector2i(curr.x - 1, curr.y),
					Vector2i(curr.x, curr.y + 1),
					Vector2i(curr.x, curr.y - 1)
				]
				
				for n in neighbors:
					if n.x >= 0 and n.x < width and n.y >= 0 and n.y < height:
						if not visited.has(n) and terrain[n.y][n.x] != BiomeType.WATER and not obstacles.has(n):
							visited[n] = true
							current_continent[n] = true
							queue.push_back(n)
							
			if current_continent.size() > max_size:
				max_size = current_continent.size()
				largest_continent = current_continent
				
	return largest_continent

func _get_biome(elevation: float, moisture: float) -> BiomeType:
	if elevation < -0.4: return BiomeType.DUNGEON
	if elevation < -0.2: return BiomeType.WATER
	if elevation > 0.6: return BiomeType.VOLCANO
	if elevation > 0.3 and moisture < 0: return BiomeType.TUNDRA
	if moisture < -0.3: return BiomeType.DESERT
	if moisture > 0.3: return BiomeType.FOREST
	return BiomeType.GRASSLAND

func _should_spawn_obstacle(biome: BiomeType, roll: float) -> bool:
	match biome:
		BiomeType.FOREST: return roll < 0.15
		BiomeType.DESERT: return roll < 0.05
		BiomeType.TUNDRA: return roll < 0.08
		BiomeType.VOLCANO: return roll < 0.1
		BiomeType.DUNGEON: return roll < 0.2
		BiomeType.WATER: return false
	return roll < 0.02 # Grassland

func _get_obstacle_name(biome: BiomeType) -> String:
	match biome:
		BiomeType.FOREST: return "Tree"
		BiomeType.DESERT: return "Cactus"
		BiomeType.TUNDRA: return "IceBoulder"
		BiomeType.VOLCANO: return "LavaRock"
		BiomeType.DUNGEON: return "StoneWall"
	return "Boulder"

# Guards against the debug menu's "regenerate map" flow (or any future
# mid-run regeneration) placing a brand new obstacle directly on top of a
# mech that's already standing there. Initial map generation always happens
# before any mechs exist, so this is a no-op then (no groups populated yet)
# and only matters for regeneration while a run is already in progress.
func _is_near_existing_mech(x: int, y: int) -> bool:
	if not is_inside_tree():
		return false
	var world_pos = Vector2(x * tile_size + tile_size / 2.0, y * tile_size + tile_size / 2.0)
	var clearance = tile_size * 1.5
	for group_name in ["player", "enemy"]:
		for m in get_tree().get_nodes_in_group(group_name):
			if m is Node2D and m.global_position.distance_to(world_pos) < clearance:
				return true
	return false

func get_biome_at_world_pos(pos: Vector2) -> int:
	var gx = int(round(pos.x / tile_size))
	var gy = int(round(pos.y / tile_size))
	
	if gy >= 0 and gy < terrain.size() and gx >= 0 and gx < terrain[gy].size():
		return terrain[gy][gx]
	return BiomeType.GRASSLAND

# Tiles per texture chunk. A map this size (400x250 tiles) drawn as ONE
# Image would be 12800x8000px (~102 megapixels, ~410MB uncompressed) - well
# past the 8192px-per-side limit a lot of GPUs cap textures at, meaning the
# old code risked silently failing (or getting clamped) to upload the map
# texture at all, on top of being a huge single allocation and a very slow
# ImageTexture upload. Splitting into many chunk-sized sprites keeps every
# individual texture small and safe, at the same total memory cost.
const CHUNK_TILES = 50 # 50x50 tiles = 1600x1600px per chunk @ tile_size 32

func _draw_map_to_texture():
	var wall_thickness = 20
	var blue_color = Color(0.1, 0.4, 0.9) # Nice blue wall

	var chunks_x = int(ceil(float(width) / CHUNK_TILES))
	var chunks_y = int(ceil(float(height) / CHUNK_TILES))

	for cy in range(chunks_y):
		for cx in range(chunks_x):
			_build_terrain_chunk(cx, cy, wall_thickness, blue_color)

	_build_collisions_and_obstacles()

	var map_w = width * tile_size
	var map_h = height * tile_size

	# Create collisions for the outer wall
	_create_wall_collision(Vector2(map_w/2, wall_thickness/2.0), Vector2(map_w, wall_thickness)) # Top
	_create_wall_collision(Vector2(map_w/2, map_h - wall_thickness/2.0), Vector2(map_w, wall_thickness)) # Bottom
	_create_wall_collision(Vector2(wall_thickness/2.0, map_h/2), Vector2(wall_thickness, map_h)) # Left
	_create_wall_collision(Vector2(map_w - wall_thickness/2.0, map_h/2), Vector2(wall_thickness, map_h)) # Right

# Draws one chunk's worth of terrain (+ obstacle squares + any outer-wall
# strip it touches) into its own small Image/Sprite2D. Purely visual - no
# collision is created here (see _build_collisions_and_obstacles).
func _build_terrain_chunk(cx: int, cy: int, wall_thickness: int, blue_color: Color):
	var tile_x0 = cx * CHUNK_TILES
	var tile_y0 = cy * CHUNK_TILES
	var tile_x1 = min(tile_x0 + CHUNK_TILES, width)
	var tile_y1 = min(tile_y0 + CHUNK_TILES, height)
	var chunk_w_tiles = tile_x1 - tile_x0
	var chunk_h_tiles = tile_y1 - tile_y0
	if chunk_w_tiles <= 0 or chunk_h_tiles <= 0:
		return

	var img = Image.create(chunk_w_tiles * tile_size, chunk_h_tiles * tile_size, false, Image.FORMAT_RGBA8)

	for ty in range(tile_y0, tile_y1):
		for tx in range(tile_x0, tile_x1):
			var biome = terrain[ty][tx]
			var local_x = (tx - tile_x0) * tile_size
			var local_y = (ty - tile_y0) * tile_size
			_paint_textured_tile(img, local_x, local_y, biome)

			var pos = Vector2i(tx, ty)
			if obstacles.has(pos) and obstacles[pos] != "Tree":
				var obs_rect = Rect2i(local_x + 8, local_y + 8, tile_size - 16, tile_size - 16)
				img.fill_rect(obs_rect, Color(0.2, 0.2, 0.2))

	# Paint whichever outer-wall strip(s) this chunk touches
	if tile_y0 == 0:
		img.fill_rect(Rect2i(0, 0, img.get_width(), wall_thickness), blue_color)
	if tile_y1 == height:
		img.fill_rect(Rect2i(0, img.get_height() - wall_thickness, img.get_width(), wall_thickness), blue_color)
	if tile_x0 == 0:
		img.fill_rect(Rect2i(0, 0, wall_thickness, img.get_height()), blue_color)
	if tile_x1 == width:
		img.fill_rect(Rect2i(img.get_width() - wall_thickness, 0, wall_thickness, img.get_height()), blue_color)

	var tex = ImageTexture.create_from_image(img)
	var sprite = Sprite2D.new()
	sprite.texture = tex
	sprite.centered = false
	sprite.position = Vector2(tile_x0 * tile_size, tile_y0 * tile_size)
	add_child(sprite)

# Structural pass: run-length merges collision bodies per row, same as the
# original water/dungeon-border logic, now ALSO applied to non-tree
# obstacles (Cactus/IceBoulder/LavaRock/Boulder/StoneWall). Previously every
# single obstacle tile got its own StaticBody2D+CollisionShape2D - on a
# dense biome that's potentially tens of thousands of individual physics
# bodies. Trees keep their own node each since they're real scene objects
# (TreeObstacle), not just a flat-colored square.
func _build_collisions_and_obstacles():
	for y in range(height):
		var water_start_x = -1
		var dungeon_start_x = -1
		var obstacle_start_x = -1

		for x in range(width):
			var biome = terrain[y][x]

			if biome == BiomeType.WATER:
				if water_start_x == -1:
					water_start_x = x
			else:
				if water_start_x != -1:
					_create_merged_collision(water_start_x, y, x - water_start_x, 2)
					water_start_x = -1

			if map_type == "Arena" and biome == BiomeType.DUNGEON:
				var is_border = false
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						var nx = x + dx
						var ny = y + dy
						if nx >= 0 and nx < width and ny >= 0 and ny < height:
							if terrain[ny][nx] != BiomeType.DUNGEON:
								is_border = true
								break
					if is_border: break

				if is_border:
					if dungeon_start_x == -1:
						dungeon_start_x = x
				else:
					if dungeon_start_x != -1:
						_create_merged_collision(dungeon_start_x, y, x - dungeon_start_x, 1)
						dungeon_start_x = -1
			else:
				if dungeon_start_x != -1:
					_create_merged_collision(dungeon_start_x, y, x - dungeon_start_x, 1)
					dungeon_start_x = -1

			var pos = Vector2i(x, y)
			if obstacles.has(pos):
				var obs_name = obstacles[pos]
				if obs_name == "Tree":
					if obstacle_start_x != -1:
						_create_merged_collision(obstacle_start_x, y, x - obstacle_start_x, 1)
						obstacle_start_x = -1
					_spawn_tree(Vector2(x * tile_size, y * tile_size))
				else:
					if obstacle_start_x == -1:
						obstacle_start_x = x
			else:
				if obstacle_start_x != -1:
					_create_merged_collision(obstacle_start_x, y, x - obstacle_start_x, 1)
					obstacle_start_x = -1

		if water_start_x != -1:
			_create_merged_collision(water_start_x, y, width - water_start_x, 2)
		if dungeon_start_x != -1:
			_create_merged_collision(dungeon_start_x, y, width - dungeon_start_x, 1)
		if obstacle_start_x != -1:
			_create_merged_collision(obstacle_start_x, y, width - obstacle_start_x, 1)

func _create_wall_collision(pos: Vector2, size: Vector2):
	var body = StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	
	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	
	body.position = pos
	body.add_child(shape)
	add_child(body)

func _spawn_tree(pos: Vector2):
	var body = load("res://scripts/core/TreeObstacle.gd").new()
	body.global_position = pos + Vector2(tile_size/2, tile_size/2)
	add_child(body)

func _create_collision(x: int, y: int, layer: int, shrink: int = 0):
	var body = StaticBody2D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	
	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(tile_size - shrink*2, tile_size - shrink*2)
	shape.shape = rect
	
	# Center of the tile
	body.position = Vector2(x * tile_size + tile_size/2.0, y * tile_size + tile_size/2.0)
	body.add_child(shape)
	add_child(body)

func _create_merged_collision(start_x: int, y: int, length: int, layer: int):
	var body = StaticBody2D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	
	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(tile_size * length, tile_size)
	shape.shape = rect
	
	body.position = Vector2(start_x * tile_size + (tile_size * length) / 2.0, y * tile_size + tile_size / 2.0)
	body.add_child(shape)
	add_child(body)

func _get_biome_color(biome: BiomeType) -> Color:
	match biome:
		BiomeType.GRASSLAND: return Color(0.4, 0.8, 0.4)
		BiomeType.WATER: return Color(0.2, 0.4, 0.9)
		BiomeType.DESERT: return Color(0.9, 0.8, 0.5)
		BiomeType.FOREST: return Color(0.1, 0.5, 0.2)
		BiomeType.TUNDRA: return Color(0.8, 0.9, 0.9)
		BiomeType.VOLCANO: return Color(0.3, 0.1, 0.1)
		BiomeType.DUNGEON: return Color(0.15, 0.1, 0.2)
	return Color.BLACK

# Chunky "fat pixel" size for the ground texture, in real pixels. tile_size
# (32) divided by this is how many fat pixels wide/tall each world tile is -
# 8 gives a 4x4 grid per tile, which reads as proper big-pixel/NES-era
# texture rather than the flat single-color squares this used to be.
const GROUND_PIXEL_SIZE = 8

# Replaces a single flat fill_rect per tile with a small grid of speckled
# "fat pixel" blocks, so grass/sand/etc. actually have texture instead of
# being a flat color swatch. Purely a load-time cost (baked into the chunk
# Image once, never touched again), not a per-frame one.
func _paint_textured_tile(img: Image, local_x: int, local_y: int, biome: BiomeType):
	var base = _get_biome_color(biome)
	var blocks_per_side = max(1, tile_size / GROUND_PIXEL_SIZE)

	for by in range(blocks_per_side):
		for bx in range(blocks_per_side):
			var color = _get_textured_pixel_color(base, biome)
			img.fill_rect(Rect2i(local_x + bx * GROUND_PIXEL_SIZE, local_y + by * GROUND_PIXEL_SIZE, GROUND_PIXEL_SIZE, GROUND_PIXEL_SIZE), color)

func _get_textured_pixel_color(base: Color, biome: BiomeType) -> Color:
	match biome:
		BiomeType.GRASSLAND:
			# Darker flecks read as little grass tufts, occasional lighter
			# blocks break up the flatness without looking noisy.
			var roll = randf()
			if roll < 0.22: return base.darkened(0.18 + randf() * 0.15)
			elif roll < 0.34: return base.lightened(0.1)
			return base.darkened(randf() * 0.05)
		BiomeType.FOREST:
			if randf() < 0.28: return base.darkened(0.2 + randf() * 0.15)
			return base.darkened(randf() * 0.08)
		BiomeType.DESERT:
			var roll2 = randf()
			if roll2 < 0.15: return base.darkened(0.08 + randf() * 0.1)
			elif roll2 < 0.25: return base.lightened(0.12)
			return base.darkened(randf() * 0.04)
		BiomeType.TUNDRA:
			if randf() < 0.12: return base.darkened(0.04 + randf() * 0.06)
			return base.lightened(randf() * 0.05)
		BiomeType.VOLCANO:
			if randf() < 0.15: return base.lightened(0.1 + randf() * 0.2) # ember cracks
			return base.darkened(randf() * 0.1)
		BiomeType.DUNGEON:
			if randf() < 0.2: return base.darkened(0.15 + randf() * 0.15)
			return base.darkened(randf() * 0.06)
		BiomeType.WATER:
			if randf() < 0.15: return base.lightened(0.08 + randf() * 0.1) # ripple glints
			return base.darkened(randf() * 0.04)
	return base

func get_valid_spawn_position(target_pos: Vector2) -> Vector2:
	var start_x = int(target_pos.x / tile_size)
	var start_y = int(target_pos.y / tile_size)
	var start_v = Vector2i(start_x, start_y)

	if _has_spawn_clearance(start_v):
		return target_pos

	# Spiral search for nearest tile with real clearance
	for radius in range(1, 50):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if abs(dx) == radius or abs(dy) == radius:
					var tx = clamp(start_x + dx, 0, width - 1)
					var ty = clamp(start_y + dy, 0, height - 1)
					var tv = Vector2i(tx, ty)
					if _has_spawn_clearance(tv):
						return Vector2(tx * tile_size + tile_size / 2.0, ty * tile_size + tile_size / 2.0)

	return target_pos # Fallback if all fails

# A tile being obstacle-free isn't enough on its own - mech collision boxes
# (40px) are bigger than a single tile (32px), so a mech centered on a
# "clear" tile immediately next to water/an obstacle can still physically
# overlap it. Require the full 3x3 neighborhood to be clear too. This is
# what get_valid_spawn_position uses for BOTH the player's spawn and every
# enemy squad's spawn, so it fixes overlap for both directions at once.
func _has_spawn_clearance(tile_pos: Vector2i) -> bool:
	if not main_continent_tiles.has(tile_pos):
		return false
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var nx = tile_pos.x + dx
			var ny = tile_pos.y + dy
			if nx < 0 or nx >= width or ny < 0 or ny >= height:
				continue
			if terrain[ny][nx] == BiomeType.WATER or obstacles.has(Vector2i(nx, ny)):
				return false
	return true

func _build_navigation():
	astar_grid.region = Rect2i(0, 0, width, height)
	astar_grid.cell_size = Vector2(tile_size, tile_size)
	astar_grid.offset = Vector2(tile_size / 2.0, tile_size / 2.0)
	astar_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar_grid.update()
	
	for y in range(height):
		for x in range(width):
			if terrain[y][x] == BiomeType.WATER or obstacles.has(Vector2i(x, y)):
				astar_grid.set_point_solid(Vector2i(x, y), true)

