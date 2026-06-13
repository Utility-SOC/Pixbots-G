class_name PierceRay
extends Area2D

var damage: float = 20.0
var direction: Vector2 = Vector2.RIGHT
var speed: float = 600.0

func _ready():
	var poly = Polygon2D.new()
	poly.color = Color(0.8, 0.8, 1.0) # Bright blue/white
	poly.polygon = PackedVector2Array([
		Vector2(0, -2), Vector2(15, 0), Vector2(0, 2), Vector2(-10, 0)
	])
	add_child(poly)
	
	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(25, 4)
	shape.shape = rect
	shape.position = Vector2(2.5, 0)
	add_child(shape)
	
	body_entered.connect(_on_body_entered)
	
	var timer = Timer.new()
	timer.wait_time = 2.0
	timer.timeout.connect(queue_free)
	add_child(timer)
	timer.start()

func _physics_process(delta):
	position += direction * speed * delta

func _on_body_entered(body: Node):
	if body.has_method("apply_damage"):
		# Pierce ray doesn't queue_free immediately, it keeps going through enemies
		body.apply_damage(damage)
