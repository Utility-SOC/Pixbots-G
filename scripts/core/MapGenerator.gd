class_name MapGenerator
extends Node2D

# preload rather than bare class_name reference - a freshly-added
# class_name script isn't in a headless run's global class cache until the
# editor has rescanned the project (same "fresh-checkout class-cache bug"
# build_installer.ps1 works around with a warm-up pass), so a bare
# `DestructibleObstacle.OBSTACLE_STATS` reference can fail to resolve.
const DestructibleObstacleScript = preload("res://scripts/core/DestructibleObstacle.gd")
const MapStructure = preload("res://scripts/core/MapStructure.gd")

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
# Non-zero = deterministic generation (daily seed / shared run cards). The
# global RNG is seeded for the generation window only, then re-randomized.
var map_seed: int = 0

# Macro layout laid over the biome/obstacle scatter (map variety): "auto"
# rolls one (30% none); any LAYOUTS name forces it. layout_name is what was
# actually applied. Only land-ish types take layouts - Arena/Tabletop/
# FightShovel/Water have hand-built identities.
const LAYOUTS = ["none", "river", "ridges", "pillars", "rings", "canyon", "crossroads"]
const LAYOUT_ROLL = ["none", "none", "none", "river", "river", "ridges", "ridges", "pillars", "rings", "canyon", "crossroads"]
const LAYOUT_TYPES = ["Normal", "Open Field", "Desert", "Forest", "Tundra", "Volcano", "Dungeon"]
const LAYOUT_KEEPOUT_TILES = 14.0 # player spawns at the centre
var map_layout: String = "auto"
var layout_name: String = "none"

# Fraction of tiles that came out BiomeType.WATER on this generation -
# "Water" map_type floods the whole map with this, but "Normal" maps can
# also roll a big lake from the elevation noise (_get_biome), so this is
# computed from the actual terrain grid rather than inferred from map_type.
# Consumed by SquadDirector/TemplateEvolution to bias squad composition
# toward water-capable roles instead of spawning e.g. an all-flamethrower
# squad that just drowns chasing the player across a lake.
var water_fraction: float = 0.0

const MOSTLY_WATER_THRESHOLD = 0.5

# Read by Mech.build_loadout_for_role: on a map this wet, every enemy
# loadout gets a guaranteed Jumpjet fed to the solver rather than leaving
# water survival to the "diver" role alone (see also TemplateEvolution's
# softer water_fraction bias, which only shifts which SQUAD spawns).
func is_mostly_water() -> bool:
	return water_fraction > MOSTLY_WATER_THRESHOLD

enum BiomeType { GRASSLAND, WATER, DESERT, FOREST, TUNDRA, VOLCANO, DUNGEON, ROAD, FLOOR, SHALLOW }

# --- FightShovel 1920: corn fields + trampled trails (Utility-SOC) --------
# Vector2i -> true for every tile marked as corn during generation (see the
# FightShovel branch in the per-tile loop below). Walkable, distinct
# texture (see _paint_textured_tile), and tracked by a separate always-on-
# top overlay node (CornTrailOverlay) rather than mutating the baked ground
# chunk textures - those are deliberately baked ONCE at load and never
# touched again (see _draw_map_to_texture's own comment on that).
var corn_field_cells: Dictionary = {}
# Zones from the structure pass: {pos (tiles), kind, r (tiles)}. Forts and villages become objectives.
var zones: Array = []
var corn_trail_overlay: Node2D = null
const CORN_COLOR = Color(0.55, 0.62, 0.18)
# Threshold against moisture_noise (already computed per-tile for the
# Normal-map biome dispatch, just repurposed here) - high enough that corn
# reads as a handful of real contiguous fields, not a wall-to-wall crop.
const CORN_FIELD_THRESHOLD = 0.32

func _ensure_corn_trail_overlay():
	if corn_field_cells.is_empty():
		corn_trail_overlay = null
		return
	var overlay = load("res://scripts/core/CornTrailOverlay.gd").new()
	overlay.name = "CornTrailOverlay"
	overlay.tile_size = float(tile_size)
	add_child(overlay)
	corn_trail_overlay = overlay

# Called by Mech._refresh_water_state (same per-mech-per-tick terrain-lookup
# precedent that function already established) whenever a mech's current
# tile is corn - marks it permanently trampled for the rest of the run (no
# regrowth timer, simplest reading of "leaves a trail").
func trample_corn(cell: Vector2i):
	if not corn_field_cells.has(cell):
		return
	if corn_trail_overlay:
		corn_trail_overlay.trample(cell)

func _ready():
	add_to_group("map_generator")
	
	# "Normal" map type gets larger-scale terrain/obstacle features than the
	# other types (per the user: bigger island/biome patches, wider gaps
	# between obstacle clusters) - halving these noise frequencies doubles
	# the real-world size of every feature they drive (biome patches AND
	# obstacle tendril bands), since a lower-frequency noise field varies
	# more slowly across the same tile grid.
	var freq_scale = 0.5 if map_type == "Normal" else 1.0

	# Second pass (per the user: Normal maps are "VERY noisy" even after the
	# freq_scale halving above) - the previous pass only addressed the base
	# frequency, but with FRACTAL_FBM's default lacunarity/gain (2.0/0.5),
	# 4 octaves still layers in detail up to 8x the base frequency. That
	# highest-octave wiggle is exactly what reads as "noisy" jagged biome
	# edges even when the underlying island shapes are big - it doesn't
	# meaningfully change WHICH biome a region becomes, just how ragged its
	# border looks tile-to-tile. Normal's elevation/moisture fields (which
	# _get_biome thresholds into biomes) get their own further-reduced
	# frequency AND fewer octaves; obstacle_noise is untouched since obstacle
	# tendril spacing is a separate concern the user didn't raise here.
	var biome_freq_scale = freq_scale * 0.5 if map_type == "Normal" else freq_scale
	var biome_octaves = 2 if map_type == "Normal" else 4

	noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = biome_octaves
	noise.frequency = 0.05 * biome_freq_scale

	moisture_noise = FastNoiseLite.new()
	moisture_noise.seed = randi()
	moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	moisture_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	moisture_noise.fractal_octaves = biome_octaves
	moisture_noise.frequency = 0.04 * biome_freq_scale

	# Drives obstacle TENDRILS: obstacles cluster along the thin winding
	# zero-bands of this noise (hedgerows, ridge lines, ruin streets)
	# instead of uniform random scatter you can't walk through.
	obstacle_noise = FastNoiseLite.new()
	obstacle_noise.seed = randi()
	obstacle_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	obstacle_noise.frequency = 0.035 * freq_scale
	
	if map_seed != 0:
		seed(map_seed)
		noise.seed = map_seed
		moisture_noise.seed = map_seed + 1
		obstacle_noise.seed = map_seed + 2
	_generate_map()
	_draw_map_to_texture()
	_build_navigation()
	if map_seed != 0:
		randomize()

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

# Shared 4-directional offsets for the flood-fill connectivity scans
# (_carve_pocket_corridors/_connect_pocket/_analyze_connectivity) - these
# used to each allocate a fresh 4-element Vector2i array literal per visited
# cell (100k+ times per full-map pass); reusing one const array avoids that
# allocation churn without changing which cells get visited.
const _CARDINAL_NEIGHBOR_OFFSETS = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

var flow_field: Dictionary = {} # Vector2i grid coord -> Vector2 step direction
var _flow_field_timer: float = 0.0
var _flow_field_target_cell: Vector2i = Vector2i(-999999, -999999)

# Phase 3 of the AI-tactics Rust-cutover plan (see
# C:\Users\Utility\.claude\plans\effervescent-drifting-kazoo.md) - optional
# native accelerator for _rebuild_flow_field's bounded BFS, same lazy-check/
# graceful-fallback pattern as _terrain_rasterizer above. Deliberately its
# own separate solidity buffer (terrain==WATER OR obstacles.has, matching
# astar_grid exactly) rather than reusing SolidGridBatcher's obstacle-only
# LOS buffer (Phase 1) - see flow_field.rs's header comment for why they
# can't share one.
var _flow_field_rasterizer = null
var _flow_field_rasterizer_checked: bool = false
var _flow_field_grid_obstacle_count: int = -1

