class_name MapGenerator
extends Node2D

var width: int = 400
var height: int = 250
var tile_size: int = 32

var noise: FastNoiseLite
var moisture_noise: FastNoiseLite
var obstacle_noise: FastNoiseLite

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

	# Drives obstacle TENDRILS: obstacles cluster along the thin winding
	# zero-bands of this noise (hedgerows, ridge lines, ruin streets)
	# instead of uniform random scatter you can't walk through.
	obstacle_noise = FastNoiseLite.new()
	obstacle_noise.seed = randi()
	obstacle_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	obstacle_noise.frequency = 0.035
	
	_generate_map()
	_draw_map_to_texture()
	_build_navigation()

	if get_tree().root.has_node("ProceduralMusic"):
		ProceduralMusic.set_biome(map_type)

# -----------------------------------------------------------------------------
# SHARED FLOW FIELD - replaces N independent per-enemy AStarGrid2D searches
# -----------------------------------------------------------------------------
# Previously every enemy Mech ran its own full astar_grid.get_id_path() call
# every ~0.5-0.7s, independently, against the same destination (the player) -
# up to 80 concurrent full-grid searches on a 400x250 tile map per refresh
# window. That's the real algorithmic cost (an actual complexity-class
# problem), not just something to call less often via off-screen LOD.
#
# This computes ONE bounded BFS "integration field" around the player instead,
# refreshed on a timer, and every mech just looks up its own cell's
# precomputed direction - O(1) per mech per frame instead of O(graph) per
# mech per refresh. The field only covers a moving window around the player
# (not the whole map) since only mechs actually near the fight need routing
# detail; anything further out gets a straight-line heading toward the
# target from get_flow_direction() below and will pick up the real field
# once it gets close enough to matter.
#
# Deliberately unweighted 8-directional BFS rather than true weighted
# Dijkstra (which would match astar_grid's diagonal-cost handling exactly) -
# the accuracy difference is irrelevant for "which way should I step" AI
# steering and BFS is meaningfully cheaper to run every refresh tick.
const FLOW_FIELD_RADIUS = 28 # grid cells (~896 world units at tile_size 32)
const FLOW_FIELD_REFRESH = 0.4
const FLOW_FIELD_RECENTER_CELLS = 6.0 # target moving this many cells forces an early refresh

const _FLOW_NEIGHBOR_OFFSETS = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var flow_field: Dictionary = {} # Vector2i grid coord -> Vector2 step direction
var _flow_field_timer: float = 0.0
var _flow_field_target_cell: Vector2i = Vector2i(-999999, -999999)

func _process(delta: float):
	_flow_field_timer -= delta

	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return

	var target_cell = Vector2i(
		clamp(int(floor(players[0].global_position.x / tile_size)), 0, width - 1),
		clamp(int(floor(players[0].global_position.y / tile_size)), 0, height - 1)
	)

	var moved_far = Vector2(target_cell - _flow_field_target_cell).length() > FLOW_FIELD_RECENTER_CELLS
	if _flow_field_timer > 0.0 and not moved_far:
		return

	_flow_field_timer = FLOW_FIELD_REFRESH
	_rebuild_flow_field(target_cell)

func _rebuild_flow_field(target_cell: Vector2i):
	_flow_field_target_cell = target_cell
	flow_field.clear()

	if astar_grid.is_point_solid(target_cell):
		return # target somehow inside a solid cell - leave the field empty, mechs fall back to a straight line

	var min_x = max(0, target_cell.x - FLOW_FIELD_RADIUS)
	var max_x = min(width - 1, target_cell.x + FLOW_FIELD_RADIUS)
	var min_y = max(0, target_cell.y - FLOW_FIELD_RADIUS)
	var max_y = min(height - 1, target_cell.y + FLOW_FIELD_RADIUS)

	# Pass 1: BFS distance from the target, bounded to the window above.
	var dist: Dictionary = {target_cell: 0}
	var queue: Array = [target_cell]
	var head = 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var cur_dist = dist[cur]
		for off in _FLOW_NEIGHBOR_OFFSETS:
			var n = cur + off
			if n.x < min_x or n.x > max_x or n.y < min_y or n.y > max_y:
				continue
			if dist.has(n) or astar_grid.is_point_solid(n):
				continue
			dist[n] = cur_dist + 1
			queue.append(n)

	# Pass 2: direction extraction - each cell steps toward whichever
	# neighbor has the lowest distance value (done in a second pass since a
	# cell's best neighbor may not have been visited yet during pass 1).
	for cell in dist.keys():
		if cell == target_cell:
			flow_field[cell] = Vector2.ZERO
			continue
		var best_dist = dist[cell]
		var best_dir = Vector2i.ZERO
		for off in _FLOW_NEIGHBOR_OFFSETS:
			var n = cell + off
			if dist.has(n) and dist[n] < best_dist:
				best_dist = dist[n]
				best_dir = off
		if best_dir != Vector2i.ZERO:
			flow_field[cell] = Vector2(best_dir.x, best_dir.y).normalized()

