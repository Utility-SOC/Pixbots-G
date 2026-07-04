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

func _ready():
	collision_layer = 1 # blocks movement, projectiles, and line of fire
	collision_mask = 0
	max_hp = 60.0 * size_tiles.x * size_tiles.y
	hp = max_hp
	_visual_seed = randi()
	z_index = 5

	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = footprint * 0.9
	shape.shape = rect
	add_child(shape)

func _draw():
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

func apply_damage(amount: float, element: String = "RAW"):
	hp -= amount
	# Visible damage state: dust and grime as the kit takes hits
	modulate = Color(1, 1, 1).lerp(Color(0.75, 0.7, 0.68), 1.0 - clamp(hp / max_hp, 0.0, 1.0))
	if hp > 0:
		return

	# Collapse: free the footprint markers so the minimap, spawn anchors,
	# and future placement forget the building. (Known limitation: the
	# nav grid keeps the stale blocker until the map regenerates - AI
	# paths around the crater. Formalized nav updates come with group 6.)
	if map_ref and "obstacles" in map_ref:
		for y in range(size_tiles.y):
			for x in range(size_tiles.x):
				map_ref.obstacles.erase(Vector2i(origin_tile.x + x, origin_tile.y + y))

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
