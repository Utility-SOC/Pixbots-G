extends Node2D

func _ready():
	# 1. Shockwave Ring
	var shockwave = Polygon2D.new()
	var pts = PackedVector2Array()
	for i in range(32):
		var a = i * PI / 16.0
		pts.append(Vector2(cos(a), sin(a)))
	shockwave.polygon = pts
	shockwave.color = Color(1, 0.8, 0.5, 0.5)
	
	# Scale animation for shockwave
	var tw = create_tween()
	tw.tween_property(shockwave, "scale", Vector2(400, 400), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(shockwave, "color", Color(1, 0.2, 0.0, 0.0), 0.5)
	add_child(shockwave)
	
	# 2. Debris Particles
	var debris = GPUParticles2D.new()
	debris.amount = 100
	debris.lifetime = 2.0
	debris.one_shot = true
	debris.explosiveness = 0.95
	
	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 20.0
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 200.0
	mat.initial_velocity_max = 800.0
	mat.gravity = Vector3(0, 0, 0)
	mat.scale_min = 3.0
	mat.scale_max = 8.0
	mat.color = Color(0.2, 0.2, 0.2)
	debris.process_material = mat
	add_child(debris)
	debris.emitting = true
	
	# 3. Fireball Core
	var core = GPUParticles2D.new()
	core.amount = 50
	core.lifetime = 0.8
	core.one_shot = true
	core.explosiveness = 0.9
	
	var cmat = ParticleProcessMaterial.new()
	cmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	cmat.emission_sphere_radius = 5.0
	cmat.direction = Vector3(0, 0, 0)
	cmat.spread = 180.0
	cmat.initial_velocity_min = 100.0
	cmat.initial_velocity_max = 300.0
	cmat.scale_min = 10.0
	cmat.scale_max = 30.0
	cmat.color = Color(1.0, 0.5, 0.0, 1.0)
	core.process_material = cmat
	add_child(core)
	core.emitting = true
	
	# 4. Screen Shake (Magnificent)
	var cam = get_tree().get_first_node_in_group("camera")
	if cam and cam.has_method("shake"):
		cam.shake(3.0, 1.5)
		
	# 5. Crater Sprite / Decal
	var crater = Polygon2D.new()
	crater.polygon = pts
	crater.color = Color(0.1, 0.1, 0.1, 0.8) # Dark scorch mark
	crater.scale = Vector2(80, 80)
	crater.z_index = -10 # Below everything
	add_child(crater)
	
	# Cleanup timer for the emitters (Crater stays forever since it's added to world?)
	# Wait, if we queue_free, the crater disappears.
	# We should unparent the crater and leave it in the scene.
	crater.top_level = true
	crater.global_position = global_position
	
	var timer = Timer.new()
	timer.wait_time = 3.0
	timer.one_shot = true
	timer.timeout.connect(func():
		queue_free()
	)
	add_child(timer)
	timer.start()