func _ensure_flow_field_rust():
	if not _flow_field_rasterizer_checked:
		_flow_field_rasterizer_checked = true
		if ClassDB.class_exists("FlowFieldRs"):
			_flow_field_rasterizer = ClassDB.instantiate("FlowFieldRs")

# Piggybacks on the same obstacles.size()-change signal SolidGridBatcher.gd
# uses (Dictionary.erase always shrinks it, obstacle destruction is the only
# way this ever changes post-generation) - water never changes after
# generation either, so the buffer only needs rebuilding this rarely.
func _rebuild_flow_field_solidity_buffer():
	var solidity = PackedByteArray()
	solidity.resize(width * height)
	for y in range(height):
		for x in range(width):
			if terrain[y][x] == BiomeType.WATER or obstacles.has(Vector2i(x, y)):
				solidity[y * width + x] = 1
	_flow_field_rasterizer.set_grid(solidity, width, height)

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
	# Phase 0/3 instrumentation for the AI-tactics Rust-cutover plan (see
	# C:\Users\Utility\.claude\plans\effervescent-drifting-kazoo.md) - wraps
	# the WHOLE rebuild (both BFS passes, or the Rust equivalent), distinct
	# from Mech.gd's _perf_flow_field_usec, which only ever measured the
	# O(1) per-mech get_flow_direction lookup. Phase 0's real number here
	# (~6.8-7.6ms per rebuild on a 0.4s cadence, a genuine periodic stutter)
	# is what justified Phase 3's Rust port below.
	var _t_flow_rebuild = Time.get_ticks_usec()
	_flow_field_target_cell = target_cell
	flow_field.clear()

	_ensure_flow_field_rust()
	if _flow_field_rasterizer:
		if _flow_field_grid_obstacle_count != obstacles.size():
			_flow_field_grid_obstacle_count = obstacles.size()
			_rebuild_flow_field_solidity_buffer()
		var results = _flow_field_rasterizer.rebuild(target_cell.x, target_cell.y, FLOW_FIELD_RADIUS)
		for entry in results:
			flow_field[entry.cell] = entry.dir
	else:
		_rebuild_flow_field_fallback(target_cell)

	Mech._perf_flow_field_rebuild_usec += Time.get_ticks_usec() - _t_flow_rebuild

# Pure-GDScript reference implementation - the fallback contract every
# Rust-ported system in this codebase keeps (see
# SeparationBatcher._batch_compute_separation_fallback). Unlike Phase 1/2's
# accepted soft-heuristic approximations, this one must stay byte-identical
# to FlowFieldRs.rebuild() - verified via FlowFieldParityCheck.gd - since
# flow-field routing is navigation-affecting, not a soft heuristic.
func _rebuild_flow_field_fallback(target_cell: Vector2i):
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
		zones = []
		ruin_specs.clear()
		corn_field_cells.clear()
		var water_tile_count = 0
		
		# Generate a new seed on each retry
		noise.seed = randi()
		moisture_noise.seed = randi()
		if obstacle_noise:
			obstacle_noise.seed = randi()
		
		var region_seeds: Array = MapStructure.prepare_regions(self) if map_type == "Normal" else []
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
				elif map_type == "FightShovel":
					# Dust Bowl farmland - see _get_biome_color/
					# _get_textured_pixel_color for the palette/texture
					# override and _get_obstacle_name for the fence-line
					# obstacle. Reuses DESERT as the base biome, same as
					# Tabletop reusing it for the plywood mat.
					biome = BiomeType.DESERT
				else:
					# Normal: a handful of big contiguous regions (warped Voronoi)
					# rather than the old noise-threshold patchwork that read as camo.
					biome = MapStructure.region_biome(self, region_seeds, x, y)
					
				row.append(biome)
				if biome == BiomeType.WATER:
					water_tile_count += 1

				if map_type == "FightShovel" and biome == BiomeType.DESERT and moisture_noise.get_noise_2d(x, y) > CORN_FIELD_THRESHOLD:
					corn_field_cells[Vector2i(x, y)] = true

				if map_type not in ["Arena", "Open Field", "Tabletop"] and _should_spawn_obstacle(biome, randf(), x, y):
					if not _is_near_existing_mech(x, y):
						obstacles[Vector2i(x, y)] = _get_obstacle_name(biome)
			terrain.append(row)
			
		# Structure pass: zones, built set pieces and roads (land maps) or
		# real rooms+corridors (Dungeon), before the macro layout overlay.
		if map_type == "Dungeon":
			MapStructure.build_dungeon(self)
		elif map_type in MapStructure.ZONE_WEIGHTS:
			MapStructure.build_regions(self)
			water_tile_count = 0
			for wy in range(height):
				for wx in range(width):
					if terrain[wy][wx] == BiomeType.WATER:
						water_tile_count += 1

		if map_type in LAYOUT_TYPES and map_type != "Dungeon":
			layout_name = map_layout if map_layout != "auto" else LAYOUT_ROLL[randi() % LAYOUT_ROLL.size()]
			if not LAYOUTS.has(layout_name):
				layout_name = "none"
			water_tile_count += _apply_layout(layout_name)
		else:
			layout_name = "none"

		# Tabletop terrain kits: gothic-ruin buildings scattered like a
		# real game-shop table setup (see the reference photo in design
		# notes - grey plastic ruins on a flocked mat). Also available on
		# any other map type via force_ruins (debug menu toggle).
		if map_type == "FightShovel":
			water_tile_count += _fightshovel_ponds()
			_place_fightshovel_structures()
			_fightshovel_tracks()
		elif map_type == "Tabletop" or force_ruins:
			_place_tabletop_ruins()
		if map_type == "Tabletop":
			_tabletop_forest_bases()
		elif map_type == "Open Field":
			_open_field_cover()

		# Connectivity guarantee (play report: "no meaningful gaps - easy to
		# get boxed in and unable to advance" on Forest/Volcano). Obstacle
		# tendrils can seal walkable pockets off entirely; carve corridors
		# from every meaningful pocket back to the main continent BEFORE
		# collision/nav/spawn data are built from the obstacles dict.
		_mark_shallows()
		_carve_pocket_corridors()

		main_continent_tiles = _analyze_connectivity()
		if map_type != "Normal" or main_continent_tiles.size() >= required_size:
			map_valid = true
			water_fraction = float(water_tile_count) / float(width * height)

# ---------------------------------------------------------------------------
# Macro layouts (see LAYOUTS). Each writes into `obstacles` / `terrain` only,
# keeps the centre spawn area clear, and leaves the usual connectivity carver
# to guarantee everything stays reachable. Returns water tiles added.
# ---------------------------------------------------------------------------
func _layout_keepout(x: int, y: int) -> bool:
	return Vector2(x - width / 2.0, y - height / 2.0).length() < LAYOUT_KEEPOUT_TILES

func _layout_in_bounds(x: int, y: int) -> bool:
	return x >= 3 and y >= 3 and x < width - 3 and y < height - 3

func _layout_block(x: int, y: int, name: String = "") -> void:
	if not _layout_in_bounds(x, y) or _layout_keepout(x, y):
		return
	if terrain[y][x] == BiomeType.WATER:
		return
	obstacles[Vector2i(x, y)] = name if name != "" else _get_obstacle_name(terrain[y][x])

func _layout_clear(x: int, y: int) -> void:
	if x >= 0 and y >= 0 and x < width and y < height:
		obstacles.erase(Vector2i(x, y))

