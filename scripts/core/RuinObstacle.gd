class_name RuinObstacle
extends StaticBody2D

# Pixelated tabletop terrain kit: a ruined gothic-ish building shell, the
# kind of grey plastic scenery every game shop table is covered in. Drawn
# procedurally in chunky 4px cells (deterministic per instance), sized to
# a multi-tile footprint, and DESTRUCTIBLE - the first shipped slice of
# the group-6 "systematically blast the terrain apart" feature.

const PIX = 4.0 # fat-pixel cell size, matches the mech bake scale family

var footprint: Vector2 = Vector2(64, 64)
var origin_tile: Vector2i = Vector2i.ZERO
var size_tiles: Vector2i = Vector2i(2, 2)
var map_ref: Node = null
var hp: float = 0.0
var max_hp: float = 0.0
var _visual_seed: int = 0
# "ruin" (default, Tabletop's grey gothic shell) | "barn" | "farmhouse" -
# FightShovel 1920's farm buildings (Utility-SOC), same destructible multi-
# tile machinery, just a different _draw() paint job. Set by MapGenerator
# from ruin_specs' "type" key before add_child, same convention as
# size_tiles/origin_tile/footprint below.
var structure_type: String = "ruin"

func _ready():
	collision_layer = 32 # terrain-obstacle layer: blocks movement/shots, but jets fly over (see Mech.OBSTACLE_LAYER)
	collision_mask = 0
	# 150/tile (was 60) - Natalia wanted ruins to read as genuinely tough
	# terrain, not something that melts in a couple of hits like a Tree
	# (30 HP flat). A small 2x2 kit now sits at 600 HP, a big 5x3 at 2250.
	max_hp = 150.0 * size_tiles.x * size_tiles.y
	hp = max_hp
	_visual_seed = randi()
	z_index = 5

	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = footprint * 0.9
	shape.shape = rect
	add_child(shape)

func _draw():
	match structure_type:
		"barn":
			_draw_barn()
		"farmhouse":
			_draw_farmhouse()
		_:
			_draw_ruin()

func _draw_ruin():
	var rng = RandomNumberGenerator.new()
	rng.seed = _visual_seed
	var half = footprint / 2.0
	var cols = int(footprint.x / PIX)
	var rows = int(footprint.y / PIX)

	var wall = Color(0.58, 0.58, 0.63)       # unpainted grey plastic
	var wall_dark = Color(0.42, 0.42, 0.48)
	var slot = Color(0.24, 0.24, 0.30)       # window/arch shadows

	# Rubble skirt along the base
	for c in range(cols):
		if rng.randf() < 0.7:
			var rubble_h = PIX * (1 + rng.randi() % 2)
			draw_rect(Rect2(Vector2(c * PIX, footprint.y - rubble_h) - half, Vector2(PIX, rubble_h)), wall_dark.darkened(rng.randf() * 0.2))

	# Broken walls: tall shell around the edges, shattered stubs inside,
	# jagged random column heights, occasional blown-out gaps.
	for c in range(cols):
		var is_edge = c < 2 or c >= cols - 2
		var height_frac = rng.randf_range(0.6, 1.0) if is_edge else rng.randf_range(0.15, 0.55)
		if rng.randf() < 0.12:
			height_frac *= 0.3 # artillery took this bit
		var col_rows = max(1, int(rows * height_frac))
		for r in range(col_rows):
			var y = footprint.y - (r + 1) * PIX
			var shade = wall if (c % 4 < 2) else wall_dark
			if r == col_rows - 1:
				shade = shade.lightened(0.14) # broken-top highlight
			# Window/arch slots on interior wall faces
			if not is_edge and r % 3 == 1 and c % 3 == 1 and r < col_rows - 1:
				shade = slot
			draw_rect(Rect2(Vector2(c * PIX, y) - half, Vector2(PIX, PIX)), shade)

