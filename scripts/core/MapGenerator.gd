class_name MapGenerator
extends Node2D

var width: int = 100
var height: int = 100
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
		var arena_radius = 40.0
		
		for y in range(height):
			var row = []
			for x in range(width):
				var biome = BiomeType.GRASSLAND
				
				if map_type == "Arena":
					var dist = Vector2(x, y).distance_to(arena_center)
					if dist > arena_radius:
						biome = BiomeType.DUNGEON
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

func get_biome_at_world_pos(pos: Vector2) -> int:
	var gx = int(round(pos.x / tile_size))
	var gy = int(round(pos.y / tile_size))
	
	if gy >= 0 and gy < terrain.size() and gx >= 0 and gx < terrain[gy].size():
		return terrain[gy][gx]
	return BiomeType.GRASSLAND

func _draw_map_to_texture():
	var img = Image.create(width * tile_size, height * tile_size, false, Image.FORMAT_RGBA8)
	
	for y in range(height):
		for x in range(width):
			var biome = terrain[y][x]
			var color = _get_biome_color(biome)
			var rect = Rect2i(x * tile_size, y * tile_size, tile_size, tile_size)
			img.fill_rect(rect, color)
			
			# Generate Physics Collisions
			if biome == BiomeType.WATER:
				_create_collision(x, y, 2) # Water is layer 2
			
			# Handle obstacles
			if obstacles.has(Vector2i(x, y)):
				var obs_name = obstacles[Vector2i(x, y)]
				if obs_name == "Tree":
					_spawn_tree(Vector2(x * tile_size, y * tile_size))
				else:
					var obs_rect = Rect2i(x * tile_size + 8, y * tile_size + 8, tile_size - 16, tile_size - 16)
					img.fill_rect(obs_rect, Color(0.2, 0.2, 0.2))
					_create_collision(x, y, 1, 8) # Obstacles are layer 1
				
	var tex = ImageTexture.create_from_image(img)
	var sprite = Sprite2D.new()
	sprite.texture = tex
	sprite.centered = false
	add_child(sprite)

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

func get_valid_spawn_position(target_pos: Vector2) -> Vector2:
	var start_x = int(target_pos.x / tile_size)
	var start_y = int(target_pos.y / tile_size)
	var start_v = Vector2i(start_x, start_y)
	
	if main_continent_tiles.has(start_v):
		return target_pos
		
	# Spiral search for nearest tile in the main continent
	for radius in range(1, 50):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if abs(dx) == radius or abs(dy) == radius:
					var tx = clamp(start_x + dx, 0, width - 1)
					var ty = clamp(start_y + dy, 0, height - 1)
					var tv = Vector2i(tx, ty)
					if main_continent_tiles.has(tv):
						return Vector2(tx * tile_size + tile_size / 2.0, ty * tile_size + tile_size / 2.0)
						
	return target_pos # Fallback if all fails

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

