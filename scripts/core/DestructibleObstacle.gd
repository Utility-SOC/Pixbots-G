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

# Hard cover: soaks up every hit that is not its weak element (no hp loss) and stops piercing shots
# dead; only a weakness hit (explosives) can crack it. Everything else in OBSTACLE_STATS is soft
# cover that chips away under any damage. Map variety: walls and boulders shape the fight, cacti,
# ice and lava rock are there to be shot through.
const ABSORBERS = ["Boulder", "StoneWall"]

var obstacle_name: String = "Boulder"
var _shape_pts: PackedVector2Array = PackedVector2Array()
var _outline_color: Color = Color.BLACK
var _flash_t: float = 0.0 # >0 while the 'absorbed a hit' flash is showing
var absorbs: bool = false
var blocks_pierce: bool = false # read by Projectile / ProjectileBatchPool after a hit
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
	absorbs = obstacle_name in ABSORBERS
	blocks_pierce = absorbs

	# One canvas item per obstacle (this node draws itself) instead of a Polygon2D + Line2D child pair:
	# ~2.8k destructibles on a big map were ~5.6k extra canvas items (a node diet, see ROADMAP Phase 8).
	_shape_pts = _shape_for(obstacle_name)
	# Accessibility (user report, 2026-08-03: obstacles were "NOT accessible"
	# - too close in color to their own terrain). A luminance-contrasted
	# outline (dark border on a light fill, light border on a dark fill)
	# reads against any biome's palette without per-biome color-matching -
	# same fix as TreeObstacle.gd.
	var luminance = 0.299 * _base_color.r + 0.587 * _base_color.g + 0.114 * _base_color.b
	_outline_color = Color(0.05, 0.05, 0.05, 0.95) if luminance > 0.5 else Color(0.95, 0.95, 0.9, 0.9)
	queue_redraw()

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
	elif absorbs:
		_spark()
		return
	hp -= amount
	if hp <= 0:
		_collapse()

# Visible "that did nothing" feedback for absorbed hits: a brief light flash on the rock.
func _spark():
	if _flash_t > 0.0:
		return
	_flash_t = 0.06
	queue_redraw()
	get_tree().create_timer(0.06).timeout.connect(func():
		if is_instance_valid(self):
			_flash_t = 0.0
			queue_redraw())

func _draw():
	var fill = _base_color.lightened(0.45) if _flash_t > 0.0 else _base_color
	var parts = _draw_parts()
	if obstacle_name == "Cactus":
		# Outlines of all boxes first (grown by 1 px), fills on top, so overlapping boxes read as ONE
		# silhouette with a clean outer outline instead of crossing lines.
		for pts in parts:
			draw_colored_polygon(_grow(pts, 1.5), _outline_color)
		for pts in parts:
			draw_colored_polygon(pts, fill)
		return
	for pts in parts:
		draw_colored_polygon(pts, fill)
		draw_polyline(pts + PackedVector2Array([pts[0]]), _outline_color, 2.0, true)

static func _grow(pts: PackedVector2Array, by: float) -> PackedVector2Array:
	var c = Vector2.ZERO
	for p in pts:
		c += p
	c /= float(pts.size())
	var out = PackedVector2Array()
	for p in pts:
		out.append(p + (p - c).sign() * by)
	return out

# The cactus silhouette overlaps itself (trunk and arms share edges), which the polygon filler rejects,
# so it is drawn as three plain boxes; every other type is one simple polygon.
func _draw_parts() -> Array:
	if obstacle_name == "Cactus":
		return [_box(-2, -12, 2, 6), _box(2, -2, 8, 2), _box(-8, -2, -2, 2)]
	return [_shape_pts] if _shape_pts.size() >= 3 else []

static func _box(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])

func _collapse():
	if map_ref and is_instance_valid(map_ref) and cell.x >= 0:
		map_ref.obstacles.erase(cell)
		if "astar_grid" in map_ref and map_ref.astar_grid:
			map_ref.astar_grid.set_point_solid(cell, false)
		if "_flow_field_timer" in map_ref:
			map_ref._flow_field_timer = 0.0

	# GPU migration (AAA Polish Roadmap Priority 1): every fps collapse chased
	# this session traced back to the same "many small per-instance CPU
	# costs" pattern this class of debris burst was still part of.
	var debris = GPUParticles2D.new()
	debris.one_shot = true
	debris.emitting = true
	debris.amount = 16
	debris.lifetime = 0.6
	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(9, 9, 0)
	mat.gravity = Vector3(0, 80, 0)
	mat.initial_velocity_min = 15.0
	mat.initial_velocity_max = 50.0
	mat.scale_min = 2.0
	mat.scale_max = 3.5
	mat.color = _base_color
	debris.process_material = mat
	debris.global_position = global_position
	if get_parent():
		get_parent().add_child(debris)
		debris.finished.connect(debris.queue_free)
		# One-shot GPU particles that are off-screen never advance, so `finished` never fires and the
		# node leaked (hundreds after a long fight). A timer frees it regardless.
		get_tree().create_timer(1.6).timeout.connect(func():
			if is_instance_valid(debris):
				debris.queue_free())
	queue_free()
