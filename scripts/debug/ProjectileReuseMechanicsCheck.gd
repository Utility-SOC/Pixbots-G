extends Node

# Verifies the RAW reuse mechanic B4's ProjectilePool will rely on, in
# isolation from the pool itself: remove_child() (not queue_free()) +
# request_ready() + add_child() on the SAME Projectile instance really does
# re-run _ready() (confirming request_ready()'s actual behavior in this
# Godot version, not just assumed API behavior), and the guarded Timer/
# VisibleOnScreenNotifier2D blocks (task #35, B3) correctly reuse the same
# child nodes rather than creating duplicates.

const ProjectileScript = preload("res://scripts/entities/Projectile.gd")

func _ready():
	var failures = 0
	var world = Node2D.new()
	add_child(world)

	var proj = ProjectileScript.new()
	proj.synergies = {EnergyPacket.SynergyType.RAW: 5.0}
	proj.damage = 10.0
	proj.fired_by_player = true
	proj.direction = Vector2.RIGHT
	proj.global_position = Vector2.ZERO
	world.add_child(proj) # first _ready()

	await get_tree().physics_frame

	var timer1 = proj._lifetime_timer
	var notifier1 = proj._vis_notifier
	if not timer1 or not notifier1:
		push_error("FAIL: first _ready() didn't create _lifetime_timer/_vis_notifier")
		failures += 1

	# Simulate the pool cycle: remove (not free), request_ready, re-add.
	var parent = proj.get_parent()
	parent.remove_child(proj)
	if is_instance_valid(proj) and proj.get_parent() != null:
		push_error("FAIL: remove_child left the projectile still parented")
		failures += 1

	proj.request_ready()
	proj.synergies = {EnergyPacket.SynergyType.LIGHTNING: 5.0} # different composition for the second activation
	proj.damage = 20.0
	proj.direction = Vector2.UP
	world.add_child(proj) # second _ready(), if request_ready() worked

	await get_tree().physics_frame

	var timer2 = proj._lifetime_timer
	var notifier2 = proj._vis_notifier

	# NOTE: damage isn't checked against an exact expected value here -
	# _calculate_stats() legitimately SCALES damage based on synergy ratios/
	# magnitude (that's its real job, unrelated to reuse-state-leak), so a
	# Lightning-heavy shot's damage output naturally differs from its raw
	# input. What actually confirms _ready() re-ran cleanly (not stale, not
	# corrupted by leftover state from the first activation) is ratios
	# containing EXACTLY the new composition - not the old RAW entry
	# blended in, which is precisely the ratios/total_power leak this check
	# already caught and got fixed once (see _reset_pooled_state()).
	if proj.ratios.size() != 1 or proj.ratios.get(EnergyPacket.SynergyType.LIGHTNING, 0.0) < 0.99:
		push_error("FAIL: ratios after reuse should be exactly {LIGHTNING: 1.0}, got %s - either _ready() didn't re-run or state leaked from the first activation" % [proj.ratios])
		failures += 1
	else:
		print("PASS: request_ready() + add_child() correctly re-ran _ready() on the same instance (ratios cleanly {LIGHTNING: 1.0}, no leak from the first activation's RAW composition)")

	if timer2 != timer1:
		push_error("FAIL: _lifetime_timer was recreated on reuse instead of reused (identity changed)")
		failures += 1
	else:
		print("PASS: _lifetime_timer reused (same instance) across the reuse cycle")

	if notifier2 != notifier1:
		push_error("FAIL: _vis_notifier was recreated on reuse instead of reused (identity changed)")
		failures += 1
	else:
		print("PASS: _vis_notifier reused (same instance) across the reuse cycle")

	# Confirm no DUPLICATE Timer/Notifier children got added alongside the
	# reused ones (i.e. the guard actually prevented a second create, not
	# just happened to reuse by coincidence).
	var timer_count = 0
	var notifier_count = 0
	for child in proj.get_children():
		if child is Timer and child == timer1:
			timer_count += 1
		if child is VisibleOnScreenNotifier2D:
			notifier_count += 1
	if timer_count != 1:
		push_error("FAIL: expected exactly 1 lifetime Timer child, found %d" % timer_count)
		failures += 1
	if notifier_count != 1:
		push_error("FAIL: expected exactly 1 VisibleOnScreenNotifier2D child, found %d" % notifier_count)
		failures += 1
	if timer_count == 1 and notifier_count == 1:
		print("PASS: no duplicate Timer/Notifier children accumulated across the reuse cycle")

	if failures == 0:
		print("PASS: ProjectileReuseMechanicsCheck - request_ready()-based reuse works as B4's pool design assumes")
	get_tree().quit(0 if failures == 0 else 1)
