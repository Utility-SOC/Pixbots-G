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
static var _shared_shape: RectangleShape2D

func _ready():
	collision_layer = 32 # terrain-obstacle layer (jets fly over it - see Mech.OBSTACLE_LAYER)
	collision_mask = 0
	add_to_group("obstacle")

	# No child nodes: one shared collision shape attached directly, visuals
	# drawn by the map's TreeRenderLayer (thousands of trees per map).
	if _shared_shape == null:
		_shared_shape = RectangleShape2D.new()
		_shared_shape.size = Vector2(16, 16)
	shape_owner_add_shape(create_shape_owner(self), _shared_shape)
	broadphase_radius = _shared_shape.size.length() / 2.0
	if map_ref and is_instance_valid(map_ref) and map_ref.has_method("register_tree_visual"):
		map_ref.register_tree_visual(position)

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
	if map_ref and is_instance_valid(map_ref) and map_ref.has_method("unregister_tree_visual"):
		map_ref.unregister_tree_visual(position)
	queue_free()
