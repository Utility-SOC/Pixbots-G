class_name Trail2D
extends Line2D

@export var max_length: int = 20
var _target: Node2D

func _ready():
	top_level = true
	_target = get_parent()
	clear_points()
	
	# Optional: Make the trail fade out towards the tail
	var curve = Curve.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(1, 1))
	width_curve = curve

func _physics_process(_delta):
	if is_instance_valid(_target):
		add_point(_target.global_position)
		if get_point_count() > max_length:
			remove_point(0)
	elif get_point_count() > 0:
		# If parent is gone but we somehow survived, fade out points
		remove_point(0)
		if get_point_count() == 0:
			queue_free()