# Wall of `thickness` between two tile points with periodic gaps.
func _layout_wall(a: Vector2, b: Vector2, thickness: int, gap_every: float, gap_len: float) -> void:
	var length = a.distance_to(b)
	var dir = (b - a) / max(length, 1.0)
	var steps = int(length)
	var next_gap = gap_every * randf_range(0.5, 1.0)
	var gap_left = 0.0
	for i in range(steps):
		if i >= next_gap:
			gap_left = gap_len
			next_gap += gap_every * randf_range(0.8, 1.2)
		if gap_left > 0.0:
			gap_left -= 1.0
			continue
		var p = a + dir * float(i)
		for t in range(thickness):
			var off = Vector2(-dir.y, dir.x) * (t - thickness / 2.0)
			_layout_block(int(p.x + off.x), int(p.y + off.y))

func _apply_layout(name: String) -> int:
	match name:
		"river":
			return _layout_river()
		"ridges":
			_layout_ridges()
		"pillars":
			_layout_pillars()
		"rings":
			_layout_rings()
		"canyon":
			_layout_canyon()
		"crossroads":
			_layout_crossroads()
	return 0

# A meandering water band across the map with a few land bridges.
func _layout_river() -> int:
	var vertical = randf() < 0.5
	var along = height if vertical else width
	var across = width if vertical else height
	var base = across * randf_range(0.3, 0.7)
	var amp1 = randf_range(8.0, 22.0)
	var amp2 = randf_range(3.0, 8.0)
	var f1 = randf_range(0.02, 0.04)
	var f2 = randf_range(0.07, 0.12)
	var ph1 = randf() * TAU
	var ph2 = randf() * TAU
	var half_w = randi_range(2, 3)
	var bridges: Array = []
	for i in range(3):
		bridges.append(int(along * (0.15 + 0.3 * i + randf_range(-0.05, 0.05))))
	var added = 0
	for i in range(3, along - 3):
		var bridge = false
		for b in bridges:
			if abs(i - b) <= 3:
				bridge = true
		if bridge:
			continue
		var centre = int(base + amp1 * sin(i * f1 + ph1) + amp2 * sin(i * f2 + ph2))
		for w in range(-half_w, half_w + 1):
			var c = centre + w
			var x = c if vertical else i
			var y = i if vertical else c
			if not _layout_in_bounds(x, y) or _layout_keepout(x, y):
				continue
			if terrain[y][x] != BiomeType.WATER:
				terrain[y][x] = BiomeType.WATER
				added += 1
			_layout_clear(x, y)
	return added

# Long broken ridge walls: choke points and cover without sealing anything.
func _layout_ridges() -> void:
	for i in range(randi_range(3, 5)):
		var start = Vector2(randf_range(20, width - 20), randf_range(20, height - 20))
		var ang = randf() * PI
		var length = randf_range(45.0, 95.0)
		var end = start + Vector2.RIGHT.rotated(ang) * length
		_layout_wall(start, end, 2, randf_range(12.0, 20.0), randf_range(4.0, 6.0))

# A lattice of 2x2 pillars: lots of cover in open ground.
func _layout_pillars() -> void:
	var spacing = randi_range(11, 15)
	for gy in range(spacing, height - spacing, spacing):
		for gx in range(spacing, width - spacing, spacing):
			var x = gx + randi_range(-2, 2)
			var y = gy + randi_range(-2, 2)
			for dy in range(2):
				for dx in range(2):
					_layout_block(x + dx, y + dy)

# Concentric broken rings around the spawn: fight out through the gaps.
func _layout_rings() -> void:
	var cx = width / 2.0
	var cy = height / 2.0
	for radius in [32.0, 58.0, 84.0]:
		var gap_centers: Array = []
		for k in range(4):
			gap_centers.append(randf() * TAU)
		var circ = int(TAU * radius * 1.5)
		for i in range(circ):
			var ang = TAU * float(i) / float(circ)
			var in_gap = false
			for g in gap_centers:
				if abs(angle_difference(ang, g)) * radius < 4.0:
					in_gap = true
			if in_gap:
				continue
			var x = int(cx + cos(ang) * radius)
			var y = int(cy + sin(ang) * radius * 0.75)
			for t in range(2):
				_layout_block(x + t, y)

# Two parallel long walls: a central lane with side flanks.
func _layout_canyon() -> void:
	var horizontal = randf() < 0.7
	var gap = randf_range(16.0, 24.0)
	for sgn in [-1.0, 1.0]:
		if horizontal:
			var y = height / 2.0 + sgn * gap
			_layout_wall(Vector2(3, y), Vector2(width - 3, y), 3, randf_range(45.0, 70.0), randf_range(6.0, 9.0))
		else:
			var x = width / 2.0 + sgn * gap * 1.6
			_layout_wall(Vector2(x, 3), Vector2(x, height - 3), 3, randf_range(35.0, 55.0), randf_range(6.0, 9.0))

# Four wide lanes from the spawn; the quadrants between get denser cover.
func _layout_crossroads() -> void:
	var cx = int(width / 2.0)
	var cy = int(height / 2.0)
	for y in range(3, height - 3):
		for x in range(3, width - 3):
			var in_lane = abs(x - cx) <= 6 or abs(y - cy) <= 6
			if in_lane:
				_layout_clear(x, y)
			elif not obstacles.has(Vector2i(x, y)) and obstacle_noise and obstacle_noise.get_noise_2d(x, y) > 0.05 and randf() < 0.35:
				_layout_block(x, y)

# A walkable pocket this size or bigger MUST be reachable from the main
# continent without crossing obstacles. Smaller slivers aren't worth a
# corridor (nothing spawns there and you can't wander in).
const MIN_POCKET_SIZE = 6

# Finds every walkable region, then for each non-main pocket of meaningful
# size BFS-walks THROUGH obstacle cells (never water - lakes are a designed
# barrier with their own traversal rules, and RuinParts stay intact - blast
# your own door through a building, that's what destructible ruins are for)
# to the nearest main-continent cell and deletes the obstacles along that
# path, widened by one cell. Obstacle-locked pockets stop existing; water-
# locked pockets are left alone on purpose.
func _carve_pocket_corridors():
	var visited = {}
	var regions: Array = []
	for y in range(height):
		for x in range(width):
			var pos = Vector2i(x, y)
			if visited.has(pos) or terrain[y][x] == BiomeType.WATER or obstacles.has(pos):
				continue
			var region = {pos: true}
			visited[pos] = true
			var queue = [pos]
			var head = 0
			while head < queue.size():
				var curr = queue[head]
				head += 1
				for off in _CARDINAL_NEIGHBOR_OFFSETS:
					var n = curr + off
					if n.x < 0 or n.x >= width or n.y < 0 or n.y >= height:
						continue
					if visited.has(n) or terrain[n.y][n.x] == BiomeType.WATER or obstacles.has(n):
						continue
					visited[n] = true
					region[n] = true
					queue.append(n)
			regions.append(region)

	if regions.size() <= 1:
		return
	regions.sort_custom(func(a, b): return a.size() > b.size())
	var main_region = regions[0]

	for i in range(1, regions.size()):
		var region = regions[i]
		if region.size() < MIN_POCKET_SIZE:
			continue
		# Tier 1: prefer a corridor through carvable OBSTACLES only, so
		# designed lakes/ruins stay intact where that's enough to connect.
		if _connect_pocket(region, main_region, false):
			continue
		# Tier 2: the pocket is water/ruin-locked. Per the user - "EVERY map
		# must have a clear path to any part so you never get stuck in a
		# cul-de-sac that keeps you from the garage" - carve through water
		# and ruin too rather than leaving it sealed. A land bridge through
		# a lake is a fair price for guaranteed traversability.
		_connect_pocket(region, main_region, true)

