extends Node

# Task #35's mandatory highest-priority verification: acquire a shot, let
# it accumulate REAL combat state (a real hit via _handle_hit, a real
# homing target, decremented lightning hops), release it, immediately
# re-acquire with a DIFFERENT synergy composition, and assert every
# accumulating field is back to its correct fresh-shot default - not the
# previous shot's leftover values. This is the check that would have
# caught (and, in an earlier form, DID catch - see
# ProjectileReuseMechanicsCheck.gd) both real leaks found during this
# investigation (_lightning_hops_left/_max, ratios/total_power).

const MechScript = preload("res://scripts/entities/Mech.gd")
const ProjectilePoolScript = preload("res://scripts/core/ProjectilePool.gd")

func _ready():
	var failures = 0
	var world = Node2D.new()
	add_child(world)
	ProjectilePoolScript._clear_for_testing()

	# --- First activation: heavy Lightning+Pierce+Vampiric, accumulate real state ---
	var target = MechScript.new()
	target.is_player = false
	target.max_hp = 1000000.0
	target.hp = 1000000.0
	target.global_position = Vector2(200.0, 0.0)
	world.add_child(target)

	var proj1 = ProjectilePoolScript.acquire()
	proj1.synergies = {EnergyPacket.SynergyType.LIGHTNING: 5.0, EnergyPacket.SynergyType.PIERCE: 5.0, EnergyPacket.SynergyType.VAMPIRIC: 3.0}
	proj1.damage = 10.0
	proj1.fired_by_player = true
	proj1.collision_mask = 4
	proj1.direction = Vector2.RIGHT
	proj1.global_position = Vector2.ZERO
	world.add_child(proj1)
	await get_tree().physics_frame

	# Real hit - populates _handled_targets and decrements
	# _lightning_hops_left (lightning re-targeting takes priority over
	# pierce in _handle_hit()'s own tail - same priority HitDecayCheck.gd
	# already confirms - so a single hit on a shot carrying both only ever
	# decrements one, not both; pierce_count's own reset is independently
	# covered by HitDecayCheck.gd/ProjectileReuseMechanicsCheck.gd, not
	# re-required as a precondition here). Doesn't free it (lightning
	# re-targets instead of dying) - explicitly released after.
	proj1._handle_hit(target)
	proj1._cached_homing_target = target # simulate a real homing acquisition without waiting on the throttled batcher

	var had_handled_target = proj1._handled_targets.has(target.get_instance_id())
	var had_lightning_hop_used = proj1._lightning_hops_left < proj1._lightning_hops_max
	if not (had_handled_target and had_lightning_hop_used):
		push_error("FAIL: test setup didn't actually accumulate real state before release (handled=%s hops=%d/%d) - can't verify the reset if there's nothing to reset" % [had_handled_target, proj1._lightning_hops_left, proj1._lightning_hops_max])
		failures += 1
	else:
		print("PASS: first activation accumulated real state (_handled_targets, _lightning_hops_left, _cached_homing_target all non-default)")

	ProjectilePoolScript.release(proj1)

	# --- Second activation: pure Raw, no lightning/pierce/vampiric at all ---
	var proj2 = ProjectilePoolScript.acquire()
	if proj2 != proj1:
		push_error("FAIL: didn't get the same instance back - can't test the actual leak scenario")
		failures += 1
	proj2.synergies = {EnergyPacket.SynergyType.RAW: 5.0}
	proj2.damage = 8.0
	proj2.fired_by_player = true
	proj2.collision_mask = 4
	proj2.direction = Vector2.LEFT
	proj2.global_position = Vector2(500.0, 500.0)
	world.add_child(proj2)
	await get_tree().physics_frame

	# Every accumulating field the plan (B2) enumerated - must be back to a
	# clean default, not leaking the first activation's leftover values.
	if proj2._handled_targets.has(target.get_instance_id()) or not proj2._handled_targets.is_empty():
		push_error("FAIL LEAK: _handled_targets carried over from the previous activation: %s" % [proj2._handled_targets])
		failures += 1
	else:
		print("PASS: _handled_targets cleanly reset")

	if proj2._cached_homing_target != null:
		push_error("FAIL LEAK: _cached_homing_target carried over: %s" % [proj2._cached_homing_target])
		failures += 1
	else:
		print("PASS: _cached_homing_target cleanly reset to null")

	if proj2._lightning_hops_left != 0 or proj2._lightning_hops_max != 0:
		push_error("FAIL LEAK: lightning hops carried over (left=%d max=%d) - a pure-Raw shot should have zero" % [proj2._lightning_hops_left, proj2._lightning_hops_max])
		failures += 1
	else:
		print("PASS: _lightning_hops_left/_max cleanly reset to 0 for a non-lightning shot")

	if proj2.pierce_count != 1 or proj2._pierce_count_max != 1:
		push_error("FAIL LEAK: pierce_count carried over (count=%d max=%d) - a pure-Raw shot should default to 1/1" % [proj2.pierce_count, proj2._pierce_count_max])
		failures += 1
	else:
		print("PASS: pierce_count/_pierce_count_max cleanly reset to 1/1")

	if proj2.ratios.size() != 1 or proj2.ratios.get(EnergyPacket.SynergyType.RAW, 0.0) < 0.99:
		push_error("FAIL LEAK: ratios didn't cleanly reflect the new pure-Raw composition: %s" % [proj2.ratios])
		failures += 1
	else:
		print("PASS: ratios cleanly reflect only the new composition")

	if failures == 0:
		print("PASS: ProjectilePoolStateLeakCheck - no state leaked across a real accumulated-combat-state reuse cycle")
	get_tree().quit(0 if failures == 0 else 1)
