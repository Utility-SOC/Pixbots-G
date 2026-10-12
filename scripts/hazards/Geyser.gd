class_name Geyser
extends Node2D

# Hydrothermal Park hazard: a vent that bubbles, then erupts a column of near-boiling water. Everything in the burst is
# DRENCHED (Lightning hurts more, Fire hurts less, any burn is put out) and SCALDED (damage over time). Enemies and the
# player alike; like the lava vent it is walkable and only matters at the moment it fires. Joins "lava_vent" so wary
# bots step away from a geyser about to blow (HazardSense), and "explosion_trigger" so an Explosion nearby sets it off.

const TELEGRAPH = 1.6
const BURST = 0.6
const DAMAGE = 14.0
const MIN_PERIOD = 7.0
const MAX_PERIOD = 14.0
const DRENCH_SECONDS = 6.0
const SCALD_SECONDS = 4.0

var radius: float = 48.0
var damage: float = DAMAGE
var times_erupted: int = 0
var _phase: int = 0 # 0 idle, 1 telegraph, 2 burst
var _timer: float = 0.0

func _ready():
	add_to_group("lava_vent")
	add_to_group("explosion_trigger")
	z_index = -3
	_timer = SimRng.stream("combat").randf_range(MIN_PERIOD * 0.3, MAX_PERIOD)
	queue_redraw()

func _process(delta: float):
	_timer -= delta
	if _timer > 0.0:
		if _phase != 0:
			queue_redraw()
		return
	match _phase:
		0:
			_phase = 1
			_timer = TELEGRAPH
		1:
			_phase = 2
			_timer = BURST
			_erupt()
		2:
			_phase = 0
			_timer = SimRng.stream("combat").randf_range(MIN_PERIOD, MAX_PERIOD)
	queue_redraw()

func is_dangerous() -> bool:
	return _phase != 0

func trigger() -> bool:
	if _phase != 0:
		return false
	_phase = 1
	_timer = TELEGRAPH
	queue_redraw()
	return true

func _erupt() -> void:
	times_erupted += 1
	for victim in victims():
		victim.apply_damage(damage, "RAW")
		if victim.has_method("apply_status"):
			victim.apply_status("drenched", DRENCH_SECONDS)
			victim.apply_status("scalded", SCALD_SECONDS)

func victims() -> Array:
	var out: Array = []
	for group_name in ["player", "enemy"]:
		for m in EntityCache.get_group(group_name):
			if is_instance_valid(m) and m.get("is_dead") != true and m.has_method("apply_damage") \
					and m.global_position.distance_to(global_position) <= radius:
				out.append(m)
	return out

func _draw():
	draw_circle(Vector2.ZERO, 7.0, Color(0.2, 0.2, 0.22, 0.9))
	if _phase == 1:
		var t = 1.0 - clampf(_timer / TELEGRAPH, 0.0, 1.0)
		draw_arc(Vector2.ZERO, radius * (1.0 - 0.3 * t), 0.0, TAU, 36, Color(0.9, 0.95, 1.0, 0.3 + 0.4 * t), 2.0)
		draw_circle(Vector2.ZERO, 10.0 + 10.0 * t, Color(0.9, 0.95, 1.0, 0.25 + 0.3 * t))
	elif _phase == 2:
		var f = clampf(_timer / BURST, 0.0, 1.0)
		draw_circle(Vector2.ZERO, radius * (1.0 - 0.2 * f), Color(0.85, 0.93, 1.0, 0.5 * f))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 36, Color(1, 1, 1, 0.9 * f), 3.0)
