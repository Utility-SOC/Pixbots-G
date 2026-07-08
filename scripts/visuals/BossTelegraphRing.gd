class_name BossTelegraphRing
extends Node2D

# Small reusable VFX: an expanding ring outline. Used two ways by boss
# signature abilities (see Mech.gd's _start_boss_ability/_resolve_shockwave):
#   telegraph() - grows slowly and pulses during an ability's windup, so the
#                 player can see (and step out of) the danger zone before it
#                 resolves.
#   burst()     - snaps outward fast and fades - the "impact" moment itself.
# One class covers both since they're the same shape, just different tweens.

var _radius: float = 10.0
var _color: Color = Color.WHITE
var _width: float = 3.0

func _ready():
	z_index = 50

func _draw():
	draw_arc(Vector2.ZERO, _radius, 0, TAU, 48, _color, _width)

func set_radius(r: float):
	_radius = r
	queue_redraw()

func telegraph(target_radius: float, duration: float, color: Color):
	_color = color
	_width = 3.0
	set_radius(0.0)
	modulate.a = 1.0
	var tw = create_tween()
	tw.tween_method(set_radius, 0.0, target_radius, duration)
	tw.parallel().tween_property(self, "modulate:a", 0.35, duration)
	tw.tween_callback(queue_free)

func burst(start_radius: float, end_radius: float, duration: float, color: Color):
	_color = color
	_width = 6.0
	set_radius(start_radius)
	modulate.a = 1.0
	var tw = create_tween()
	tw.tween_method(set_radius, start_radius, end_radius, duration)
	tw.parallel().tween_property(self, "modulate:a", 0.0, duration)
	tw.tween_callback(queue_free)
