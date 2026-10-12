class_name UnexplodedOrdnance
extends Node2D

# Munitions Range hazard: a dud shell half buried in the ground. Anything walking right up to it, or an Explosion nearby,
# sets it off for a big blast that hurts everyone around, and one going off can set off its neighbours. It never goes off
# by itself and is armed from the start. Joins "explosion_trigger" (see Projectile / ProjectileBatchPool).

const TRIGGER_RADIUS = 26.0
const BLAST_RADIUS = 110.0
const DAMAGE = 140.0
const CHAIN_DELAY = 0.35
const POLL = 0.25

var radius: float = BLAST_RADIUS
var exploded: bool = false
var _poll: float = 0.0
var _fuse: float = -1.0

func _ready():
	add_to_group("explosion_trigger")
	add_to_group("uxo")
	z_index = -3
	_poll = randf() * POLL
	queue_redraw()

func is_dangerous() -> bool:
	return false # not telegraphed: finding these is the point

func trigger() -> bool:
	if exploded or _fuse >= 0.0:
		return false
	_fuse = CHAIN_DELAY
	return true

func _process(delta: float):
	if exploded:
		return
	if _fuse >= 0.0:
		_fuse -= delta
		if _fuse <= 0.0:
			_detonate()
		return
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = POLL
	for group_name in ["player", "enemy"]:
		for m in EntityCache.get_group(group_name):
			if is_instance_valid(m) and m.get("is_dead") != true and m.global_position.distance_to(global_position) <= TRIGGER_RADIUS:
				_fuse = 0.05
				return

func _detonate() -> void:
	exploded = true
	Sfx.explosion(BLAST_RADIUS, global_position)
	for group_name in ["player", "enemy"]:
		for m in EntityCache.get_group(group_name):
			if is_instance_valid(m) and m.get("is_dead") != true and m.has_method("apply_damage") \
					and m.global_position.distance_to(global_position) <= BLAST_RADIUS:
				m.apply_damage(DAMAGE, "EXPLOSION")
	for other in get_tree().get_nodes_in_group("uxo"):
		if other != self and is_instance_valid(other) and other.global_position.distance_to(global_position) <= BLAST_RADIUS:
			other.trigger()
	queue_redraw()
	get_tree().create_timer(0.4).timeout.connect(func():
		if is_instance_valid(self):
			queue_free())

func _draw():
	if exploded:
		draw_circle(Vector2.ZERO, BLAST_RADIUS * 0.6, Color(1.0, 0.6, 0.2, 0.5))
		return
	draw_circle(Vector2(0, 3), 9.0, Color(0.2, 0.17, 0.12, 0.7)) # disturbed earth
	draw_rect(Rect2(-3, -10, 6, 14), Color(0.35, 0.36, 0.3)) # the shell, nose up
	draw_rect(Rect2(-3, -10, 6, 3), Color(0.55, 0.5, 0.2))
	draw_rect(Rect2(-3, -2, 6, 2), Color(0.5, 0.2, 0.15))
