class_name TreeObstacle
extends StaticBody2D

var hp: float = 30.0
# Set by MapGenerator._spawn_tree so destruction clears the nav footprint
# (same pattern as RuinObstacle). Null-safe: debug-spawned trees without a
# map still work, they just never blocked nav in the first place.
var map_ref: Node = null
var cell: Vector2i = Vector2i(-1, -1)

# Projectile hit-broadphase (see scripts/core/ProjectileBroadphase.gd) - a
# bounding-circle radius so this obstacle can be pushed into the Rust
# spatial query as a target, same as every PartHitbox.
var broadphase_radius: float = 0.0

func _ready():
	collision_layer = 32 # terrain-obstacle layer (jets fly over it - see Mech.OBSTACLE_LAYER)
	collision_mask = 0
	add_to_group("obstacle")

	# Accessibility (user report, 2026-08-03: obstacles were "NOT accessible"
	# - too close in color to their own terrain, confirmed against a real
	# playtest recording showing this exact dark-green-on-grassland-green
	# case). A dark outline reads against every biome's own palette
	# (grassland/forest are both green-hued, desert/tundra are light,
	# volcano/dungeon are dark) without needing per-biome color-matching
	# logic - same fix applied to every DestructibleObstacle type below.
	var poly = Polygon2D.new()
	poly.color = Color(0.05, 0.3, 0.05) # Dark green
	var tree_shape = PackedVector2Array([
		Vector2(0, -12), Vector2(8, 8), Vector2(-8, 8)
	])
	poly.polygon = tree_shape
	add_child(poly)

	# Light outline, not dark - the tree fill itself is already dark
	# (luminance ~0.2), so a dark border would have little contrast against
	# its OWN fill at the boundary (same luminance-contrast logic as
	# DestructibleObstacle.gd's per-type outline color below).
	var outline = Line2D.new()
	outline.points = tree_shape + PackedVector2Array([tree_shape[0]])
	outline.width = 2.0
	outline.default_color = Color(0.9, 0.95, 0.85, 0.9)
	outline.joint_mode = Line2D.LINE_JOINT_ROUND
	add_child(outline)

	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(16, 16)
	shape.shape = rect
	add_child(shape)
	broadphase_radius = rect.size.length() / 2.0

func apply_damage(amount: float, element: String = "RAW", source: Node = null, was_reflected: bool = false, source_label_override: String = ""):
	# Demolition-as-buildcraft (fourth-review ruling): obstacles have
	# element weaknesses. FIRE torches trees for double damage.
	if element == "FIRE":
		amount *= 2.0
	hp -= amount
	if hp <= 0:
		_collapse()

func _collapse():
	# Clear the nav footprint too - previously a destroyed tree kept its
	# obstacles-dict entry and solid astar cell, leaving an invisible wall
	# the AI pathed around (and the flow field routed around) forever.
	if map_ref and is_instance_valid(map_ref) and cell.x >= 0:
		map_ref.obstacles.erase(cell)
		if "astar_grid" in map_ref and map_ref.astar_grid:
			map_ref.astar_grid.set_point_solid(cell, false)
		if "_flow_field_timer" in map_ref:
			map_ref._flow_field_timer = 0.0 # rebuild promptly with the new gap
	queue_free()