# Called by Mech._execute_ai_tactics instead of running its own A* search.
# Returns a normalized world-space direction toward fallback_target_pos -
# from the shared field if world_pos's cell has one, otherwise a straight
# line (mech is outside the field's current bounded window).
func get_flow_direction(world_pos: Vector2, fallback_target_pos: Vector2) -> Vector2:
	var cell = Vector2i(
		clamp(int(floor(world_pos.x / tile_size)), 0, width - 1),
		clamp(int(floor(world_pos.y / tile_size)), 0, height - 1)
	)
	if flow_field.has(cell):
		var dir: Vector2 = flow_field[cell]
		if dir != Vector2.ZERO:
			return dir
	return world_pos.direction_to(fallback_target_pos)

func _generate_map():
	# Tabletop: a 4x8ft table with blue firring-strip walls.
	# CANONICAL SCALE, REVISED (design ruling - also governs section 6
	# melee/mass): pixbots are 20mm miniatures, not 4-7" toys. A ~100px
	# mech sprite = 20mm, so 1mm = 5px and 1 inch = 127px. The 96"x48"
	# table is therefore ~12192x6096px = ~381x190 tiles - rounded to
	# 384x192. The arena is now nearly the size of the classic maps, which
	# matches the game's pace. Dimensions must be (re)set here, not just at
	# _ready, because the debug menu regenerates different map types on
	# this same node - switching sizes must restore correctly both ways.
	if map_type == "Tabletop":
		width = 384
		height = 192
	else:
		width = 400
		height = 250

	var map_valid = false
	var required_size = width * height * 0.3 # 30% of map
	
	while not map_valid:
		terrain.clear()
		obstacles.clear()
		ruin_specs.clear()
		
		# Generate a new seed on each retry
		noise.seed = randi()
		moisture_noise.seed = randi()
		if obstacle_noise:
			obstacle_noise.seed = randi()
		
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
				elif map_type == "Tabletop":
					# Plywood reads as desert-tan; the blue outer walls are
					# already the "firring strips tacked to the edges".
					biome = BiomeType.DESERT
				else:
					var elev = noise.get_noise_2d(x, y)
					var moist = moisture_noise.get_noise_2d(x, y)
					biome = _get_biome(elev, moist)
					
				row.append(biome)
				
				if map_type not in ["Arena", "Open Field", "Tabletop"] and _should_spawn_obstacle(biome, randf(), x, y):
					if not _is_near_existing_mech(x, y):
						obstacles[Vector2i(x, y)] = _get_obstacle_name(biome)
			terrain.append(row)
			
		# Tabletop terrain kits: gothic-ruin buildings scattered like a
		# real game-shop table setup (see the reference photo in design
		# notes - grey plastic ruins on a flocked mat). Also available on
		# any other map type via force_ruins (debug menu toggle).
		if map_type == "Tabletop" or force_ruins:
			_place_tabletop_ruins()

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

# Multi-tile ruined-building footprints. Originally Tabletop-only; now
# usable on any map_type (see `force_ruins`, set by the debug menu) since
# Natalia wanted ruins available everywhere, not just the tabletop preset.
# Tiles are marked "RuinPart" in `obstacles` (so the minimap, spawn anchors,
# and nav all treat them as solid terrain) and one destructible RuinObstacle
# node per building is spawned in _build_collisions_and_obstacles.
var ruin_specs: Array = []
var force_ruins: bool = false # debug-menu override to spawn ruins on non-Tabletop maps

