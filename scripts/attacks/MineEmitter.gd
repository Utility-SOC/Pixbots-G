class_name MineEmitter
extends Node2D

# What a poison mine leaves behind when it triggers, if any of its added
# elements keep acting after detonation (see Projectile.mine_profile - there
# are no named recipes, just traits):
#   - flame: a sustain element (Fire) burns the nearest targets in a short cone;
#   - volley: projectile elements (Kinetic / Pierce) fire single sub-shots at
#     the nearest target, carrying the mine's own mix. Sub-shots are spawned
#     flagged no_mine, so they never become mines or emitters themselves.
#
# Lifetime safety: the mine that spawns this node is destroyed on detonation
# while the emitter lives several more seconds, so it must NOT hold callbacks
# (lambdas) into the mine or the shooter - a lambda capturing a freed object
# crashed the game. It owns plain data, a pool reference (validity-checked on
# every use) and a WeakRef to the shooter.

# Enemies fire plenty of poison, so emitters are capped: each runs a physics query
# several times a second. Over the cap a mine just detonates as a plain burst.
const MAX_LIVE = 14
static var live_count: int = 0

static func can_deploy() -> bool:
	return live_count < MAX_LIVE

const TICK_SEC = 0.2
const VOLLEY_SEC = 0.6
const MAX_FLAME_TARGETS = 2
const CONE_HALF_WIDTH = 20.0

var _flame_range: float = 300.0
var _volley_range: float = 650.0
var _duration: float = 5.0
var _flame_per_tick: float = 0.0
var _volley_per_shot: float = 0.0
var _mask: int = 4
var _pool: Node = null # ProjectileBatchPool: sub-shot spawning + damage routing
var _shot_color: Color = Color.WHITE
var _shot_dom: int = 0
var _shot_ratios: Dictionary = {}
var _by_player: bool = true
var _src_ref: WeakRef = null
var _age: float = 0.0
var _tick_t: float = 0.0
var _volley_t: float = 0.0
var _aim := Vector2.RIGHT
var _flame_len: float = 0.0
var _flaming: bool = false

# shot = {color, dominant, ratios, by_player, source}; `pool` may be null (no
# sub-shots then, and flame damage goes straight to apply_damage).
func setup(duration: float, flame_total: float, flame_range: float, volley_total: float, volley_range: float, collision_mask: int, pool: Node, shot: Dictionary) -> void:
	_duration = duration
	_flame_per_tick = flame_total / max(1.0, duration / TICK_SEC)
	_volley_per_shot = volley_total / max(1.0, duration / VOLLEY_SEC)
	_flame_range = flame_range
	_volley_range = volley_range
	_mask = collision_mask
	_pool = pool
	_shot_color = shot.get("color", Color.WHITE)
	_shot_dom = int(shot.get("dominant", 0))
	_shot_ratios = shot.get("ratios", {})
	_by_player = bool(shot.get("by_player", true))
	var src = shot.get("source", null)
	_src_ref = weakref(src) if src != null and is_instance_valid(src) else null
	z_index = 40

func _enter_tree() -> void:
	live_count += 1
	_tick_t = randf() * TICK_SEC # spread queries across frames

func _exit_tree() -> void:
	live_count = max(0, live_count - 1)

func _process(delta: float) -> void:
	_age += delta
	if _age >= _duration:
		queue_free()
		return
	queue_redraw()

# Space queries belong in the physics step.
func _physics_process(delta: float) -> void:
	_tick_t += delta
	if _tick_t >= TICK_SEC:
		_tick_t -= TICK_SEC
		_tick()

func _pool_ok() -> bool:
	return _pool != null and is_instance_valid(_pool) and _pool.is_inside_tree()

func _hit(col: Node, amount: float) -> void:
	if not is_instance_valid(col):
		return
	if _pool_ok() and _pool.has_method("_apply_damage_to_target"):
		_pool._apply_damage_to_target(col, amount, "FIRE")
	elif col.has_method("apply_damage"):
		col.apply_damage(amount, "FIRE")
	if is_instance_valid(col) and col.has_method("apply_status"):
		col.apply_status("burning", 2.0)

func _fire_sub_shot(target: Node, amount: float) -> void:
	if not _pool_ok() or not is_instance_valid(target):
		return
	var src = _src_ref.get_ref() if _src_ref != null else null
	if src != null and not is_instance_valid(src):
		src = null
	var dir = (target.global_position - global_position).normalized()
	_pool.spawn(global_position, dir, 650.0, amount, 10.0, -1.0, _shot_color, 0.9, _by_player, src, _shot_dom, _shot_ratios, {}, 0.0, {}, 1.0, false, true)

func _tick() -> void:
	var flame_on = _flame_per_tick > 0.0
	var volley_on = _volley_per_shot > 0.0 and _pool_ok()
	_volley_t += TICK_SEC
	var reach = max(_flame_range if flame_on else 0.0, _volley_range if volley_on else 0.0)
	if reach <= 0.0:
		return
	var space = get_world_2d().direct_space_state
	var q = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = reach
	q.shape = shape
	q.transform = global_transform
	q.collision_mask = _mask
	var found: Array = []
	for res in space.intersect_shape(q, 32):
		var col = res.get("collider")
		if col != null and is_instance_valid(col) and col.has_method("apply_damage") and col.get("is_dead") != true and not found.has(col):
			found.append(col)
	found.sort_custom(func(a, b): return a.global_position.distance_squared_to(global_position) < b.global_position.distance_squared_to(global_position))
	_flaming = false
	if flame_on:
		var n = 0
		for col in found:
			if not is_instance_valid(col):
				continue
			var d = col.global_position.distance_to(global_position)
			if d > _flame_range:
				break
			_hit(col, _flame_per_tick)
			if n == 0 and is_instance_valid(col):
				var to_t = col.global_position - global_position
				_aim = to_t.normalized() if to_t.length() > 1.0 else _aim
				_flame_len = min(to_t.length(), _flame_range)
				_flaming = true
			n += 1
			if n >= MAX_FLAME_TARGETS:
				break
	if volley_on and _volley_t >= VOLLEY_SEC and not found.is_empty():
		_volley_t = 0.0
		_fire_sub_shot(found[0], _volley_per_shot)

func _draw() -> void:
	var fade = clamp((_duration - _age) / (_duration * 0.2), 0.0, 1.0)
	draw_circle(Vector2.ZERO, 9.0, Color(0.10, 0.28, 0.08, 0.9 * fade))
	draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 20, Color(0.45, 0.95, 0.2, 0.8 * fade), 2.0)
	if not _flaming:
		return
	var flick = 0.85 + 0.15 * sin(_age * 38.0)
	var len = _flame_len * flick
	var ortho = Vector2(-_aim.y, _aim.x)
	var layers = [
		[1.0, Color(1.0, 0.35, 0.05, 0.55)],
		[0.7, Color(1.0, 0.7, 0.1, 0.65)],
		[0.4, Color(0.75, 1.0, 0.25, 0.8)],
	]
	for l in layers:
		var w = CONE_HALF_WIDTH * l[0]
		var c: Color = l[1]
		c.a *= fade
		draw_colored_polygon(PackedVector2Array([ortho * 3.0, _aim * len + ortho * w, _aim * len * 1.05, _aim * len - ortho * w, -ortho * 3.0]), c)