# Carves a widened corridor from `region` to `main_region`. permeable_all
# = false restricts the corridor to obstacle cells (water/RuinPart block
# the BFS); true lets it cross water and ruin too (converting water cells
# to walkable land and removing ruin along the path). Returns true if a
# corridor was carved, false if no path exists under the given permeability.
func _connect_pocket(region: Dictionary, main_region: Dictionary, permeable_all: bool) -> bool:
	var start: Vector2i = region.keys()[0]
	var parent = {start: start}
	var queue = [start]
	var head = 0
	var reached = Vector2i(-1, -1)
	while head < queue.size() and reached.x < 0:
		var curr = queue[head]
		head += 1
		for off in _CARDINAL_NEIGHBOR_OFFSETS:
			var n = curr + off
			if n.x < 0 or n.x >= width or n.y < 0 or n.y >= height or parent.has(n):
				continue
			if not permeable_all:
				if terrain[n.y][n.x] == BiomeType.WATER:
					continue
				if obstacles.get(n, "") == "RuinPart":
					continue
			parent[n] = curr
			if main_region.has(n):
				reached = n
				break
			queue.append(n)
	if reached.x < 0:
		return false

	# Walk the path back, clearing everything along it (1-cell widened so
	# the corridor is passable for a mech, not a single-tile slit). Ruin and
	# obstacles are erased; water is converted to land (biome of the nearest
	# land neighbor, else GRASSLAND) so it renders and paths as walkable.
	var walk = reached
	while true:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var c = Vector2i(walk.x + dx, walk.y + dy)
				if c.x < 0 or c.x >= width or c.y < 0 or c.y >= height:
					continue
				if obstacles.has(c):
					obstacles.erase(c)
				if permeable_all and terrain[c.y][c.x] == BiomeType.WATER:
					# Convert to a land bridge. The generation-time
					# water_tile_count (used only for the whole-map
					# water_fraction / is_mostly_water heuristic) is a local
					# in _generate_map and out of scope here; a handful of
					# carved cells out of 100k shifts that fraction by
					# <0.001, so it's left as-is rather than threaded through.
					terrain[c.y][c.x] = _nearest_land_biome(c)
		if walk == parent[walk]:
			break
		walk = parent[walk]
	return true

# Biome to stamp on a water cell being carved into a land bridge - copies
# an adjacent non-water tile so the bridge blends with the shoreline,
# falling back to GRASSLAND if the whole neighborhood is water.
func _nearest_land_biome(pos: Vector2i) -> int:
	for n in [Vector2i(pos.x + 1, pos.y), Vector2i(pos.x - 1, pos.y), Vector2i(pos.x, pos.y + 1), Vector2i(pos.x, pos.y - 1)]:
		if n.x < 0 or n.x >= width or n.y < 0 or n.y >= height:
			continue
		if terrain[n.y][n.x] != BiomeType.WATER:
			return terrain[n.y][n.x]
	return BiomeType.GRASSLAND

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
			var head = 0
			current_continent[pos] = true
			visited[pos] = true

			while head < queue.size():
				var curr = queue[head]
				head += 1

				for off in _CARDINAL_NEIGHBOR_OFFSETS:
					var n = curr + off
					if n.x >= 0 and n.x < width and n.y >= 0 and n.y < height:
						if not visited.has(n) and terrain[n.y][n.x] != BiomeType.WATER and not obstacles.has(n):
							visited[n] = true
							current_continent[n] = true
							queue.append(n)
							
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
# the user wanted ruins available everywhere, not just the tabletop preset.
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

# Cluster placement shared by the Tabletop and Open Field variety passes: centres kept clear of the spawn and
# of each other, never on water or on an existing obstacle.
const CLUSTER_SPAWN_CLEARANCE = 14.0
func _cluster_centres(count: int, min_gap: float) -> Array:
	var centre = Vector2(width / 2.0, height / 2.0)
	var out: Array = []
	var tries = 0
	while out.size() < count and tries < count * 60:
		tries += 1
		var p = Vector2(randf_range(6.0, width - 6.0), randf_range(6.0, height - 6.0))
		if p.distance_to(centre) < CLUSTER_SPAWN_CLEARANCE:
			continue
		var c = Vector2i(int(p.x), int(p.y))
		if terrain[c.y][c.x] == BiomeType.WATER or obstacles.has(c):
			continue
		var ok = true
		for q in out:
			if q.distance_to(p) < min_gap:
				ok = false
				break
		if ok:
			out.append(p)
	return out

func _free_cell(c: Vector2i) -> bool:
	return c.x >= 1 and c.y >= 1 and c.x < width - 1 and c.y < height - 1 \
		and terrain[c.y][c.x] != BiomeType.WATER and not obstacles.has(c)

# Open Field is otherwise bare: scatter small boulder clusters (hard cover to hold or snipe from) so a
# long-range build has something to play around. Density scales with map area.
func _open_field_cover() -> int:
	var scale = sqrt(float(width * height) / 2048.0)
	var placed = 0
	for p in _cluster_centres(clampi(int(7 * scale), 6, 30), 16.0):
		for _i in range(randi_range(2, 5)):
			var c = Vector2i(int(p.x) + randi_range(-2, 2), int(p.y) + randi_range(-2, 2))
			if _free_cell(c):
				obstacles[c] = "Boulder"
				placed += 1
	return placed

# Tabletop: the mat gets a few flocked "forest bases" like the scenery kits on a real table, a green disc
# with a handful of trees on it, in between the ruins.
func _tabletop_forest_bases() -> int:
	var scale = sqrt(float(width * height) / 2048.0)
	var trees = 0
	for p in _cluster_centres(clampi(int(4 * scale), 3, 16), 20.0):
		for y in range(int(p.y) - 4, int(p.y) + 5):
			for x in range(int(p.x) - 4, int(p.x) + 5):
				var c = Vector2i(x, y)
				if c.x < 0 or c.y < 0 or c.x >= width or c.y >= height or terrain[y][x] == BiomeType.WATER:
					continue
				if Vector2(x - p.x, y - p.y).length() <= 4.0:
					terrain[y][x] = BiomeType.GRASSLAND
		for _i in range(randi_range(4, 7)):
			var c = Vector2i(int(p.x) + randi_range(-3, 3), int(p.y) + randi_range(-3, 3))
			if _free_cell(c) and Vector2(c.x - p.x, c.y - p.y).length() <= 3.5:
				obstacles[c] = "Tree"
				trees += 1
	return trees

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

# Barns and farmhouses for FightShovel 1920 (Utility-SOC: "tractors, corn-
# fields... barns and farmhouses in the shovelfight terrain"). Deliberately
# near-identical to _place_tabletop_ruins() above (same overlap-rejection/
# spawn-clearance logic, same "RuinPart" obstacle tag so every other system
# that already treats RuinPart as solid - minimap, corridor-carving,
# connectivity checks - needs zero changes) - reuses ruin_specs/
# RuinObstacle wholesale rather than a parallel structure/class, just with
# a "type" tag so RuinObstacle._draw() paints a farm building instead of a
# grey ruin shell, and smaller farm-scale footprints instead of a ruined
# cathedral.
# FightShovel farmland variety: a few irrigation ponds (their rim becomes shallows) kept well away from
# the spawn, and dirt tracks joining the spawn and every farm building (roads, so they are quicker to
# cross). Ponds go in BEFORE the buildings so those avoid them; tracks go in after and must not erase
# the buildings they lead to.
const FARM_POND_SPAWN_CLEARANCE = 28.0
func _fightshovel_ponds() -> int:
	var scale = sqrt(float(width * height) / 2048.0)
	var count = clampi(int((2 + randi() % 3) * scale * 0.6), 2, 6)
	var centre = Vector2(width / 2.0, height / 2.0)
	var made = 0
	var placed = 0
	var tries = 0
	while placed < count and tries < count * 40:
		tries += 1
		var rx = randf_range(4.0, 7.0)
		var ry = randf_range(3.0, 5.0)
		var c = Vector2(randf_range(rx + 6.0, width - rx - 6.0), randf_range(ry + 6.0, height - ry - 6.0))
		if c.distance_to(centre) < FARM_POND_SPAWN_CLEARANCE:
			continue
		for y in range(int(c.y - ry) - 1, int(c.y + ry) + 2):
			for x in range(int(c.x - rx) - 1, int(c.x + rx) + 2):
				if x < 0 or y < 0 or x >= width or y >= height:
					continue
				var dx = (x - c.x) / rx
				var dy = (y - c.y) / ry
				if dx * dx + dy * dy <= 1.0 and terrain[y][x] != BiomeType.WATER:
					terrain[y][x] = BiomeType.WATER
					obstacles.erase(Vector2i(x, y))
					corn_field_cells.erase(Vector2i(x, y))
					made += 1
		placed += 1
	return made

