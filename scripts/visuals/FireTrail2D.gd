class_name FireTrail2D
extends Node2D

@export var max_length: int = 15
@export var base_radius: float = 12.0
var _target: Node2D
var _points: Array[Vector2] = []

func _ready():
	top_level = true
	_target = get_parent()

func _physics_process(_delta):
	if is_instance_valid(_target):
		_points.push_front(_target.global_position)
		if _points.size() > max_length:
			_points.pop_back()
	else:
		_points.pop_back()
		if _points.is_empty():
			queue_free()
	queue_redraw()

func _draw():
	if _points.is_empty(): return
	
	# Draw from back to front (oldest point to newest point) so front circle covers the rest
	for i in range(_points.size() - 1, -1, -1):
		var pt = _points[i] - global_position
		var t = float(i) / max_length
		
		# Gradient: Bright Yellow (front) -> Red -> Black (back/soot)
		var color = Color.WHITE
		if t < 0.4:
			# t=0 is front (Yellow), t=0.4 is middle (Red)
			color = Color(1.0, 1.0, 0.2).lerp(Color(1.0, 0.0, 0.0), t / 0.4)
		else:
			# t=0.4 is middle (Red), t=1.0 is back (Black soot)
			color = Color(1.0, 0.0, 0.0).lerp(Color(0.1, 0.1, 0.1, 0.5), (t - 0.4) / 0.6)
			
		# Radius shrinks as it goes back
		var radius = base_radius * (1.0 - (t * 0.7)) # Drops down to 30% size
		
		draw_circle(pt, radius, color)
