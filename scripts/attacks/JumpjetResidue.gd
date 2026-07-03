class_name JumpjetResidue
extends Area2D

var lifetime: float = 3.0
var timer: float = 0.0
var damage_per_sec: float = 10.0
var synergies: Dictionary = {}

var visual: Polygon2D
var particles: CPUParticles2D

func setup(_damage: float, _synergies: Dictionary):
	damage_per_sec = _damage
	synergies = _synergies.duplicate()
	
	var base_color = EnergyPacket.get_color_blend(synergies)
	
	if visual:
		visual.color = Color(base_color.r, base_color.g, base_color.b, 0.5)
	
	if particles:
		particles.color = Color(base_color.r, base_color.g, base_color.b, 0.8)

func _ready():
	collision_layer = 0
	collision_mask = 4 # Enemies
	
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 25.0
	collision.shape = shape
	add_child(collision)
	
	visual = Polygon2D.new()
	var base_color = EnergyPacket.get_color_blend(synergies) if not synergies.is_empty() else Color.WHITE
	visual.color = Color(base_color.r, base_color.g, base_color.b, 0.5)
	var points = PackedVector2Array()
	for j in range(12):
		var angle = j * (PI / 6.0)
		points.append(Vector2(cos(angle), sin(angle)) * 25.0)
	visual.polygon = points
	add_child(visual)
	
	particles = CPUParticles2D.new()
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 20.0
	particles.direction = Vector2(0, -1)
	particles.spread = 20.0
	particles.initial_velocity_min = 10.0
	particles.initial_velocity_max = 30.0
	particles.gravity = Vector2(0, -50)
	particles.color = Color(base_color.r, base_color.g, base_color.b, 0.8)
	particles.amount = 15
	particles.lifetime = 0.5
	add_child(particles)

func _physics_process(delta: float):
	timer += delta
	if timer > lifetime:
		# Fade out
		visual.modulate.a -= delta * 2.0
		particles.emitting = false
		if visual.modulate.a <= 0:
			queue_free()
		return
		
	for body in get_overlapping_bodies():
		if body.has_method("apply_damage"):
			# Find dominant synergy for damage type
			var element = "RAW"
			if synergies.has(EnergyPacket.SynergyType.FIRE): element = "FIRE"
			elif synergies.has(EnergyPacket.SynergyType.ICE): element = "ICE"
			elif synergies.has(EnergyPacket.SynergyType.LIGHTNING): element = "LIGHTNING"
			
			var dmg = damage_per_sec * delta
			body.apply_damage(dmg, element)
			
			if body.has_method("apply_status"):
				if synergies.has(EnergyPacket.SynergyType.FIRE):
					body.apply_status("burning", 2.0)
				if synergies.has(EnergyPacket.SynergyType.ICE):
					body.apply_status("frozen", 2.0)
