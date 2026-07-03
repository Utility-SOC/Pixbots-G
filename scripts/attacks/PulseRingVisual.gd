class_name PulseRingVisual
extends Node2D

# Lightweight expanding-ring effect, reused by Jammer Module pulses (purple)
# and Heal Beacon pulses (green) so we don't need two near-identical files.
# Self-contained: no dependency on other attack scripts.

var radius: float = 200.0
var ring_color: Color = Color(0.6, 0.2, 0.9, 1.0)
var _progress: float = 0.0
var _duration: float = 0.6

func setup(p_radius: float, p_color: Color, p_duration: float = 0.6):
	radius = p_radius
	ring_color = p_color
	_duration = p_duration

func _ready():
	z_index = -1
	var tween = create_tween()
	tween.tween_method(_set_progress, 0.0, 1.0, _duration)
	tween.tween_callback(queue_free)

func _set_progress(p: float):
	_progress = p
	queue_redraw()

func _draw():
	var r = radius * _progress
	var alpha = ring_color.a * (1.0 - _progress)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(ring_color.r, ring_color.g, ring_color.b, alpha), 4.0, true)
