class_name FireProjectile
extends Area2D

var speed: float = 400.0
var direction: Vector2 = Vector2.RIGHT
var max_distance: float = 500.0
var distance_traveled: float = 0.0

func _ready():
	# Simple circle collider
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 10.0
	collision.shape = shape
	add_child(collision)
	
	body_entered.connect(_on_body_entered)
	
	# Visual fireball
	var visual = Polygon2D.new()
	visual.color = Color(1.0, 0.4, 0.0, 1.0)
	var points = PackedVector2Array()
	for j in range(8):
		var angle = j * (PI / 4.0)
		points.append(Vector2(cos(angle), sin(angle)) * 10.0)
	visual.polygon = points
	add_child(visual)

func _physics_process(delta: float):
	var move_step = direction * speed * delta
	position += move_step
	distance_traveled += move_step.length()
	
	if distance_traveled >= max_distance:
		spawn_residue()
		queue_free()

func _on_body_entered(body: Node2D):
	# Ignore the shooter (assuming shooter is parent or handled via collision layers)
	spawn_residue()
	queue_free()

func spawn_residue():
	var residue = preload("res://scripts/attacks/FireResidue.gd").new()
	residue.global_position = global_position
	get_tree().current_scene.add_child(residue)


# ------------------------------------------------------------------------------
# FireResidue.gd (Normally this would be a separate file, but placing here for portability if needed.
# For standard Godot workflow, let's create it dynamically in the global scope if not loaded)
# ------------------------------------------------------------------------------
