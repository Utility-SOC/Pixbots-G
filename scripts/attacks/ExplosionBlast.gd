class_name ExplosionBlast
extends Node2D

var damage: float = 30.0
var radius: float = 100.0

func _ready():
	var poly = Polygon2D.new()
	poly.color = Color(1.0, 0.5, 0.0, 0.7) # Orange transparent explosion
	# Make a circle
	var pts = PackedVector2Array()
	var sides = 16
	for i in range(sides):
		var angle = i * PI * 2 / sides
		pts.append(Vector2(cos(angle), sin(angle)) * radius)
	poly.polygon = pts
	add_child(poly)
	
	# Apply AOE
	var space_state = get_world_2d().direct_space_state
	# Assuming Godot 4.x shape query here if needed, but for now we'll mock
	print("Explosion went off! Radius: ", radius, " Damage: ", damage)
	
	var timer = Timer.new()
	timer.wait_time = 0.3
	timer.timeout.connect(queue_free)
	add_child(timer)
	timer.start()
