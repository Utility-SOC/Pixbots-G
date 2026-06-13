class_name TreeObstacle
extends StaticBody2D

var hp: float = 30.0

func _ready():
	collision_layer = 1
	collision_mask = 0
	
	var poly = Polygon2D.new()
	poly.color = Color(0.05, 0.3, 0.05) # Dark green
	poly.polygon = PackedVector2Array([
		Vector2(0, -12), Vector2(8, 8), Vector2(-8, 8)
	])
	add_child(poly)
	
	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(16, 16)
	shape.shape = rect
	add_child(shape)

func apply_damage(amount: float, element: String = "RAW"):
	hp -= amount
	if hp <= 0:
		queue_free()
