class_name DestructibleObstacle
extends StaticBody2D

# Generic single-tile destructible obstacle (task #17: "universal obstacle
# destructibility" - the boulder-class flat obstacles were the last
# non-destructible terrain type; Tree/RuinPart already had their own real
# scene nodes with hp/apply_damage/collapse). Parametrized by MapGenerator's
# obstacle-name tag instead of being one bespoke script per biome, since all
# five flat types (Boulder/Cactus/IceBoulder/LavaRock/StoneWall) share
# identical collapse/nav-clearing behavior and only differ in color/hp/
# elemental weakness. Mirrors TreeObstacle.gd's apply_damage/collapse shape
# and RuinObstacle.gd's debris burst - see those for the pattern this
# generalizes.

# name -> [hp, base_color, weak_element, weak_mult]
const OBSTACLE_STATS = {
	"Boulder": [80.0, Color(0.42, 0.42, 0.46), "EXPLOSION", 2.0],
	"Cactus": [40.0, Color(0.18, 0.42, 0.16), "FIRE", 2.0],
	"IceBoulder": [80.0, Color(0.72, 0.85, 0.92), "FIRE", 2.0],
	"LavaRock": [80.0, Color(0.24, 0.12, 0.1), "ICE", 2.0],
	"StoneWall": [90.0, Color(0.5, 0.48, 0.46), "EXPLOSION", 2.0],
}

var obstacle_name: String = "Boulder"
var hp: float = 80.0
var max_hp: float = 80.0
var map_ref: Node = null
var cell: Vector2i = Vector2i(-1, -1)
var _base_color: Color = Color(0.42, 0.42, 0.46)
var _weak_element: String = "EXPLOSION"
var _weak_mult: float = 2.0

# Projectile hit-broadphase (see scripts/core/ProjectileBroadphase.gd).
var broadphase_radius: float = 0.0

func _ready():
	collision_layer = 32 # terrain-obstacle layer (jets fly over it - see Mech.OBSTACLE_LAYER)
	collision_mask = 0
	add_to_group("obstacle")

	var stats = OBSTACLE_STATS.get(obstacle_name, OBSTACLE_STATS["Boulder"])
	max_hp = stats[0]
	hp = max_hp
	_base_color = stats[1]
	_weak_element = stats[2]
	_weak_mult = stats[3]

	var poly = Polygon2D.new()
	poly.color = _base_color
	poly.polygon = _shape_for(obstacle_name)
	add_child(poly)

	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(16, 16)
	shape.shape = rect
	add_child(shape)
	broadphase_radius = rect.size.length() / 2.0

# Rough silhouette per type so these read as distinct terrain rather than
# five identically-shaped grey boxes - the flat painted square they replace.
func _shape_for(name: String) -> PackedVector2Array:
	match name:
		"Cactus":
			return PackedVector2Array([
				Vector2(-2, -12), Vector2(2, -12), Vector2(2, 6), Vector2(8, 2),
				Vector2(8, -2), Vector2(2, -2), Vector2(2, 2), Vector2(-2, 2),
				Vector2(-8, -2), Vector2(-8, 2), Vector2(-2, 6)
			])
		"StoneWall":
			return PackedVector2Array([
				Vector2(-9, -9), Vector2(9, -9), Vector2(9, 9), Vector2(-9, 9)
			])
		_: # Boulder / IceBoulder / LavaRock: irregular rock silhouette
			return PackedVector2Array([
				Vector2(-9, -3), Vector2(-5, -9), Vector2(4, -8), Vector2(9, -1),
				Vector2(7, 8), Vector2(-3, 9), Vector2(-9, 4)
			])

func apply_damage(amount: float, element: String = "RAW", source: Node = null, was_reflected: bool = false, source_label_override: String = ""):
	if element == _weak_element:
		amount *= _weak_mult
	hp -= amount
	if hp <= 0:
		_collapse()

func _collapse():
	if map_ref and is_instance_valid(map_ref) and cell.x >= 0:
		map_ref.obstacles.erase(cell)
		if "astar_grid" in map_ref and map_ref.astar_grid:
			map_ref.astar_grid.set_point_solid(cell, false)
		if "_flow_field_timer" in map_ref:
			map_ref._flow_field_timer = 0.0

	var debris = CPUParticles2D.new()
	debris.one_shot = true
	debris.emitting = true
	debris.amount = 16
	debris.lifetime = 0.6
	debris.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	debris.emission_rect_extents = Vector2(9, 9)
	debris.gravity = Vector2(0, 80)
	debris.initial_velocity_min = 15.0
	debris.initial_velocity_max = 50.0
	debris.scale_amount_min = 2.0
	debris.scale_amount_max = 3.5
	debris.color = _base_color
	debris.global_position = global_position
	if get_parent():
		get_parent().add_child(debris)
		debris.finished.connect(debris.queue_free)
	queue_free()
