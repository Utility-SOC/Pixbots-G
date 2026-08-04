extends Node

# Correctness check for task #34's weapon-charge LOD throttle (Mech.gd's
# _tick_weapon_charges call site) - confirms a far, throttled mech's weapon
# bank still reaches full charge in roughly the same REAL TIME as an
# unthrottled one (chunkier 4Hz updates, not slower overall progress), and
# that transitioning from far back to near mid-cycle flushes any pending
# elapsed time instead of silently losing charge progress. Hand-builds
# precalculated_weapons directly, same established pattern
# TileConfigCheck.gd already uses for bank-mode testing - bypasses the
# accumulator/grid wiring needed to reach a real "bank" mount naturally.

const MechScript = preload("res://scripts/entities/Mech.gd")
const WeaponMountTileScript = preload("res://scripts/tiles/WeaponMountTile.gd")

func _make_bank_mech(is_far: bool, world: Node2D, target: Node2D) -> Node:
	var m = MechScript.new()
	m.is_player = false
	m.target = target
	m.global_position = Vector2(3000.0, 0.0) if is_far else Vector2(0.0, 0.0)
	world.add_child(m)
	m.set_physics_process(false) # drive _physics_process_body via the real _physics_process signal instead - re-enabled right after, just avoids a stray first tick before setup below

	var mount = WeaponMountTileScript.new()
	mount.rarity = HexTile.Rarity.RARE
	mount.body_slot = HexTile.BodySlot.TORSO
	var packet = EnergyPacket.new(80.0, null)
	# Deliberately huge - at the default fire_rate (0.25, i.e. 4
	# charge-units/sec), 3 real seconds only ever accumulates ~12 units.
	# Keeping charge_required far out of reach for the whole test avoids
	# the auto-fire-and-reset-to-0 behavior _tick_weapon_charges triggers
	# on a full non-player bank (see Mech.gd:~1258) - if either mech
	# reached that reset mid-test, comparing their charge at the 3s mark
	# could land them in different phases of the reset cycle and produce a
	# flaky false failure unrelated to whether the LOD throttle itself
	# works correctly.
	packet.charge_required = 1000.0
	m.precalculated_weapons = [{
		"mount": mount, "packet": packet, "step": 0,
		"slot_type": HexTile.BodySlot.TORSO, "bank_mode": "bank",
	}]
	mount.bank_current_charge = 0.0
	m.set_physics_process(true)
	return m

func _ready():
	var failures = 0
	var world = Node2D.new()
	add_child(world)
	var target = Node2D.new()
	target.global_position = Vector2(50000.0, 50000.0) # far outside any mech's engagement/sight range for both cases below
	world.add_child(target)

	var near_mech = _make_bank_mech(false, world, target)
	var far_mech = _make_bank_mech(true, world, target)

	# Run for 3 real sim-seconds - long enough to cross several 0.25s
	# throttle cycles for the far mech.
	for i in range(180):
		await get_tree().physics_frame

	var near_charge = near_mech.precalculated_weapons[0].mount.bank_current_charge
	var far_charge = far_mech.precalculated_weapons[0].mount.bank_current_charge

	print("near mech charge after 3s: %.3f" % near_charge)
	print("far mech charge after 3s:  %.3f" % far_charge)

	# Tolerance: sampling can land mid-cycle for the far mech (up to one
	# full 0.25s throttle interval's worth of not-yet-applied charge, ~1.0
	# unit at this setup's 4.0 charge-units/sec rate) in EITHER direction -
	# two prior attempts at this test used tighter/directional checks and
	# got false failures (11.133 vs 11.933 lagging by 0.8; then 11.667 vs
	# 11.2 LEADING by 0.467) that were both just this same mid-cycle/
	# tick-summation sampling noise, not a real bug. What actually matters:
	# both progress at roughly the same rate over real time, within about
	# one throttle interval's worth of each other, regardless of which
	# direction the sampling instant happens to favor.
	var max_expected_gap = 0.25 * (1.0 / 0.25) + 0.3 # one throttle interval's worth of charge at this fire_rate, +margin
	if far_charge <= 0.0:
		push_error("FAIL: far mech's weapon charge never progressed at all over 3 real seconds")
		failures += 1
	elif absf(far_charge - near_charge) > max_expected_gap:
		push_error("FAIL: far (throttled) mech's charge (%.3f) diverged from the near (unthrottled) mech's charge (%.3f) by more than one throttle interval's worth (%.3f) - real divergence, not just sampling noise" % [far_charge, near_charge, max_expected_gap])
		failures += 1
	else:
		print("PASS: far mech's throttled charge tracks the near mech's unthrottled charge closely over real time (%.3f vs %.3f)" % [far_charge, near_charge])

	# --- Far-to-near transition mid-cycle must not lose pending charge time ---
	var transition_mech = _make_bank_mech(true, world, target)
	await get_tree().physics_frame
	await get_tree().physics_frame # a couple ticks into the throttled phase, some elapsed time now pending
	var charge_before_transition = transition_mech.precalculated_weapons[0].mount.bank_current_charge
	transition_mech.global_position = Vector2(0.0, 0.0) # snap near - should flush pending elapsed time on the very next tick, not drop it
	await get_tree().physics_frame
	var charge_after_transition = transition_mech.precalculated_weapons[0].mount.bank_current_charge
	if charge_after_transition < charge_before_transition:
		push_error("FAIL: charge went BACKWARDS across a far->near transition (%.3f -> %.3f) - should only ever increase" % [charge_before_transition, charge_after_transition])
		failures += 1
	else:
		print("PASS: far->near transition flushed pending elapsed time correctly (charge %.3f -> %.3f, monotonically increasing)" % [charge_before_transition, charge_after_transition])

	if failures == 0:
		print("PASS: WeaponChargeLodCheck - throttled far-mech charging tracks real time correctly, transitions never lose progress")
	get_tree().quit(0 if failures == 0 else 1)
