class_name AcidBall
extends Area2D

var damage: float = 10.0
var direction: Vector2 = Vector2.RIGHT
var speed: float = 400.0

func _ready():
	var poly = Polygon2D.new()
	poly.color = Color(0.2, 0.9, 0.2) # Bright green acid
	poly.polygon = PackedVector2Array([
		Vector2(-5, -5), Vector2(5, -5), Vector2(5, 5), Vector2(-5, 5)
	])
	add_child(poly)
	
	var shape = CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shape.shape.radius = 6.0
	add_child(shape)
	
	body_entered.connect(_on_body_entered)
	
	var timer = Timer.new()
	timer.wait_time = 3.0
	timer.one_shot = true
	timer.timeout.connect(queue_free)
	add_child(timer)
	timer.start()

func _physics_process(delta):
	position += direction * speed * delta

func _on_body_entered(body: Node):
	if body.has_method("apply_status"):
		body.apply_status("poison", 5.0) # 5 seconds of poison DoT
		if body.has_method("apply_damage"):
			body.apply_damage(damage)
	queue_free()