# Minimum distance (in tiles) a ruin footprint's NEAREST EDGE must keep from
# the map's spawn center (player always spawns at exact map center - see
# Main.gd:247). Deliberately larger than the 1-tile radius
# _has_spawn_clearance() requires for a plain mech spawn, since ruins are
# multi-tile and get_valid_spawn_position() will happily wedge the player
# right up against whatever's nearest if the center itself is blocked.
const RUIN_CENTER_CLEARANCE_TILES = 6.0

func _place_tabletop_ruins():
	ruin_specs.clear()
	# Base density is tuned for the 64x32 Tabletop preset (2048 tiles). On
	# bigger maps (Normal/biome maps are 400x250 = 100,000 tiles) scale the
	# count up by the linear (sqrt-of-area) ratio so ruins read as a
	# battlefield feature rather than 8 lonely buildings lost in a huge
	# field - capped so generation can't run away on extreme map sizes.
	var density_scale = sqrt(float(width * height) / 2048.0)
	var target_count = min(80, int((7 + randi() % 3) * density_scale))
	var attempts = 0
	var max_attempts = max(200, target_count * 30)
	var center = Vector2(width / 2.0, height / 2.0)
	while ruin_specs.size() < target_count and attempts < max_attempts:
		attempts += 1
		# Kit size mix at 20mm scale: mostly small scatter ruins, but ~20%
		# are big centerpiece kits (the ruined-cathedral pieces from the
		# reference table photo) - 8-14 tiles wide reads as a real building
		# a mech fights THROUGH, not just behind.
		var w: int
		var h: int
		if randf() < 0.2:
			w = 8 + randi() % 7  # 8-14 tiles wide centerpiece
			h = 5 + randi() % 4  # 5-8 tiles deep
		else:
			w = 2 + randi() % 4 # 2-5 tiles wide scatter kit
			h = 2 + randi() % 2 # 2-3 tiles deep
		var ox = 3 + randi() % max(1, width - w - 6)
		var oy = 3 + randi() % max(1, height - h - 6)

		# Keep the map's spawn center clear for the player's starting scrum.
		# Uses the closest point ON THE FOOTPRINT RECT to the center, not
		# just the footprint's own center coordinate - the old center-point
		# check could pass while the building's actual near edge sat right
		# next to the spawn point, since it never accounted for footprint
		# size when measuring distance.
		var closest_x = clamp(center.x, ox, ox + w - 1)
		var closest_y = clamp(center.y, oy, oy + h - 1)
		if Vector2(closest_x, closest_y).distance_to(center) < RUIN_CENTER_CLEARANCE_TILES:
			continue

		# Reject overlaps (other ruins, tendril obstacles, water), with a
		# two-tile buffer between kits - wide enough that a mech's collision
		# box (bigger than one tile) can't straddle two adjacent buildings
		# or get pinned in a one-tile gap between them.
		var area_clear = true
		for y in range(oy - 2, oy + h + 2):
			for x in range(ox - 2, ox + w + 2):
				if x < 0 or x >= width or y < 0 or y >= height:
					area_clear = false
					break
				if obstacles.has(Vector2i(x, y)) or terrain[y][x] == BiomeType.WATER:
					area_clear = false
					break
			if not area_clear:
				break
		if not area_clear:
			continue

		for y in range(oy, oy + h):
			for x in range(ox, ox + w):
				obstacles[Vector2i(x, y)] = "RuinPart"
		ruin_specs.append({"x": ox, "y": oy, "w": w, "h": h})