# FightShovel 1920 farm buildings (Utility-SOC) - same PIX-chunk procedural
# style as _draw_ruin, different paint job. Red gambrel-roofed barn with a
# big central door.
func _draw_barn():
	var rng = RandomNumberGenerator.new()
	rng.seed = _visual_seed
	var half = footprint / 2.0
	var cols = int(footprint.x / PIX)
	var rows = int(footprint.y / PIX)

	var wall = Color(0.62, 0.16, 0.14)
	var wall_dark = Color(0.48, 0.11, 0.10)
	var trim = Color(0.92, 0.9, 0.85)
	var roof = Color(0.28, 0.24, 0.22)

	var roof_rows = max(1, int(rows * 0.32))
	for c in range(cols):
		for r in range(rows):
			var y = r * PIX
			var shade: Color
			if r < roof_rows:
				shade = roof.lightened(0.1) if abs(c - cols / 2) <= 1 else roof.darkened(rng.randf() * 0.08)
			elif r == roof_rows:
				shade = trim # eave trim line
			else:
				shade = wall if (c % 5 < 4) else wall_dark # vertical plank seams
				if r > rows * 0.55 and abs(c - cols / 2) <= max(1, cols / 6):
					shade = wall_dark.darkened(0.3) # big central door
			draw_rect(Rect2(Vector2(c * PIX, y) - half, Vector2(PIX, PIX)), shade)

# Weathered white farmhouse with a grey peaked roof and scattered windows.
func _draw_farmhouse():
	var rng = RandomNumberGenerator.new()
	rng.seed = _visual_seed
	var half = footprint / 2.0
	var cols = int(footprint.x / PIX)
	var rows = int(footprint.y / PIX)

	var wall = Color(0.85, 0.8, 0.68)
	var wall_dark = Color(0.72, 0.68, 0.58)
	var roof = Color(0.3, 0.28, 0.3)
	var window = Color(0.35, 0.45, 0.55)

	var roof_peak_rows = max(2, int(rows * 0.4))
	for c in range(cols):
		var dist_from_center = abs(c - cols / 2.0)
		var roof_here = int(roof_peak_rows * (1.0 - dist_from_center / (cols / 2.0 + 0.001)))
		for r in range(rows):
			var y = r * PIX
			var shade: Color
			if r < roof_here:
				shade = roof.lightened(0.08) if r == 0 else roof.darkened(rng.randf() * 0.06)
			else:
				shade = wall if (c + r) % 3 != 0 else wall_dark
				if r > roof_peak_rows and r < rows - 2 and c % 4 == 2:
					shade = window
			draw_rect(Rect2(Vector2(c * PIX, y) - half, Vector2(PIX, PIX)), shade)

func apply_damage(amount: float, element: String = "RAW", source: Node = null, was_reflected: bool = false, source_label_override: String = ""):
	hp -= amount
	# Visible damage state: dust and grime as the kit takes hits
	modulate = Color(1, 1, 1).lerp(Color(0.75, 0.7, 0.68), 1.0 - clamp(hp / max_hp, 0.0, 1.0))
	if hp > 0:
		return

	# Collapse: free the footprint markers so the minimap, spawn anchors,
	# and future placement forget the building. Also clears the matching
	# astar_grid solid points and forces a flow-field rebuild next tick -
	# without this the shared flow field (MapGenerator._rebuild_flow_field)
	# kept permanently routing mechs around the now-walkable rubble.
	if map_ref and "obstacles" in map_ref:
		for y in range(size_tiles.y):
			for x in range(size_tiles.x):
				var cell = Vector2i(origin_tile.x + x, origin_tile.y + y)
				map_ref.obstacles.erase(cell)
				if "astar_grid" in map_ref and map_ref.astar_grid:
					map_ref.astar_grid.set_point_solid(cell, false)
		if map_ref.has_method("_rebuild_flow_field") and "_flow_field_target_cell" in map_ref:
			map_ref._flow_field_timer = 0.0

	var debris = CPUParticles2D.new()
	debris.one_shot = true
	debris.emitting = true
	debris.amount = 30
	debris.lifetime = 0.7
	debris.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	debris.emission_rect_extents = footprint / 2.0
	debris.gravity = Vector2(0, 80)
	debris.initial_velocity_min = 20.0
	debris.initial_velocity_max = 60.0
	debris.scale_amount_min = 3.0
	debris.scale_amount_max = 5.0
	debris.color = Color(0.5, 0.5, 0.55)
	debris.global_position = global_position
	if get_parent():
		get_parent().add_child(debris)
		debris.finished.connect(debris.queue_free)
	queue_free()
