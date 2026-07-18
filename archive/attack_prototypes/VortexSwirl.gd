class_name VortexSwirl
extends Node2D

var projectiles: Array[Area2D] = []
var expansion_speed: float = 150.0
var rotation_speed: float = 8.0
var current_radius: float = 10.0
var max_radius: float = 400.0
var damage: float = 15.0

func _ready():
	# Spawn 6 projectiles in a hex pattern
	for i in range(6):
		var area = Area2D.new()
		
		# Add a collision shape
		var collision = CollisionShape2D.new()
		var circle_shape = CircleShape2D.new()
		circle_shape.radius = 15.0
		collision.shape = circle_shape
		area.add_child(collision)
		
		# Connect the hit signal
		area.body_entered.connect(_on_body_entered)
		
		# Visual placeholder (can be replaced with Sprite2D later)
		var visual = Polygon2D.new()
		visual.color = Color(0.5, 0.0, 1.0, 0.8) # Purple vortex
		visual.polygon = PackedVector2Array([
			Vector2(-10, -10), Vector2(10, -10), 
			Vector2(10, 10), Vector2(-10, 10)
		])
		# Make it roughly circular
		var points = PackedVector2Array()
		for j in range(8):
			var angle = j * (PI / 4.0)
			points.append(Vector2(cos(angle), sin(angle)) * 15.0)
		visual.polygon = points
		area.add_child(visual)
		
		add_child(area)
		projectiles.append(area)

func _physics_process(delta: float):
	# Expand outward and spin
	current_radius += expansion_speed * delta
	rotation += rotation_speed * delta
	
	if current_radius > max_radius:
		queue_free()
		return
		
	# Update positions of the 6 spheres
	for i in range(6):
		var angle = i * (PI / 3.0) # 60 degrees apart
		projectiles[i].position = Vector2(cos(angle), sin(angle)) * current_radius

func _on_body_entered(body: Node2D):
	if body.has_method("take_damage"):
		body.take_damage(damage)
		# Add a slight pull effect (vortex)
		if body is CharacterBody2D:
			var pull_dir = (global_position - body.global_position).normalized()
			body.velocity += pull_dir * 100.0
