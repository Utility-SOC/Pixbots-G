class_name TreeObstacle
extends StaticBody2D

const ScorchDecals = preload("res://scripts/visuals/ScorchDecals.gd")

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
	set_process(false) # only burning trees tick

	# No child nodes: one shared collision shape attached directly, visuals
	# drawn by the map's TreeRenderLayer (thousands of trees per map).
	if _shared_shape == null:
		_shared_shape = RectangleShape2D.new()
		_shared_shape.size = Vector2(16, 16)
	shape_owner_add_shape(create_shape_owner(self), _shared_shape)
	broadphase_radius = _shared_shape.size.length() / 2.0
	if map_ref and is_instance_valid(map_ref) and map_ref.has_method("register_tree_visual"):
		map_ref.register_tree_visual(position)

# --- Forest fire ----------------------------------------------------------------------------------------------------
# A burning tree burns down in BURN_SECONDS, sets fire to trees near it each pulse (so a forest burns, given time), and
# sets any mech standing next to it alight. Lit by FIRE hits and lava vents. Joins "lava_vent" while burning so wary
# bots keep away (HazardSense reads is_dangerous / radius). Numbers marked (tune).
const BURN_DPS = 5.0
const PULSE = 1.0
const SPREAD_RADIUS_CELLS = 2
const SPREAD_CHANCE_ADJACENT = 0.30 # per pulse, per neighbour within 1 cell; farther neighbours get less
const SPREAD_CHANCE_FAR = 0.12
const HEAT_RADIUS = 44.0
const IGNITE_CHANCE_FROM_FIRE_HIT = 0.6
var burning: bool = false
var radius: float = HEAT_RADIUS
var spread_multiplier: float = 1.0 # a map can make its fires spread faster (Dense Forest) or slower
var _pulse_t: float = 0.0
var _flame: Node2D = null
var _burn_seconds: float = 0.0

func is_dangerous() -> bool:
	return burning

func ignite() -> bool:
	if burning or hp <= 0.0:
		return false
	burning = true
	_pulse_t = randf() * PULSE
	add_to_group("burning_tree")
	add_to_group("lava_vent")
	set_process(true)
	if _flame == null:
		_flame = TreeFlame.new()
		add_child(_flame)
	return true

func _process(delta: float):
	if not burning:
		set_process(false)
		return
	_burn_seconds += delta
	hp -= BURN_DPS * delta
	_pulse_t -= delta
	if _pulse_t <= 0.0:
		_pulse_t = PULSE
		_spread()
	if hp <= 0.0:
		_collapse()

func _spread() -> void:
	if map_ref != null and is_instance_valid(map_ref) and map_ref.has_method("trees_near"):
		for t in map_ref.trees_near(cell, SPREAD_RADIUS_CELLS):
			if t == self or t.burning:
				continue
			var d = maxi(absi(t.cell.x - cell.x), absi(t.cell.y - cell.y))
			var chance = (SPREAD_CHANCE_ADJACENT if d <= 1 else SPREAD_CHANCE_FAR) * spread_multiplier
			if randf() < chance:
				t.ignite()
	for group_name in ["player", "enemy"]:
		for m in EntityCache.get_group(group_name):
			if is_instance_valid(m) and m.get("is_dead") != true and m.has_method("apply_status") and m.global_position.distance_to(global_position) <= HEAT_RADIUS:
				m.apply_status("burning", 2.5)

func apply_damage(amount: float, element: String = "RAW", source: Node = null, was_reflected: bool = false, source_label_override: String = ""):
	# Demolition-as-buildcraft (fourth-review ruling): obstacles have
	# element weaknesses. FIRE torches trees for double damage.
	if element == "FIRE":
		amount *= 2.0
		if randf() < IGNITE_CHANCE_FROM_FIRE_HIT:
			ignite()
	hp -= amount
	if hp <= 0:
		_collapse()

# A small flickering flame drawn over a burning tree.
class TreeFlame extends Node2D:
	var _t: float = 0.0
	var _phase: int = 0
	func _ready():
		z_index = 6
		set_process(true)
	func _process(delta: float):
		_t += delta
		if _t > 0.12:
			_t = 0.0
			_phase = (_phase + 1) % 3
			queue_redraw()
	func _draw():
		var h = 10.0 + 4.0 * float(_phase)
		draw_rect(Rect2(-5, -h, 10, h), Color(0.95, 0.35, 0.08, 0.85))
		draw_rect(Rect2(-3, -h * 0.7, 6, h * 0.7), Color(1.0, 0.7, 0.15, 0.9))
		draw_rect(Rect2(-1, -h * 0.4, 2, h * 0.4), Color(1.0, 0.95, 0.6, 0.95))

func _collapse():
	if map_ref and is_instance_valid(map_ref) and "tree_nodes" in map_ref:
		map_ref.tree_nodes.erase(cell)
	if burning:
		remove_from_group("burning_tree")
		remove_from_group("lava_vent")
		ScorchDecals.mark(get_tree(), global_position, 40.0) # charred ground
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
