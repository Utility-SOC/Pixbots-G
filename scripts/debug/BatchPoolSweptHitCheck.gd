extends Node

# Regression check for the swept-segment hit-test fix: _step_hit_test used
# to check only a shot's END-OF-TICK position against a target's radius,
# which tunnels - a fast or swirling shot can hop clean over a target
# between two consecutive tick positions without either landing inside it.
# Confirmed via a real repro this session: a Vortex-ratio shot missed a
# stationary target entirely at a normal 60fps tick rate. Fixed by checking
# the closest point on the swept segment (prev_position -> position) each
# tick instead of just the endpoint.

const ProjectileBatchPoolScript = preload("res://scripts/entities/ProjectileBatchPool.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var world = Node2D.new()
	add_child(world)
	var pool = ProjectileBatchPoolScript.new(8)
	world.add_child(pool)

	var target = MechScript.new()
	target.is_player = false
	target.max_hp = 1000.0
	target.hp = 1000.0
	target.global_position = Vector2(100, 100)
	world.add_child(target)
	pool.register_target(target)

	# --- 1: a shot whose single-tick jump would leap CLEAN OVER the target
	# (end-of-tick position on one side, start-of-tick on the other, target
	# radius smaller than the jump) must still register a hit, since the
	# swept segment passes directly through the target.
	var i = pool.spawn(Vector2(0, 100), Vector2.RIGHT, 0.0, 50.0, 10.0, 5.0, Color.WHITE, 1.0, true, null)
	# Manually simulate one huge jump (bypasses _step_simulate's own speed-
	# based movement so this test is deterministic regardless of Rust
	# availability) - prev_position stays at spawn (0,100), position jumps
	# straight past the target to (250,100). The target (100,100) sits ON
	# this segment, well within its radius.
	pool._position[i] = Vector2(250, 100)
	var hp_before = target.hp
	pool._step_hit_test()
	_check("a shot whose per-tick jump passes clean through the target registers a hit (swept segment, not just the endpoint)",
		target.hp < hp_before and pool._alive[i] == 0)

	# --- 2: the OLD point-only check would have missed this exact case -
	# confirm the endpoint alone really is outside the hit radius, so this
	# test is actually exercising the swept-segment path, not coincidentally
	# passing because the endpoint itself was already close enough.
	var endpoint_distance = Vector2(250, 100).distance_to(Vector2(100, 100))
	_check("sanity: the jump's END-OF-TICK point alone is well outside the hit radius (endpoint dist=%.0f, radius=30) - this case genuinely needs the swept check" % endpoint_distance,
		endpoint_distance > 30.0)

	# --- 3: a shot that never comes near the target at all (segment passes
	# far away) still correctly does NOT hit.
	var far_target = target
	pool.unregister_target(far_target)
	var far = MechScript.new()
	far.is_player = false
	far.max_hp = 1000.0
	far.hp = 1000.0
	far.global_position = Vector2(100, 100)
	world.add_child(far)
	pool.register_target(far)
	var i2 = pool.spawn(Vector2(0, 500), Vector2.RIGHT, 0.0, 50.0, 10.0, 5.0, Color.WHITE, 1.0, true, null)
	pool._position[i2] = Vector2(250, 500) # far below the target, never crosses near it
	var hp_before2 = far.hp
	pool._step_hit_test()
	_check("a shot whose swept segment stays far from the target still correctly misses",
		far.hp == hp_before2 and pool._alive[i2] == 1)

	if failures == 0:
		print("PASS: ProjectileBatchPool's hit-test uses a swept segment, not a point-only check, so fast/swirling shots no longer tunnel past a target")
	get_tree().quit(0 if failures == 0 else 1)
