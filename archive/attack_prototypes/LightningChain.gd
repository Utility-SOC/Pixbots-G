class_name LightningChain
extends Area2D

var damage: float = 10.0
var bounces_left: int = 3
var previously_hit: Array[Node] = []

func _ready():
	# Lightning visualization
	var line = Line2D.new()
	line.default_color = Color(1.0, 1.0, 0.0)
	line.width = 3.0
	line.add_point(Vector2.ZERO)
	line.add_point(Vector2(50, 0)) # Placeholder length
	add_child(line)
	
	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(50, 10)
	shape.shape = rect
	shape.position = Vector2(25, 0)
	add_child(shape)
	
	body_entered.connect(_on_body_entered)
	
	var timer = Timer.new()
	timer.wait_time = 0.2 # Lightning fades quickly
	timer.timeout.connect(queue_free)
	add_child(timer)
	timer.start()

func _on_body_entered(body: Node):
	if body in previously_hit: return
	
	if body.has_method("apply_damage"):
		body.apply_damage(damage)
		previously_hit.append(body)
		
		if bounces_left > 0:
			_chain_to_next(body.global_position)

func _chain_to_next(start_pos: Vector2):
	# In a full game, query physics 2D for nearest body within radius
	print("Lightning chained! Bounces left: ", bounces_left - 1)
