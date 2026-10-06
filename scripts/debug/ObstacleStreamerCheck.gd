extends Node

# ObstacleCollisionStreamer: obstacles far from every mech/projectile leave the physics broadphase,
# near ones keep colliding, new obstacles respect the invariant, wake_all restores everything.

const MapGeneratorScript = preload("res://scripts/core/MapGenerator.gd")
const FakeMech = preload("res://scripts/debug/ObstacleStreamerFakeMech.gd")
const StreamerScript = preload("res://scripts/core/ObstacleCollisionStreamer.gd")
const DestructibleScript = preload("res://scripts/core/DestructibleObstacle.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

# Ground truth: does the real physics space still contain this obstacle's shape? (The server has no
# getter for a disabled shape, so ask it with a point query after a physics step.)
func _asleep(o: StaticBody2D) -> bool:
	await get_tree().physics_frame
	var q = PhysicsPointQueryParameters2D.new()
	q.collision_mask = 32
	q.position = o.global_position
	return get_viewport().world_2d.direct_space_state.intersect_point(q).size() == 0

func _mk(pos: Vector2) -> StaticBody2D:
	var o = DestructibleScript.new()
	o.global_position = pos
	add_child(o)
	return o

func _ready():
	var s = StreamerScript.new()
	add_child(s)
	var near = _mk(Vector2(100, 100))
	var far = _mk(Vector2(9000, 9000))
	var mech = FakeMech.new()
	mech.global_position = Vector2(150, 150)
	mech.add_to_group("enemy")
	add_child(mech)
	await get_tree().physics_frame
	s.refresh()
	_check("obstacle next to a mech stays awake", not (await _asleep(near)))
	_check("obstacle far from everything sleeps", (await _asleep(far)))
	_check("stats count them (awake 1, asleep 1)", s.last_awake == 1 and s.last_asleep == 1)

	mech.global_position = Vector2(8900, 9000)
	s.refresh()
	_check("moving the mech wakes the far obstacle", not (await _asleep(far)))
	_check("and the one it left sleeps", (await _asleep(near)))

	# A projectile also keeps collision alive around it.
	var proj = Node2D.new()
	proj.global_position = Vector2(100, 120)
	proj.add_to_group("projectile")
	add_child(proj)
	s.refresh()
	_check("projectile wakes obstacles near it", not (await _asleep(near)))
	proj.queue_free()
	await get_tree().process_frame

	# New obstacle in a sleeping cell must be put to sleep; one in an awake cell stays awake.
	var new_far = _mk(Vector2(-5000, -5000))
	var new_near = _mk(Vector2(8950, 9050))
	s.refresh()
	_check("new obstacle in a sleeping cell sleeps", (await _asleep(new_far)))
	_check("new obstacle in an awake cell is awake", not (await _asleep(new_near)))

	# Freed obstacles don't break the tick.
	far.queue_free()
	await get_tree().process_frame
	s.refresh()
	_check("refresh survives a freed obstacle", true)

	s.wake_all()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var a1 = await _asleep(near)
	var a2 = await _asleep(new_far)
	print("DBG near_asleep=", a1, " new_far_asleep=", a2, " buckets=", s._buckets.size(), " active=", s._active_cells.size())
	_check("wake_all enables everything", not a1 and not a2)

	print("ObstacleStreamerCheck: %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)

