extends Node

# Correctness check for the preamble-throttling follow-up (task #34
# continuation) - confirms a far, throttled mech's status-effect DoT damage
# still totals correctly over real time (chunkier increments, not slower
# overall progress), same verification shape as WeaponChargeLodCheck.gd.

const MechScript = preload("res://scripts/entities/Mech.gd")

func _make_mech(is_far: bool, world: Node2D, target: Node2D) -> Node:
	var m = MechScript.new()
	m.is_player = false
	m.target = target
	m.global_position = Vector2(3000.0, 0.0) if is_far else Vector2(0.0, 0.0)
	m.max_hp = 1000000.0
	m.hp = 1000000.0
	world.add_child(m)
	# Long duration so it never expires mid-test - isolates the DAMAGE-total
	# question from the expiry-timing-precision question (already accepted
	# as a minor, disclosed tradeoff per the plan).
	m.apply_status("burning", 999.0)
	return m

func _ready():
	var failures = 0
	var world = Node2D.new()
	add_child(world)
	var target = Node2D.new()
	target.global_position = Vector2(50000.0, 50000.0) # far outside any mech's engagement/sight range for both cases below
	world.add_child(target)

	var near_mech = _make_mech(false, world, target)
	var far_mech = _make_mech(true, world, target)

	# 3 real sim-seconds - long enough to cross several 0.25s throttle cycles.
	for i in range(180):
		await get_tree().physics_frame

	var near_damage = near_mech.max_hp - near_mech.hp
	var far_damage = far_mech.max_hp - far_mech.hp
	var expected = 5.0 * 3.0 # burning = 5 dmg/sec

	print("near mech burn damage after 3s: %.3f (expected ~%.1f)" % [near_damage, expected])
	print("far mech burn damage after 3s:  %.3f (expected ~%.1f)" % [far_damage, expected])

	# Tolerance: sampling can land mid-cycle for the far mech (up to one
	# full 0.25s throttle interval's worth of not-yet-applied damage, ~1.25
	# at 5 dmg/sec) in either direction - same lesson from
	# WeaponChargeLodCheck.gd's own tolerance design (two earlier attempts
	# at that check used tighter/directional tolerances and got false
	# failures on ordinary mid-cycle sampling noise).
	var max_expected_gap = 0.25 * 5.0 + 0.5

	if far_damage <= 0.0:
		push_error("FAIL: far mech's burn damage never progressed at all over 3 real seconds")
		failures += 1
	elif absf(far_damage - near_damage) > max_expected_gap:
		push_error("FAIL: far (throttled) mech's damage (%.3f) diverged from the near (unthrottled) mech's damage (%.3f) by more than one throttle interval's worth (%.3f)" % [far_damage, near_damage, max_expected_gap])
		failures += 1
	elif absf(near_damage - expected) > 1.0 or absf(far_damage - expected) > max_expected_gap + 1.0:
		push_error("FAIL: damage total doesn't match the expected 5 dmg/sec rate (near=%.3f, far=%.3f, want ~%.1f)" % [near_damage, far_damage, expected])
		failures += 1
	else:
		print("PASS: far mech's throttled DoT tracks the near mech's unthrottled DoT closely, both matching the real 5 dmg/sec rate")

	if failures == 0:
		print("PASS: StatusEffectLodCheck - throttled far-mech status-effect damage totals correctly over real time")
	get_tree().quit(0 if failures == 0 else 1)
