extends Node

# Regression harness for the CloakSystem extraction (Mech.gd tech-debt
# pass): confirms the split preserves every external behavior exactly -
# recharge, activation threshold, drain-to-auto-break, the ambush damage
# window, external mech.is_cloaked writes (BossBrain-style), and the
# has_cloak_generator=false safety branch.

const MechScript = preload("res://scripts/entities/Mech.gd")
const CloakSystemScript = preload("res://scripts/entities/CloakSystem.gd")

const DT := 1.0 / 30.0

func _ready():
	var failures = 0
	var world = Node2D.new()
	add_child(world)

	var mech = MechScript.new()
	mech.is_player = false # AI branch: wants_cloak driven by target distance, not input
	world.add_child(mech)
	mech.set_physics_process(false)

	# Wire up a cloak generator's capacity fields exactly as
	# _recalculate_grid would (see CloakTile.gd/Mech._recalculate_grid).
	# Drain is deliberately slow relative to recharge/threshold here so
	# activation reaches a STABLE cloaked state to assert against, rather
	# than immediately oscillating drain<->recharge (a real, correct
	# possibility with an aggressive drain rate - not what's under test here).
	mech.has_cloak_generator = true
	mech.max_cloak_charge = 100.0
	mech.cloak_recharge_rate = 50.0 # 2s to full from empty
	mech.cloak_recharge_delay = 0.2
	mech.cloak_drain_rate = 2.0 # slow - stays cloaked for many ticks once active
	mech.cloak_system = CloakSystemScript.new(mech)

	# A distant "target" so the AI branch's wants_cloak reads true
	# (closing distance > engagement_distance * 0.9).
	var far_target = Node2D.new()
	far_target.global_position = Vector2(5000, 0)
	world.add_child(far_target)
	mech.target = far_target
	mech.engagement_distance = 100.0

	# --- 1. Recharges toward full once past the delay, then activates -----
	for i in range(90): # 3s - well past the ~18-tick threshold crossing at this recharge rate
		mech.cloak_system.tick(DT)
	if not mech.is_cloaked:
		push_error("FAIL: mech never activated cloak despite full charge + wanting it")
		failures += 1
	else:
		print("1) recharges from empty, activates once past the 30%% threshold")

	# --- 2. Charge drains while cloaked ------------------------------------
	var charge_before = mech.cloak_system.cloak_charge
	mech.cloak_system.tick(DT)
	if mech.cloak_system.cloak_charge >= charge_before:
		push_error("FAIL: charge didn't drain while cloaked (%f -> %f)" % [charge_before, mech.cloak_system.cloak_charge])
		failures += 1
	else:
		print("2) charge drains while active (%.2f -> %.2f)" % [charge_before, mech.cloak_system.cloak_charge])

	# --- 3. Draining to 0 auto-breaks cloak --------------------------------
	mech.cloak_system.cloak_charge = 0.02 # less than one tick's drain (2.0 * DT ~= 0.067), guaranteed to cross 0
	mech.cloak_system.tick(DT)
	if mech.is_cloaked:
		push_error("FAIL: cloak didn't auto-break when charge hit 0")
		failures += 1
	else:
		print("3) charge hitting 0 auto-breaks cloak")

	# --- 4. External _break_cloak() call (BossBrain/PlayerController path) -
	mech.cloak_system.cloak_charge = mech.max_cloak_charge
	mech.is_cloaked = true # simulating BossBrain's direct "mech.is_cloaked = true"
	mech._break_cloak()
	if mech.is_cloaked or mech.cloak_system.time_since_cloak_break != 0.0:
		push_error("FAIL: external _break_cloak() didn't cleanly break cloak")
		failures += 1
	else:
		print("4) external mech._break_cloak() (the thin wrapper) works exactly as before")

	# --- 5. Ambush multiplier: active while cloaked, and during the window -
	mech.is_cloaked = true
	if mech._get_ambush_multiplier() != CloakSystemScript.AMBUSH_MULTIPLIER:
		push_error("FAIL: no ambush multiplier while actively cloaked")
		failures += 1
	else:
		print("5a) ambush multiplier applies while cloaked")

	mech.is_cloaked = false
	mech.cloak_system._ambush_window_timer = CloakSystemScript.AMBUSH_WINDOW_DURATION
	if mech._get_ambush_multiplier() != CloakSystemScript.AMBUSH_MULTIPLIER:
		push_error("FAIL: no ambush multiplier during the post-decloak window")
		failures += 1
	else:
		print("5b) ambush multiplier applies during the post-decloak window")

	# Clear the target so the recharge branch's wants_cloak reads false -
	# otherwise sufficient banked charge (from step 1) would just
	# re-activate cloak mid-loop and mask what this assertion is actually
	# checking (pure ambush-window decay, not "does cloak stay off").
	mech.target = null
	for i in range(30): # 1s > AMBUSH_WINDOW_DURATION (0.25s)
		mech.cloak_system.tick(DT)
	if mech._get_ambush_multiplier() != 1.0:
		push_error("FAIL: ambush multiplier never decayed back to 1.0")
		failures += 1
	else:
		print("5c) ambush multiplier decays back to 1.0 once the window elapses")

	# --- 6. No cloak generator: forced uncloaked, full opacity -------------
	mech.has_cloak_generator = false
	mech.is_cloaked = true
	mech.modulate.a = 0.3
	mech.cloak_system.tick(DT)
	if mech.is_cloaked or mech.modulate.a != 1.0:
		push_error("FAIL: has_cloak_generator=false didn't force uncloak + full opacity")
		failures += 1
	else:
		print("6) unequipping the cloak generator forces uncloak + full opacity")

	if failures == 0:
		print("PASS: CloakSystem extraction preserves every external behavior")
	get_tree().quit(0 if failures == 0 else 1)
