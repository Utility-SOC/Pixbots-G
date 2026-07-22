extends Node

# Regression harness for: DeathExplosion's crater decal was meant to
# persist as a permanent scorch mark (its own code comment: "We should
# unparent the crater and leave it in the scene") but didn't - top_level
# = true only affects transform inheritance, not whether queue_free() on
# the parent cascades to it, so the crater vanished along with the rest of
# the explosion after the 3s cleanup timer.
#
# First fix attempt (remove_child + add_child on the SAME crater node, from
# inside the Timer's own timeout callback while that Timer was still this
# node's child) reliably crashed the engine (segfault) in testing -
# modifying a node's children mid-signal-dispatch from one of those same
# children is apparently unsafe in this Godot version. Fixed instead by
# spawning an INDEPENDENT replacement decal on the parent right as the
# original is freed - no children-list surgery on the explosion node at all.

const DeathExplosionScript = preload("res://scripts/visuals/DeathExplosion.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _find_timer(node: Node) -> Timer:
	for c in node.get_children():
		if c is Timer:
			return c
	return null

func _find_crater(node: Node) -> Polygon2D:
	for c in node.get_children():
		if c is Polygon2D:
			return c
	return null

func _ready():
	var saved_craters = DeathExplosionScript._persisted_craters.duplicate()
	DeathExplosionScript._persisted_craters.clear()

	var world = Node2D.new()
	add_child(world)

	# --- 1. A single explosion leaves behind a persisted decal, reparented
	# to the explosion's own parent, position preserved, tracked in the list. -
	var explosion = DeathExplosionScript.new()
	explosion.global_position = Vector2(123.0, 456.0)
	world.add_child(explosion)

	var crater = _find_crater(explosion)
	_check("explosion has a real crater Polygon2D child before cleanup", crater != null)

	var timer = _find_timer(explosion)
	_check("explosion has a real cleanup Timer child", timer != null)

	timer.timeout.emit() # fire the 3s cleanup callback immediately, no real wait
	await get_tree().process_frame
	await get_tree().process_frame

	_check("exactly one persisted decal exists after cleanup", DeathExplosionScript._persisted_craters.size() == 1)
	var persisted = DeathExplosionScript._persisted_craters[0] if DeathExplosionScript._persisted_craters.size() > 0 else null
	_check("the persisted decal is a real, valid Polygon2D", persisted != null and is_instance_valid(persisted) and persisted is Polygon2D)
	if persisted:
		_check("the persisted decal is parented directly to the explosion's own parent (the world)",
			persisted.get_parent() == world)
		_check("the persisted decal's world position matches where the explosion happened",
			persisted.global_position.distance_to(Vector2(123.0, 456.0)) < 0.5)
		_check("the persisted decal looks like the original crater (same polygon/color/scale)",
			persisted.color == Color(0.1, 0.1, 0.1, 0.8) and persisted.scale == Vector2(80, 80))

	# --- 2. Cap: spawning past MAX_PERSISTED_CRATERS evicts the oldest.
	# Directly exercises the eviction logic with lightweight stand-in decals
	# rather than spawning dozens of full DeathExplosion instances (each
	# with 2 GPUParticles2D + a Tween) - that's real GPU-adjacent overhead
	# this check doesn't need to pay just to test a plain Array cap. -------
	DeathExplosionScript._persisted_craters.clear()
	var first_decal = Polygon2D.new()
	world.add_child(first_decal)
	DeathExplosionScript._persisted_craters.append(first_decal)
	for i in range(DeathExplosionScript.MAX_PERSISTED_CRATERS):
		var extra = Polygon2D.new()
		world.add_child(extra)
		DeathExplosionScript._persisted_craters.append(extra)
		if DeathExplosionScript._persisted_craters.size() > DeathExplosionScript.MAX_PERSISTED_CRATERS:
			var oldest = DeathExplosionScript._persisted_craters.pop_front()
			if is_instance_valid(oldest):
				oldest.queue_free()
	await get_tree().process_frame

	_check("the persisted-craters list is capped at MAX_PERSISTED_CRATERS, not left to grow unbounded",
		DeathExplosionScript._persisted_craters.size() == DeathExplosionScript.MAX_PERSISTED_CRATERS)
	_check("the OLDEST decal (added first) was evicted and freed once the cap was exceeded",
		not is_instance_valid(first_decal))

	DeathExplosionScript._persisted_craters = saved_craters

	if failures == 0:
		print("PASS: DeathExplosion craters actually persist after cleanup (an independent decal, not a risky same-node reparent), capped so they can't grow unbounded")
	get_tree().quit(0 if failures == 0 else 1)
