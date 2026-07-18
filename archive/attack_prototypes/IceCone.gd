class_name IceCone
extends Area2D

var collision_poly: CollisionPolygon2D
var particles: GPUParticles2D
var active_time: float = 2.0
var timer: float = 0.0
var damage_per_sec: float = 10.0

func _ready():
	# Create a cone shape for collision
	collision_poly = CollisionPolygon2D.new()
	var points = PackedVector2Array()
	points.append(Vector2.ZERO) # Origin
	
	# Sweep an arc for the cone (e.g. 60 degrees wide, 300 units long)
	var angle_spread = PI / 3.0
	var radius = 300.0
	var segments = 8
	
	for i in range(segments + 1):
		var angle = -angle_spread/2.0 + (angle_spread * i / segments)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	
	collision_poly.polygon = points
	add_child(collision_poly)
	
	# Connect signal to apply damage/slow to enemies entering
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# Setup particles for visual blowing snow
	particles = GPUParticles2D.new()
	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	mat.direction = Vector3(1, 0, 0) # Emitting right
	mat.spread = 30.0 # 60 degree cone
	mat.initial_velocity_min = 200.0
	mat.initial_velocity_max = 350.0
	mat.color = Color(0.6, 0.9, 1.0, 0.8) # Frosty blue
	mat.gravity = Vector3(0, 0, 0)
	particles.process_material = mat
	particles.amount = 100
	particles.lifetime = 1.0
	particles.explosiveness = 0.1
	add_child(particles)

func _physics_process(delta: float):
	timer += delta
	if timer > active_time:
		particles.emitting = false
		if timer > active_time + 1.0: # Wait for particles to finish
			queue_free()
		return
		
	# Apply continuous damage/slow to overlapping bodies
	for body in get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.take_damage(damage_per_sec * delta)
			
		if body.has_method("apply_status"):
			body.apply_status("frozen", 0.5)

func _on_body_entered(body: Node2D):
	# Immediate slow application could go here
	pass

func _on_body_exited(body: Node2D):
	pass
