class_name FireTrail2D
extends CPUParticles2D

func _init():
	amount = 15
	lifetime = 0.5
	explosiveness = 0.0
	local_coords = false
	direction = Vector2(0, -1)
	spread = 20.0
	gravity = Vector2(0, -100) # Flames rise up slightly
	initial_velocity_min = 15.0
	initial_velocity_max = 30.0
	scale_amount_min = 4.0
	scale_amount_max = 12.0
	
	# Gradient for fire: Yellow -> Red -> Black soot
	var grad = Gradient.new()
	grad.offsets = [0.0, 0.4, 1.0]
	grad.colors = [
		Color(1.0, 1.0, 0.2, 1.0), # Bright yellow
		Color(1.0, 0.2, 0.0, 0.8), # Red-orange
		Color(0.1, 0.1, 0.1, 0.0)  # Fading soot
	]
	color_ramp = grad
	
	# To ensure it stays behind the projectile
	show_behind_parent = true
