extends Node

# Task #35 B5 verification item 3: a pooled projectile reused with a
# DIFFERENT synergy composition must produce a visual_node subtree
# reflecting ONLY the new composition - not the old one left over
# alongside it. Caught a real bug: _build_visuals() unconditionally did
# `visual_node = Node2D.new(); add_child(visual_node)` with no teardown of
# the previous visual_node, so a reused shot rendered BOTH the stale
# Kinetic wedge AND the new Fire trail simultaneously (the `visual_node`
# var reassignment only forgets the old reference, it doesn't remove the
# actual node). Fixed in Projectile.gd's _build_visuals() by
# remove_child()+queue_free()-ing any existing visual_node first.

const ProjectilePoolScript = preload("res://scripts/core/ProjectilePool.gd")

func _ready():
	var failures = 0
	var world = Node2D.new()
	add_child(world)
	ProjectilePoolScript._clear_for_testing()

	# --- First activation: pure Kinetic ---
	var proj1 = ProjectilePoolScript.acquire()
	proj1.synergies = {EnergyPacket.SynergyType.KINETIC: 5.0}
	proj1.damage = 10.0
	proj1.fired_by_player = true
	proj1.direction = Vector2.RIGHT
	proj1.global_position = Vector2.ZERO
	world.add_child(proj1)
	await get_tree().physics_frame

	var old_visual_node = proj1.visual_node
	if not is_instance_valid(old_visual_node) or old_visual_node.get_child_count() == 0:
		push_error("FAIL: first activation didn't build any visual children - can't verify the reuse teardown")
		failures += 1
	else:
		print("PASS: first activation built a Kinetic visual_node with %d child(ren)" % old_visual_node.get_child_count())

	var id1 = proj1.get_instance_id()
	ProjectilePoolScript.release(proj1)

	# --- Second activation: pure Fire (full_ornament likely off in headless test range, but shape still changes) ---
	var proj2 = ProjectilePoolScript.acquire()
	if proj2.get_instance_id() != id1:
		push_error("FAIL: didn't get the same pooled instance back - can't test the actual reuse scenario")
		failures += 1
	proj2.synergies = {EnergyPacket.SynergyType.FIRE: 5.0}
	proj2.damage = 10.0
	proj2.fired_by_player = true
	proj2.direction = Vector2.LEFT
	proj2.global_position = Vector2(300, 300)
	world.add_child(proj2)
	await get_tree().physics_frame

	# The old visual_node must be gone - not still parented under proj2 as
	# a leftover sibling of the new one.
	if is_instance_valid(old_visual_node) and old_visual_node.get_parent() == proj2:
		push_error("FAIL LEAK: the FIRST activation's visual_node is still attached to the reused projectile - stale visuals would render alongside the new ones")
		failures += 1
	else:
		print("PASS: first activation's visual_node was removed, not left attached")

	# Exactly one Node2D "visual root" child should be present now (the new
	# visual_node) - more than one means duplicate/overlapping visual
	# subtrees. NOTE: VisibleOnScreenNotifier2D is ALSO a Node2D subclass
	# (it has its own rect/transform), so it must be excluded explicitly
	# rather than assumed non-Node2D - an earlier version of this check got
	# that wrong and produced a false failure.
	var node2d_children = 0
	for child in proj2.get_children():
		if child is Node2D and child != proj2._vis_notifier:
			node2d_children += 1
	if node2d_children != 1:
		push_error("FAIL LEAK: expected exactly 1 non-notifier Node2D child (the current visual_node) on the reused projectile, found %d" % node2d_children)
		failures += 1
	else:
		print("PASS: exactly one visual_node subtree present after reuse (no duplicate/overlapping visuals)")

	if not is_instance_valid(proj2.visual_node) or proj2.visual_node.get_child_count() == 0:
		push_error("FAIL: second activation didn't build any visual children")
		failures += 1
	else:
		print("PASS: second activation built a fresh Fire visual_node with %d child(ren)" % proj2.visual_node.get_child_count())

	if failures == 0:
		print("PASS: ProjectilePoolVisualCheck - reused projectile's visuals cleanly reflect only the new composition")
	get_tree().quit(0 if failures == 0 else 1)
