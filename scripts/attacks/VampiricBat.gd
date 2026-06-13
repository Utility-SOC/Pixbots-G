class_name VampiricBat
extends Area2D

var damage: float = 10.0
var direction: Vector2 = Vector2.RIGHT
var speed: float = 350.0
var shooter: Node2D # Reference back to the player/mech that fired it

func _ready():
	# Scale particle bat based on damage (magnitude)
	var bat_scale = clamp(damage / 50.0, 0.5, 3.0)
	
	var poly = Polygon2D.new()
	poly.color = Color(0.1, 0.1, 0.1) # Dark bat
	# Bat shape
	poly.polygon = PackedVector2Array([
		Vector2(0, -3), Vector2(6, -6), Vector2(2, 0), Vector2(6, 6), Vector2(0, 3),
		Vector2(-6, 6), Vector2(-2, 0), Vector2(-6, -6)
	])
	poly.scale = Vector2(bat_scale, bat_scale)
	add_child(poly)
	
	var shape = CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shape.shape.radius = 8.0 * bat_scale
	add_child(shape)
	
	body_entered.connect(_on_body_entered)
	
	var timer = Timer.new()
	timer.wait_time = 4.0
	timer.timeout.connect(queue_free)
	add_child(timer)
	timer.start()

func _physics_process(delta):
	position += direction * speed * delta

func _on_body_entered(body: Node):
	if body != shooter and body.has_method("apply_damage"):
		body.apply_damage(damage)
		_spawn_return_particles()
	queue_free()

func _spawn_return_particles():
	if not shooter: return
	
	# Would spawn a GPUParticles2D that sets emission to curve back to shooter
	# Here we simulate with a dummy node or print
	var return_heal = damage * 0.5
	if shooter.has_method("heal"):
		shooter.heal(return_heal)
	print("VampiricBat returned ", return_heal, " HP to shooter in an arc!")
