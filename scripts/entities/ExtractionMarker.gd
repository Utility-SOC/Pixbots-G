extends Area2D

func _ready():
	# Visual representation: A glowing circle
	var visual = Polygon2D.new()
	var pts = PackedVector2Array()
	var num_pts = 32
	var radius = 60.0
	for i in range(num_pts):
		var angle = (i / float(num_pts)) * TAU
		pts.append(Vector2(cos(angle), sin(angle)) * radius)
	visual.polygon = pts
	visual.color = Color(0.2, 1.0, 0.4, 0.5) # Glowing green
	add_child(visual)
	
	var outline = Line2D.new()
	outline.points = pts
	outline.add_point(pts[0]) # close loop
	outline.width = 4.0
	outline.default_color = Color(0.1, 1.0, 0.3, 1.0)
	add_child(outline)
	
	# Text Label
	var label = Label.new()
	label.text = "EXTRACT"
	label.add_theme_font_size_override("font_size", 20)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	label.position = Vector2(-45, -15)
	add_child(label)
	
	# Collision
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = radius
	collision.shape = shape
	add_child(collision)
	
	collision_layer = 0
	collision_mask = 8 # Collide with player layer
	
	body_entered.connect(_on_body_entered)
	
	var tween = create_tween().set_loops()
	tween.tween_property(visual, "modulate:a", 0.2, 1.0)
	tween.tween_property(visual, "modulate:a", 0.5, 1.0)

func _on_body_entered(body: Node2D):
	if body.is_in_group("player"):
		var main = get_tree().current_scene
		if main and main.has_method("_open_garage"):
			# _open_garage() rebuilds mech visuals, which adds new physics
			# nodes (hitbox Area2D/CollisionShape2D) - doing that synchronously
			# from inside this body_entered signal mutates physics state while
			# the physics server is still flushing the very query that fired
			# this callback ("Can't change this state while flushing queries").
			# Deferring past the current physics step is exactly what Godot's
			# own error message recommends here.
			main.call_deferred("_open_garage")
			queue_free()