func _fightshovel_tracks() -> int:
	if ruin_specs.is_empty():
		return 0
	var nodes: Array = [Vector2(width / 2.0, height / 2.0)]
	for spec in ruin_specs:
		nodes.append(Vector2(spec.x + spec.w / 2.0, spec.y + spec.h / 2.0))
	var kept: Dictionary = {}
	for k in obstacles:
		if obstacles[k] == "RuinPart":
			kept[k] = true
	var connected: Array = [0]
	var rest: Array = range(1, nodes.size())
	var roads = 0
	while not rest.is_empty():
		var best_i = 0
		var best_from = 0
		var best_d = 1.0e12
		for ri in range(rest.size()):
			for ci in connected:
				var d = nodes[rest[ri]].distance_to(nodes[ci])
				if d < best_d:
					best_d = d
					best_i = ri
					best_from = ci
		MapStructure._carve_road(self, nodes[best_from], nodes[rest[best_i]])
		connected.append(rest[best_i])
		rest.remove_at(best_i)
		roads += 1
	for k in kept:
		obstacles[k] = "RuinPart" # the tracks lead to the buildings, they do not demolish them
	return roads

func _place_fightshovel_structures():
	ruin_specs.clear()
	var density_scale = sqrt(float(width * height) / 2048.0)
	var target_count = min(40, int((3 + randi() % 3) * density_scale))
	var attempts = 0
	var max_attempts = max(150, target_count * 30)
	var center = Vector2(width / 2.0, height / 2.0)
	while ruin_specs.size() < target_count and attempts < max_attempts:
		attempts += 1
		var structure_type = "barn" if randf() < 0.5 else "farmhouse"
		var w: int
		var h: int
		if structure_type == "barn":
			w = 5 + randi() % 3 # 5-7 tiles wide
			h = 4 + randi() % 3 # 4-6 tiles deep
		else:
			w = 3 + randi() % 3 # 3-5 tiles wide
			h = 3 + randi() % 2 # 3-4 tiles deep
		var ox = 3 + randi() % max(1, width - w - 6)
		var oy = 3 + randi() % max(1, height - h - 6)

		var closest_x = clamp(center.x, ox, ox + w - 1)
		var closest_y = clamp(center.y, oy, oy + h - 1)
		if Vector2(closest_x, closest_y).distance_to(center) < RUIN_CENTER_CLEARANCE_TILES:
			continue

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
		ruin_specs.append({"x": ox, "y": oy, "w": w, "h": h, "type": structure_type})

# Edge treelines + sparse interior copses (redesigned 2026-08-05 per user
# report: the old tendril-band scatter below made obstacles "mostly a
# nuisance" - the zero-crossing band of a smooth noise field traces long
# winding lines that can run most of the map's width, and even the lower
# per-biome chances still filled a lot of ground. Two independent, much
# sparser rules now, checked in order (first match wins):
#   1. EDGE TREELINE - only within EDGE_MARGIN_TILES of a map border, and
#      only where a coarse noise sample says this STRETCH of border is
#      treed - a solid ring around the whole perimeter reads as a wall, not
#      terrain, so most of the edge stays open and only some runs get a
#      line of obstacles (per the user: "a forest around PARTS of the edge
#      of the map"). Nearby edge tiles share noise value with their
#      neighbors, so a qualifying stretch reads as one contiguous run
#      rather than flickering tile-to-tile.
#   2. INTERIOR COPSE - a much tighter, high-value noise threshold (an
#      upper-tail blob region, not a thin zero-crossing line) picks out
#      small, isolated interior clusters - "a copse here or there," not a
#      network of hedgerows spanning the map.
# Outside both, only a tiny lone-obstacle chance remains, roughly half the
# old rate, keeping maps from feeling completely bare between clusters.
# Per-biome density values below are themselves cut to roughly half-to-60%
# of the old tendril-band chances - a direct density cap, independent of
# the placement-shape change.
const EDGE_MARGIN_TILES = 6

func _biome_obstacle_density(biome: BiomeType) -> float:
	match biome:
		BiomeType.FOREST: return 0.32   # was 0.55 (in the old tendril band)
		BiomeType.DESERT: return 0.14   # was 0.25
		BiomeType.TUNDRA: return 0.16   # was 0.30
		BiomeType.VOLCANO: return 0.18  # was 0.35
		BiomeType.DUNGEON: return 0.28  # was 0.50
	return 0.08 # Grassland, was 0.15

func _should_spawn_obstacle(biome: BiomeType, roll: float, x: int = 0, y: int = 0) -> bool:
	if biome == BiomeType.WATER:
		return false
	if not obstacle_noise:
		return roll < 0.002

	# Normal mode keeps its own earlier ruling (per the user: "gaps between
	# obstacles need to be larger") - a flat extra cut on top of the general
	# cap below, same intent the old code's narrower tendril_band encoded.
	var density = _biome_obstacle_density(biome) * (0.6 if map_type == "Normal" else 1.0)

	var near_edge = x < EDGE_MARGIN_TILES or x >= width - EDGE_MARGIN_TILES or y < EDGE_MARGIN_TILES or y >= height - EDGE_MARGIN_TILES
	if near_edge:
		# Coarser sample than the interior copse check - bigger noise
		# "features" mean a qualifying edge run stays contiguous over many
		# tiles instead of breaking up tile-by-tile.
		var edge_sample = obstacle_noise.get_noise_2d(x * 0.4, y * 0.4)
		if edge_sample > 0.2:
			return roll < density

	var copse_sample = obstacle_noise.get_noise_2d(x, y)
	if copse_sample > 0.55:
		return roll < density

	return roll < 0.002 # rare lone tree/boulder, elsewhere

func _get_obstacle_name(biome: BiomeType) -> String:
	# FightShovel 1920 reuses the DESERT biome (see the map_type dispatch
	# above), but a dust-bowl farm scattering cacti would read as wrong -
	# fence-lines (mostly) and the occasional abandoned tractor instead.
	# Checked before the biome match since this is a map_type override, not
	# a biome one.
	if map_type == "FightShovel":
		return "Tractor" if randf() < 0.12 else "Fence"
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

# chunk coord -> baked ground Sprite2D (TerrainEditor repaints single chunks)
var _chunk_sprites: Dictionary = {}
# layer -> {row y -> [{x, n, body}]}: merged collision runs, so a single cell
# can be carved out of a run at runtime (TerrainEditor).
var _runs: Dictionary = {}

func _draw_map_to_texture():
	_chunk_sprites.clear()
	_runs.clear()
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

# Optional native accelerator (rust_ext GDExtension, see ../../rust_ext/) for
# the per-tile "fat pixel" painting loop below - by far the largest confirmed
# map-load cost (a 400x250 Normal map runs ~1.6 million Image.fill_rect calls
# across this, all synchronous in _ready() with zero frame-yielding). Same
# lazy-check/graceful-fallback pattern as MechPartRenderer.gd's
# _rasterizer/_rasterizer_checked - _paint_textured_tile/
# _get_textured_pixel_color/_get_biome_color are kept as the reference
# implementation and fallback (used verbatim if the extension DLL isn't
# built), not dead code.
var _terrain_rasterizer = null
var _terrain_rasterizer_checked: bool = false