# Tendril-clustered obstacles (design ruling): instead of uniform random
# scatter dense enough to wall off movement, obstacles concentrate along
# the thin winding zero-bands of obstacle_noise - reading as hedgerows,
# tree lines, and rubble streets with big open lanes between them. A tiny
# lone-obstacle chance outside the tendrils keeps maps from feeling
# manicured.
func _should_spawn_obstacle(biome: BiomeType, roll: float, x: int = 0, y: int = 0) -> bool:
	if biome == BiomeType.WATER:
		return false

	var in_tendril = abs(obstacle_noise.get_noise_2d(x, y)) < 0.08 if obstacle_noise else false

	if not in_tendril:
		return roll < 0.004 # rare lone tree/boulder

	match biome:
		BiomeType.FOREST: return roll < 0.55
		BiomeType.DESERT: return roll < 0.25
		BiomeType.TUNDRA: return roll < 0.30
		BiomeType.VOLCANO: return roll < 0.35
		BiomeType.DUNGEON: return roll < 0.50
	return roll < 0.15 # Grassland

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
	# CRITICAL for regeneration: every child of MapGenerator is generated
	# output (chunk sprites, collision bodies, trees, ruins). The old code
	# never cleared them, so each debug-menu map swap STACKED a whole new
	# map's sprites and physics bodies on top of the old ones - invisible
	# while all maps were the same size, glaring once Tabletop (64x32)
	# painted its little sheet in the corner of the stale 400x250 map.
	for child in get_children():
		child.queue_free()

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
			# Trees and RuinParts have real scene nodes drawing them - only
			# flat obstacle types get the painted grey square.
			if obstacles.has(pos) and obstacles[pos] != "Tree" and obstacles[pos] != "RuinPart":
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
				if obs_name == "Tree" or obs_name == "RuinPart":
					# Node-based obstacles bring their own collision
					# (TreeObstacle / RuinObstacle) - exclude them from the
					# merged flat-collision run.
					if obstacle_start_x != -1:
						_create_merged_collision(obstacle_start_x, y, x - obstacle_start_x, 1)
						obstacle_start_x = -1
					if obs_name == "Tree":
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

	# One destructible terrain-kit node per placed ruin (Tabletop, or any
	# other map type with force_ruins on - ruin_specs is simply empty
	# otherwise, so this loop is a no-op on maps without ruins).
	for spec in ruin_specs:
		var ruin = load("res://scripts/core/RuinObstacle.gd").new()
		ruin.size_tiles = Vector2i(spec.w, spec.h)
		ruin.origin_tile = Vector2i(spec.x, spec.y)
		ruin.footprint = Vector2(spec.w * tile_size, spec.h * tile_size)
		ruin.map_ref = self
		ruin.global_position = Vector2(spec.x * tile_size, spec.y * tile_size) + ruin.footprint / 2.0
		add_child(ruin)

	_scatter_oil_slicks()

# Sparse, walkable environmental hazard - dark puddles scattered on
# DESERT/VOLCANO ground (oil-field/wasteland flavor) that do nothing until a
# FIRE-synergy hit lands nearby, then burn for a few seconds (see
# OilSlickHazard.gd). Deliberately excludes solid-obstacle tiles (nothing to
# ignite would ever be visible/reachable there) and water tiles (a puddle on
# water reads as a bug, not a feature). Rare enough to feel like a set-piece
# rather than a shotgunned biome decal.
const OIL_SLICK_CHANCE = 0.006
func _scatter_oil_slicks():
	if map_type in ["Arena", "Open Field"]:
		return
	for y in range(height):
		for x in range(width):
			var biome = terrain[y][x]
			if biome != BiomeType.DESERT and biome != BiomeType.VOLCANO:
				continue
			var pos = Vector2i(x, y)
			if obstacles.has(pos):
				continue
			if randf() < OIL_SLICK_CHANCE:
				var slick = load("res://scripts/hazards/OilSlickHazard.gd").new()
				slick.global_position = Vector2(x * tile_size + tile_size / 2.0, y * tile_size + tile_size / 2.0)
				slick.radius = tile_size * (0.9 + randf() * 0.5)
				add_child(slick)

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
	# Tabletop's ground reads as a painted + flocked wargaming mat (rust
	# red, like the reference table) rather than raw desert sand. Handled
	# here so the minimap bake picks up the mat color for free.
	if map_type == "Tabletop" and biome == BiomeType.DESERT:
		return Color(0.52, 0.24, 0.16)
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
	# Flock texture for the Tabletop mat: mottled rust with darker worn
	# patches, grey-brown scatter (static grass / basing grit), and the
	# occasional bright fleck where the flock's thin and paint shows.
	if map_type == "Tabletop":
		var flock_roll = randf()
		if flock_roll < 0.14: return base.darkened(0.15 + randf() * 0.2)
		elif flock_roll < 0.22: return Color(0.42, 0.33, 0.26).lerp(base, 0.4) # grit
		elif flock_roll < 0.27: return base.lightened(0.12 + randf() * 0.1)
		return base.darkened(randf() * 0.06)
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

