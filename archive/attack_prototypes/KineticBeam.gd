class_name KineticBeam
extends Node2D

var raycast: RayCast2D
var line: Line2D
var max_length: float = 800.0
var damage: float = 20.0
var active_time: float = 0.5
var timer: float = 0.0

func _ready():
	# Set up the physics raycast
	raycast = RayCast2D.new()
	raycast.target_position = Vector2(max_length, 0)
	raycast.enabled = true
	raycast.collision_mask = 1 # Assuming enemies are on layer 1
	add_child(raycast)
	
	# Set up the visual line
	line = Line2D.new()
	line.width = 15.0
	line.default_color = Color(0.8, 0.8, 1.0, 1.0) # Bright whitish blue
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(line)
	
	# Force an immediate raycast update so it draws correctly frame 1
	raycast.force_raycast_update()

func _physics_process(delta: float):
	timer += delta
	if timer > active_time:
		# Fade out and destroy
		var alpha = 1.0 - ((timer - active_time) / 0.2)
		if alpha <= 0:
			queue_free()
		else:
			line.default_color.a = alpha
		return
		
	line.clear_points()
	line.add_point(Vector2.ZERO)
	
	if raycast.is_colliding():
		var hit_point = to_local(raycast.get_collision_point())
		line.add_point(hit_point)
		
		# Apply damage if the hit object has a take_damage method
		var collider = raycast.get_collider()
		if collider and collider.has_method("take_damage"):
			collider.take_damage(damage * delta)
	else:
		line.add_point(Vector2(max_length, 0))