# Draws one chunk's worth of terrain (+ obstacle squares + any outer-wall
# strip it touches) into its own small Image/Sprite2D. Purely visual - no
# collision is created here (see _build_collisions_and_obstacles).
# Paints one chunk of ground at full resolution (CPU image, no GPU resources).
func _render_chunk_image(cx: int, cy: int, wall_thickness: int, blue_color: Color) -> Image:
	var tile_x0 = cx * CHUNK_TILES
	var tile_y0 = cy * CHUNK_TILES
	var tile_x1 = min(tile_x0 + CHUNK_TILES, width)
	var tile_y1 = min(tile_y0 + CHUNK_TILES, height)
	var chunk_w_tiles = tile_x1 - tile_x0
	var chunk_h_tiles = tile_y1 - tile_y0
	if chunk_w_tiles <= 0 or chunk_h_tiles <= 0:
		return null

	if not _terrain_rasterizer_checked:
		_terrain_rasterizer_checked = true
		if ClassDB.class_exists("TerrainRasterizer"):
			_terrain_rasterizer = ClassDB.instantiate("TerrainRasterizer")

	var img: Image
	if _terrain_rasterizer:
		var biomes := PackedInt32Array()
		var obstacle_names := PackedStringArray()
		var corn_mask := PackedByteArray()
		biomes.resize(chunk_w_tiles * chunk_h_tiles)
		obstacle_names.resize(chunk_w_tiles * chunk_h_tiles)
		corn_mask.resize(chunk_w_tiles * chunk_h_tiles)
		for ty in range(tile_y0, tile_y1):
			for tx in range(tile_x0, tile_x1):
				var idx = (ty - tile_y0) * chunk_w_tiles + (tx - tile_x0)
				var pos = Vector2i(tx, ty)
				biomes[idx] = BiomeType.WATER if terrain[ty][tx] == BiomeType.SHALLOW else terrain[ty][tx] # the native rasterizer paints shallows as water; the overlay lightens them
				obstacle_names[idx] = obstacles.get(pos, "")
				corn_mask[idx] = 1 if corn_field_cells.has(pos) else 0
		var bytes = _terrain_rasterizer.rasterize_chunk(biomes, obstacle_names, corn_mask, chunk_w_tiles, chunk_h_tiles, tile_size, map_type, randi())
		img = Image.create_from_data(chunk_w_tiles * tile_size, chunk_h_tiles * tile_size, false, Image.FORMAT_RGBA8, bytes)
	else:
		img = Image.create(chunk_w_tiles * tile_size, chunk_h_tiles * tile_size, false, Image.FORMAT_RGBA8)

		for ty in range(tile_y0, tile_y1):
			for tx in range(tile_x0, tile_x1):
				var biome = terrain[ty][tx]
				var local_x = (tx - tile_x0) * tile_size
				var local_y = (ty - tile_y0) * tile_size
				var pos = Vector2i(tx, ty)
				_paint_textured_tile(img, local_x, local_y, biome, pos)

				# Trees, RuinParts, and the DestructibleObstacle-backed flat
				# types (Boulder/Cactus/IceBoulder/LavaRock/StoneWall) have
				# real scene nodes drawing them now - only the remaining
				# genuinely flat/indestructible types (Tractor, Fence) get a
				# painted square baked into the static terrain texture.
				if obstacles.get(pos, "") == "Wall":
					_paint_wall_tile(img, local_x, local_y, biome, ty)
				elif obstacles.has(pos) and obstacles[pos] != "Tree" and obstacles[pos] != "RuinPart" and not DestructibleObstacleScript.OBSTACLE_STATS.has(obstacles[pos]):
					var obs_rect = Rect2i(local_x + 8, local_y + 8, tile_size - 16, tile_size - 16)
					var obs_color = Color(0.2, 0.2, 0.2)
					if obstacles[pos] == "Tractor":
						obs_color = Color(0.55, 0.28, 0.12) # rusted orange-red
						img.fill_rect(obs_rect, obs_color)
						# Two darker "wheel" accents at the front/back corners.
						img.fill_rect(Rect2i(local_x + 6, local_y + tile_size - 12, 8, 8), Color(0.15, 0.13, 0.12))
						img.fill_rect(Rect2i(local_x + tile_size - 14, local_y + tile_size - 12, 8, 8), Color(0.15, 0.13, 0.12))
					else:
						img.fill_rect(obs_rect, obs_color)

	# Paint whichever outer-wall strip(s) this chunk touches
	if tile_y0 == 0:
		img.fill_rect(Rect2i(0, 0, img.get_width(), wall_thickness), blue_color)
	if tile_y1 == height:
		img.fill_rect(Rect2i(0, img.get_height() - wall_thickness, img.get_width(), wall_thickness), blue_color)
	if tile_x0 == 0:
		img.fill_rect(Rect2i(0, 0, wall_thickness, img.get_height()), blue_color)
	if tile_x1 == width:
		img.fill_rect(Rect2i(img.get_width() - wall_thickness, 0, wall_thickness, img.get_height()), blue_color)

	return img

static func downscale_chunk(img: Image, factor: int = TEXTURE_DOWNSCALE) -> Image:
	var out = Image.new()
	out.copy_from(img)
	out.resize(maxi(1, img.get_width() / factor), maxi(1, img.get_height() / factor), Image.INTERPOLATE_NEAREST)
	return out

# The ground is painted in 8-px 'fat pixels', so uploading it at full resolution wastes GPU memory: the
# 400x250-tile map was ~410 MB of texture (about the whole budget of an Intel HD 4000, whose two Vulkan
# device losses came right after long runs). Chunks are uploaded at 1/TEXTURE_DOWNSCALE size and drawn
# scaled back up with nearest filtering, which reproduces the same hard-edged blocks for ~1/16 the memory.
const TEXTURE_DOWNSCALE = 4
const GROUND_Z = -100
# Dungeon masonry has 1-2 px mortar lines, finer than the 8 px blocks everything else is painted in (measured: even x2 loses 4% of pixels), so Dungeon stays full size.
func texture_downscale() -> int:
	return DUNGEON_TEXTURE_DOWNSCALE if map_type == "Dungeon" else TEXTURE_DOWNSCALE
const DUNGEON_TEXTURE_DOWNSCALE = 1
func _build_terrain_chunk(cx: int, cy: int, wall_thickness: int, blue_color: Color):
	var tile_x0 = cx * CHUNK_TILES
	var tile_y0 = cy * CHUNK_TILES
	var img = _render_chunk_image(cx, cy, wall_thickness, blue_color)
	if img == null:
		return
	var factor = texture_downscale()
	if factor > 1:
		img = downscale_chunk(img, factor)
	var tex = ImageTexture.create_from_image(img)
	var sprite = Sprite2D.new()
	sprite.texture = tex
	sprite.centered = false
	# The baked ground must be the lowest thing on the canvas: decals (-10), oil slicks and vents (-3),
	# objective rings (-2) and the shallow tint (-9) all use negative z and were hidden under a z=0 ground.
	sprite.z_index = GROUND_Z
	sprite.scale = Vector2(factor, factor)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = Vector2(tile_x0 * tile_size, tile_y0 * tile_size)
	var ckey = Vector2i(cx, cy)
	if _chunk_sprites.has(ckey) and is_instance_valid(_chunk_sprites[ckey]):
		var old_sprite = _chunk_sprites[ckey]
		var old_idx = old_sprite.get_index()
		old_sprite.queue_free()
		add_child(sprite)
		move_child(sprite, old_idx)
	else:
		add_child(sprite)
	_chunk_sprites[ckey] = sprite

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
				if obs_name == "Tree" or obs_name == "RuinPart" or DestructibleObstacleScript.OBSTACLE_STATS.has(obs_name):
					# Node-based obstacles bring their own collision
					# (TreeObstacle / RuinObstacle / DestructibleObstacle) -
					# exclude them from the merged flat-collision run.
					if obstacle_start_x != -1:
						_create_merged_collision(obstacle_start_x, y, x - obstacle_start_x, 32)
						obstacle_start_x = -1
					if obs_name == "Tree":
						_spawn_tree(Vector2(x * tile_size, y * tile_size))
					elif DestructibleObstacleScript.OBSTACLE_STATS.has(obs_name):
						_spawn_destructible_obstacle(Vector2(x * tile_size, y * tile_size), obs_name)
				else:
					if obstacle_start_x == -1:
						obstacle_start_x = x
			else:
				if obstacle_start_x != -1:
					_create_merged_collision(obstacle_start_x, y, x - obstacle_start_x, 32)
					obstacle_start_x = -1

		if water_start_x != -1:
			_create_merged_collision(water_start_x, y, width - water_start_x, 2)
		if dungeon_start_x != -1:
			_create_merged_collision(dungeon_start_x, y, width - dungeon_start_x, 1)
		if obstacle_start_x != -1:
			_create_merged_collision(obstacle_start_x, y, width - obstacle_start_x, 32)

	# One destructible terrain-kit node per placed ruin/farm building
	# (Tabletop ruins, FightShovel barns/farmhouses, or any other map type
	# with force_ruins on - ruin_specs is simply empty otherwise, so this
	# loop is a no-op on maps without either). structure_type defaults to
	# "ruin" for pre-existing specs that never set a "type" key.
	for spec in ruin_specs:
		var ruin = load("res://scripts/core/RuinObstacle.gd").new()
		ruin.size_tiles = Vector2i(spec.w, spec.h)
		ruin.origin_tile = Vector2i(spec.x, spec.y)
		ruin.footprint = Vector2(spec.w * tile_size, spec.h * tile_size)
		ruin.map_ref = self
		ruin.structure_type = spec.get("type", "ruin")
		ruin.global_position = Vector2(spec.x * tile_size, spec.y * tile_size) + ruin.footprint / 2.0
		add_child(ruin)

	_ensure_corn_trail_overlay()
	_scatter_oil_slicks()
	_scatter_lava_vents()
	_spawn_zone_objectives()
	_build_shallow_overlay()
	_build_biome_props()

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

