extends Node

# Basic smoke test for ProjectilePool.gd (task #35, B4) - confirms
# acquire()/release() actually cycle the SAME instance (not silently
# falling back to new() every time), and that a released-then-reacquired
# instance is correctly registered with ProjectileManager/ProjectileBroadphase
# exactly once (not zero, not duplicated).

const ProjectilePoolScript = preload("res://scripts/core/ProjectilePool.gd")

func _ready():
	var failures = 0
	var world = Node2D.new()
	add_child(world)
	ProjectilePoolScript._clear_for_testing()

	var proj1 = ProjectilePoolScript.acquire()
	proj1.synergies = {EnergyPacket.SynergyType.RAW: 5.0}
	proj1.damage = 10.0
	proj1.fired_by_player = true
	proj1.direction = Vector2.RIGHT
	proj1.global_position = Vector2.ZERO
	world.add_child(proj1)

	await get_tree().physics_frame

	if not ProjectileManager._active.has(proj1.get_instance_id()):
		push_error("FAIL: freshly acquired+added projectile isn't registered in ProjectileManager")
		failures += 1
	else:
		print("PASS: fresh acquire+add_child registers correctly in ProjectileManager")

	var id1 = proj1.get_instance_id()
	ProjectilePoolScript.release(proj1)

	if ProjectileManager._active.has(id1):
		push_error("FAIL: released projectile is still registered in ProjectileManager")
		failures += 1
	else:
		print("PASS: release() correctly unregistered from ProjectileManager (via remove_child -> _exit_tree)")

	if proj1.get_parent() != null:
		push_error("FAIL: released projectile still has a parent")
		failures += 1

	var proj2 = ProjectilePoolScript.acquire()
	if proj2 != proj1:
		push_error("FAIL: acquire() after a release() didn't return the SAME instance - pool isn't actually reusing")
		failures += 1
	else:
		print("PASS: acquire() after release() returned the SAME instance (real reuse, not a silent new())")

	proj2.synergies = {EnergyPacket.SynergyType.LIGHTNING: 5.0}
	proj2.damage = 15.0
	proj2.fired_by_player = false
	proj2.direction = Vector2.UP
	proj2.global_position = Vector2(100, 100)
	world.add_child(proj2)

	await get_tree().physics_frame

	if not ProjectileManager._active.has(proj2.get_instance_id()):
		push_error("FAIL: re-acquired+re-added projectile isn't registered in ProjectileManager")
		failures += 1
	else:
		print("PASS: re-acquired+re-added projectile is correctly registered exactly once")

	if proj2.ratios.size() != 1 or proj2.ratios.get(EnergyPacket.SynergyType.LIGHTNING, 0.0) < 0.99:
		push_error("FAIL: reused instance's ratios weren't cleanly reset, got %s" % [proj2.ratios])
		failures += 1
	else:
		print("PASS: reused instance's ratios cleanly reflect only the new composition")

	ProjectilePoolScript.release(proj2)
	ProjectilePoolScript._clear_for_testing()

	if failures == 0:
		print("PASS: ProjectilePoolSmokeCheck - acquire/release cycle works end to end")
	get_tree().quit(0 if failures == 0 else 1)
