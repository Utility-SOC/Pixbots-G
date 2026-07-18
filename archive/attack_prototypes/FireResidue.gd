class_name FireResidue
extends Area2D

var lifetime: float = 5.0
var timer: float = 0.0
var damage_per_sec: float = 8.0

func _ready():
	# Ground hazard collision shape
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 40.0
	collision.shape = shape
	add_child(collision)
	
	# Visual burning patch on the ground
	var visual = Polygon2D.new()
	visual.color = Color(1.0, 0.3, 0.0, 0.6) # Semi-transparent orange/red
	var points = PackedVector2Array()
	for j in range(12):
		var angle = j * (PI / 6.0)
		points.append(Vector2(cos(angle), sin(angle)) * 40.0)
	visual.polygon = points
	add_child(visual)
	
	# Add GPU particles for lingering flames
	var particles = GPUParticles2D.new()
	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 35.0
	mat.direction = Vector3(0, -1, 0) # Fire goes up
	mat.spread = 20.0
	mat.initial_velocity_min = 20.0
	mat.initial_velocity_max = 50.0
	mat.gravity = Vector3(0, -98, 0)
	mat.color = Color(1.0, 0.5, 0.0, 0.8)
	particles.process_material = mat
	particles.amount = 30
	particles.lifetime = 1.0
	add_child(particles)

func _physics_process(delta: float):
	timer += delta
	if timer > lifetime:
		queue_free()
		return
		
	# Apply Damage over Time to anyone standing in it
	for body in get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.take_damage(damage_per_sec * delta)
		
		# Optionally apply a "burning" status effect that lasts after they leave
		if body.has_method("apply_status"):
			body.apply_status("burning", 3.0) # Burn for 3 seconds after leaving