# Volcano biome identity: eruption vents (see LavaVent.gd). Placed per tile like the oil slicks but
# rarer, capped per map, and never within VENT_SPAWN_CLEAR tiles of the player spawn.
const LAVA_VENT_CHANCE = 0.004
const LAVA_VENT_MAX = 24
const VENT_SPAWN_CLEAR = 10
func _scatter_lava_vents() -> int:
	if map_type in ["Arena", "Open Field", "Tabletop", "Dungeon"]:
		return 0
	var placed = 0
	var centre = Vector2i(width / 2, height / 2)
	for y in range(height):
		for x in range(width):
			if placed >= LAVA_VENT_MAX:
				return placed
			if terrain[y][x] != BiomeType.VOLCANO:
				continue
			var pos = Vector2i(x, y)
			if obstacles.has(pos) or absi(x - centre.x) + absi(y - centre.y) < VENT_SPAWN_CLEAR:
				continue
			if randf() < LAVA_VENT_CHANCE:
				var vent = load("res://scripts/hazards/LavaVent.gd").new()
				vent.global_position = Vector2(x * tile_size + tile_size / 2.0, y * tile_size + tile_size / 2.0)
				vent.radius = tile_size * (1.1 + randf() * 0.5)
				add_child(vent)
				placed += 1
	return placed

# Shallows: the one-tile band of water along every shoreline becomes walkable, slower ground
# (BiomeType.SHALLOW) instead of a hard wall. Everything keyed on WATER (collision, nav solids,
# drowning) therefore treats it as land with no further changes; TerrainEffects supplies the slowdown.
# Decided against a snapshot so the band stays exactly one tile thick.
func _mark_shallows() -> int:
	var edge: Array = []
	for y in range(height):
		for x in range(width):
			if terrain[y][x] != BiomeType.WATER:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx = x + d.x
				var ny = y + d.y
				if nx >= 0 and ny >= 0 and nx < width and ny < height and terrain[ny][nx] != BiomeType.WATER:
					edge.append(Vector2i(x, y))
					break
	for c in edge:
		terrain[c.y][c.x] = BiomeType.SHALLOW
	return edge.size()

# Pale quads over every shallow tile so the walkable band reads as lighter water over the baked texture.
# A plain canvas item drawing same-colour rects (the canvas batcher merges them); it was a MultiMesh until a
# player's Ivy Bridge GPU lost its Vulkan device after a long session, so it stays on the well-trodden path.
const ShallowOverlayScript = preload("res://scripts/visuals/ShallowOverlay.gd")
const FxTierScript = preload("res://scripts/core/FxTier.gd")
func _build_shallow_overlay() -> int:
	if FxTierScript.safe():
		return 0
	var cells: Array = []
	for y in range(height):
		for x in range(width):
			if terrain[y][x] == BiomeType.SHALLOW:
				cells.append(Vector2i(x, y))
	if cells.is_empty():
		return 0
	var overlay = ShallowOverlayScript.new()
	overlay.name = "ShallowOverlay"
	overlay.setup(cells, tile_size)
	add_child(overlay)
	return cells.size()

# Ambient props (tufts, bones, shards, ash...) for the biome identity pass; see BiomeProps.gd.
const BiomePropsScript = preload("res://scripts/visuals/BiomeProps.gd")
func _build_biome_props() -> int:
	var props = BiomePropsScript.new()
	props.name = "BiomeProps"
	add_child(props)
	return props.build(self, map_seed)

# Forts get a hold point, villages a loot cache (see ZoneObjective.gd).
func _spawn_zone_objectives() -> int:
	var made = 0
	for z in zones:
		if z.kind != "fort" and z.kind != "village":
			continue
		var obj = load("res://scripts/hazards/ZoneObjective.gd").new()
		obj.kind = "hold" if z.kind == "fort" else "cache"
		obj.radius = tile_size * 5.0
		obj.global_position = Vector2(z.pos.x * tile_size, z.pos.y * tile_size)
		add_child(obj)
		made += 1
	return made

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

var _tree_layer: TreeRenderLayer

func register_tree_visual(pos: Vector2) -> void:
	if _tree_layer == null or not is_instance_valid(_tree_layer) or _tree_layer.is_queued_for_deletion():
		_tree_layer = TreeRenderLayer.new()
		add_child(_tree_layer)
	_tree_layer.add_tree(pos)

func unregister_tree_visual(pos: Vector2) -> void:
	if _tree_layer != null and is_instance_valid(_tree_layer):
		_tree_layer.remove_tree(pos)

func _spawn_tree(pos: Vector2):
	var body = load("res://scripts/core/TreeObstacle.gd").new()
	body.global_position = pos + Vector2(tile_size/2, tile_size/2)
	# So the tree can clear its nav footprint when destroyed (same pattern
	# as RuinObstacle) - without this, dead trees left invisible AI walls.
	body.map_ref = self
	body.cell = Vector2i(int(pos.x / tile_size), int(pos.y / tile_size))
	add_child(body)

func _spawn_destructible_obstacle(pos: Vector2, obs_name: String):
	var body = load("res://scripts/core/DestructibleObstacle.gd").new()
	body.obstacle_name = obs_name
	body.global_position = pos + Vector2(tile_size/2, tile_size/2)
	body.map_ref = self
	body.cell = Vector2i(int(pos.x / tile_size), int(pos.y / tile_size))
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
	if not _runs.has(layer):
		_runs[layer] = {}
	if not _runs[layer].has(y):
		_runs[layer][y] = []
	_runs[layer][y].append({"x": start_x, "n": length, "body": body})

