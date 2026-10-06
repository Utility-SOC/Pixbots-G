class_name LavaVent
extends Node2D

# Volcanic ground hazard: a glowing crack that erupts on a timer. Every eruption has a telegraph (the
# crack brightens and a warning ring closes in for TELEGRAPH seconds), then a burst that hurts and ignites
# everything inside RADIUS - enemies and the player alike, so a vent is a tool as much as a threat
# (lure a squad over it, or hold the ring and let it work). Nothing about movement changes; like the oil
# slick it is walkable and only matters at the moment it fires.
#
# Cheap by design: no physics query (it walks the small player/enemy groups), and it redraws only while
# telegraphing or erupting, never while idle.

const TELEGRAPH = 1.2
const BURST = 0.35
const DAMAGE = 30.0
const MIN_PERIOD = 6.0
const MAX_PERIOD = 11.0
const SfxNames = "boom_small"

var radius: float = 40.0
var damage: float = DAMAGE

var _phase: int = 0 # 0 idle, 1 telegraph, 2 burst
var _timer: float = 0.0
var _seed: int = 0
var times_erupted: int = 0

func _ready():
	add_to_group("lava_vent")
	z_index = -3
	_seed = randi()
	_timer = randf_range(MIN_PERIOD * 0.3, MAX_PERIOD) # staggered so vents don't pulse in unison
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
			_timer = randf_range(MIN_PERIOD, MAX_PERIOD)
	queue_redraw()

func _erupt() -> void:
	times_erupted += 1
	Sfx.play(SfxNames, global_position)
	for victim in victims():
		victim.apply_damage(damage, "FIRE")
		if victim.has_method("apply_status"):
			victim.apply_status("burning", 3.0)

# Everyone currently inside the blast circle.
func victims() -> Array:
	var out: Array = []
	for group_name in ["player", "enemy"]:
		for m in EntityCache.get_group(group_name):
			if is_instance_valid(m) and m.get("is_dead") != true and m.has_method("apply_damage") \
					and m.global_position.distance_to(global_position) <= radius:
				out.append(m)
	return out

# Test hook: jump straight to the telegraph.
func start_telegraph() -> void:
	_phase = 1
	_timer = TELEGRAPH
	queue_redraw()

func _draw():
	var rng = RandomNumberGenerator.new()
	rng.seed = _seed
	# the crack: a jagged dark star with a glowing core, always present
	var glow = 0.4 if _phase == 0 else (0.55 + 0.35 * (1.0 - clampf(_timer / TELEGRAPH, 0.0, 1.0)) if _phase == 1 else 1.0)
	var pts = PackedVector2Array()
	var spikes = 9
	for i in range(spikes * 2):
		var a = i * TAU / float(spikes * 2)
		var r = radius * (0.34 if i % 2 == 0 else 0.15) * (0.8 + rng.randf() * 0.5)
		pts.append(Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, Color(0.06, 0.03, 0.02, 0.9))
	draw_circle(Vector2.ZERO, radius * 0.14, Color(1.0, 0.45, 0.1, glow))
	if _phase == 1:
		var t = 1.0 - clampf(_timer / TELEGRAPH, 0.0, 1.0)
		draw_arc(Vector2.ZERO, radius * (1.0 - 0.35 * t), 0.0, TAU, 40, Color(1.0, 0.4, 0.1, 0.35 + 0.4 * t), 2.0)
	elif _phase == 2:
		var f = clampf(_timer / BURST, 0.0, 1.0)
		draw_circle(Vector2.ZERO, radius * (1.0 - 0.25 * f), Color(1.0, 0.5, 0.1, 0.55 * f))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(1.0, 0.8, 0.3, 0.9 * f), 3.0)