func _get_biome_color(biome: BiomeType) -> Color:
	# Tabletop's ground reads as a painted + flocked wargaming mat (rust
	# red, like the reference table) rather than raw desert sand. Handled
	# here so the minimap bake picks up the mat color for free.
	if map_type == "Tabletop" and biome == BiomeType.DESERT:
		return Color(0.52, 0.24, 0.16)
	# FightShovel 1920: parched, sun-bleached dust-bowl earth - drier and
	# greyer than raw desert sand (0.9, 0.8, 0.5), distinct from Tabletop's
	# rust-red painted mat.
	if map_type == "FightShovel" and biome == BiomeType.DESERT:
		return Color(0.62, 0.53, 0.36)
	match biome:
		BiomeType.GRASSLAND: return Color(0.4, 0.8, 0.4)
		BiomeType.WATER: return Color(0.2, 0.4, 0.9)
		BiomeType.DESERT: return Color(0.9, 0.8, 0.5)
		BiomeType.FOREST: return Color(0.1, 0.5, 0.2)
		BiomeType.TUNDRA: return Color(0.8, 0.9, 0.9)
		BiomeType.VOLCANO: return Color(0.3, 0.1, 0.1)
		BiomeType.DUNGEON: return Color(0.15, 0.1, 0.2)
		BiomeType.ROAD: return Color(0.58, 0.47, 0.33)
		BiomeType.FLOOR: return Color(0.4, 0.37, 0.38)
		BiomeType.SHALLOW: return Color(0.45, 0.7, 0.9)
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
func _paint_textured_tile(img: Image, local_x: int, local_y: int, biome: BiomeType, pos: Vector2i = Vector2i.ZERO):
	var is_corn = map_type == "FightShovel" and corn_field_cells.has(pos)
	var base = CORN_COLOR if is_corn else _get_biome_color(biome)
	var blocks_per_side = max(1, tile_size / GROUND_PIXEL_SIZE)

	for by in range(blocks_per_side):
		for bx in range(blocks_per_side):
			var color: Color
			if is_corn:
				# Alternating vertical stalk rows read as a planted field
				# instead of a flat color patch; the odd bright block is a
				# ripe/dry stalk catching the light.
				color = base.lightened(0.15) if bx % 2 == 0 else base.darkened(0.12)
				if randf() < 0.08:
					color = Color(0.85, 0.72, 0.25)
			else:
				color = _get_textured_pixel_color(base, biome)
			img.fill_rect(Rect2i(local_x + bx * GROUND_PIXEL_SIZE, local_y + by * GROUND_PIXEL_SIZE, GROUND_PIXEL_SIZE, GROUND_PIXEL_SIZE), color)
	if biome == BiomeType.FLOOR: # flagstone mortar
		var mortar = base.darkened(0.3)
		img.fill_rect(Rect2i(local_x, local_y, tile_size, 2), mortar)
		img.fill_rect(Rect2i(local_x, local_y, 2, tile_size), mortar)

# Full-tile masonry for the "Wall" obstacle, tinted by the ground it stands on
# (mirrors terrain_rasterizer.rs's wall_color/painting).
func _paint_wall_tile(img: Image, local_x: int, local_y: int, biome: int, ty: int) -> void:
	var wc = Color(0.5, 0.48, 0.46)
	match biome:
		BiomeType.DESERT: wc = Color(0.72, 0.6, 0.4)
		BiomeType.TUNDRA: wc = Color(0.68, 0.76, 0.84)
		BiomeType.VOLCANO: wc = Color(0.2, 0.16, 0.18)
		BiomeType.DUNGEON: wc = Color(0.3, 0.28, 0.38)
	var t = tile_size
	img.fill_rect(Rect2i(local_x, local_y, t, t), wc)
	img.fill_rect(Rect2i(local_x, local_y, t, 4), wc.lightened(0.18))
	img.fill_rect(Rect2i(local_x, local_y + t - 4, t, 4), wc.darkened(0.3))
	var mortar = wc.darkened(0.4)
	img.fill_rect(Rect2i(local_x, local_y + t / 2 - 1, t, 2), mortar)
	var seam = t / 2 if ty % 2 == 0 else t / 4
	img.fill_rect(Rect2i(local_x + seam, local_y, 2, t / 2), mortar)
	img.fill_rect(Rect2i(local_x + seam + t / 2, local_y + t / 2, 2, t / 2), mortar)

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
	# FightShovel 1920: cracked, wind-scoured dust-bowl earth - darker
	# cracked-soil veins, pale sun-bleached patches, and a fine dust haze
	# rather than Tabletop's flock texture.
	if map_type == "FightShovel":
		var dust_roll = randf()
		if dust_roll < 0.10: return base.darkened(0.25 + randf() * 0.2) # cracked soil vein
		elif dust_roll < 0.24: return base.lightened(0.14 + randf() * 0.12) # sun-bleached patch
		elif dust_roll < 0.30: return Color(0.7, 0.63, 0.5).lerp(base, 0.35) # drifted dust
		return base.darkened(randf() * 0.05)
	match biome:
		BiomeType.ROAD:
			var rroll = randf()
			if rroll < 0.18: return base.darkened(0.1 + randf() * 0.12)
			elif rroll < 0.28: return base.lightened(0.1)
			return base.darkened(randf() * 0.04)
		BiomeType.FLOOR:
			if randf() < 0.2: return base.darkened(0.08 + randf() * 0.1)
			return base.lightened(randf() * 0.04)
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
	var raw_x = int(target_pos.x / tile_size)
	var raw_y = int(target_pos.y / tile_size)
	# Clamp the SEARCH ORIGIN into real tile bounds first - target_pos can
	# legitimately arrive far outside the map (a random offset from a
	# player standing near an edge - see Main._spawn_extraction_marker,
	# the actual source of the "enemies/extraction off map" playtest
	# report: the marker landed outside the map and the player followed
	# the "Follow indicator" prompt off it, with chasing enemies in tow).
	# Searching from an out-of-bounds origin made every dx/dy in the spiral
	# below clamp to the SAME single boundary column/row - effectively
	# searching nothing. Clamping the origin here means the spiral always
	# explores a real neighborhood near the map edge instead.
	var start_x = clamp(raw_x, 0, width - 1)
	var start_y = clamp(raw_y, 0, height - 1)
	var start_v = Vector2i(start_x, start_y)

	# Only return target_pos verbatim when it was ALREADY in-bounds and
	# clear - preserves the exact requested position for the normal case.
	# An out-of-bounds target_pos always falls through to the spiral search.
	if raw_x == start_x and raw_y == start_y and _has_spawn_clearance(start_v):
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

	# Last-resort fallback: clamp into real map bounds rather than ever
	# handing back an unclamped (possibly off-map) target_pos - a caller
	# that forgets to pre-clamp its own input (as the extraction marker
	# did) must never be able to place something off the map even here.
	var fallback_inset = tile_size * 2.0
	return Vector2(
		clamp(target_pos.x, fallback_inset, width * tile_size - fallback_inset),
		clamp(target_pos.y, fallback_inset, height * tile_size - fallback_inset)
	)

# A tile being obstacle-free isn't enough on its own - mech collision boxes
# (40px) are bigger than a single tile (32px), so a mech centered on a
# "clear" tile immediately next to water/an obstacle can still physically
# overlap it. Require the full 3x3 neighborhood to be clear too. This is
# what get_valid_spawn_position uses for BOTH the player's spawn and every
# enemy squad's spawn, so it fixes overlap for both directions at once.
# Cheap walkability probes for squad tactics (flank/stage goals): terrain +
# obstacle lookups only, no physics queries. Amphibious movers ignore water.
func is_world_walkable(world_pos: Vector2, amphibious: bool = false) -> bool:
	var x = int(floor(world_pos.x / tile_size))
	var y = int(floor(world_pos.y / tile_size))
	if x < 0 or y < 0 or x >= width or y >= height:
		return false
	if obstacles.has(Vector2i(x, y)):
		return false
	return amphibious or terrain[y][x] != BiomeType.WATER

func segment_walkable(a: Vector2, b: Vector2, amphibious: bool = false) -> bool:
	var d = a.distance_to(b)
	var steps = int(ceil(d / (tile_size * 0.75)))
	for i in range(1, steps + 1):
		if not is_world_walkable(a.lerp(b, float(i) / steps), amphibious):
			return false
	return true

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

