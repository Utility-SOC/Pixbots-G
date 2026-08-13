extends Node

# Regression harness for the AI _shoot() call-site throttle (perf plan,
# wave-138 playtest: "shoot 466ms/sec" - every non-player, non-boss mech in
# engagement range called _shoot() on EVERY physics tick with no fire-rate
# gate at that call site at all). Fix: Mech.gd's AI combat-shooting call
# site now gates non-boss mechs behind a per-instance _ai_shoot_timer at
# AI_SHOOT_CHECK_HZ, while _tick_weapon_charges (charge accumulation) stays
# completely untouched and unthrottled - so the fix should cut how often
# _shoot() gets CALLED without changing how often a weapon actually FIRES
# over time (steady-state DPS unchanged).
#
# Exercises the real call-site code directly (the actual _ai_shoot_timer
# field, the actual AI_SHOOT_CHECK_HZ const, the actual _shoot()/
# _tick_weapon_charges() methods) rather than driving the full
# _execute_ai_tactics() (which pulls in BossBrain/raycasts/sight-batcher
# dependencies unrelated to what this specific fix touches).

const MechScript = preload("res://scripts/entities/Mech.gd")
const WeaponMountTileScript = preload("res://scripts/tiles/WeaponMountTile.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

var world: Node2D

# A slow-charging mount (charge_required well above 1 tick's worth) so the
# simulated window covers several real fire events, not just "always ready."
func _make_armed_mech(charge_required: float) -> Node:
	var mech = MechScript.new()
	mech.is_player = false
	mech.is_boss = false
	world.add_child(mech)
	mech.set_physics_process(false)
	mech.global_position = Vector2.ZERO

	var torso = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.RARE)
	torso.generate_shape()
	var core = CoreTileScript.new()
	core.rarity = HexTile.Rarity.RARE
	var active: Array[int] = [0]
	core.active_faces = active
	torso.hex_grid.add_tile(HexCoord.new(0, 0), core)
	var mount = WeaponMountTileScript.new()
	mount.rarity = HexTile.Rarity.RARE
	mount.body_slot = HexTile.BodySlot.TORSO
	torso.hex_grid.add_tile(HexCoord.new(1, 0), mount)

	mech.equip_component(torso)
	mech._recalculate_grid()
	for data in mech.precalculated_weapons:
		data.packet.charge_required = charge_required
	mech.last_aim_position = Vector2(600, 0)
	return mech

func _ready():
	world = Node2D.new()
	add_child(world)

	const DELTA = 1.0 / 60.0
	const TICKS = 600 # 10 simulated seconds
	const CHARGE_REQUIRED = 2.0 # at default fire_rate 0.25, takes ~0.5s to charge

	var mech = _make_armed_mech(CHARGE_REQUIRED)
	_check("setup produced a real armed mount - can't measure the throttle without one",
		not mech.precalculated_weapons.is_empty())

	Mech._perf_diag_shoot_call_count = 0
	Mech._perf_diag_shots_fired_count = 0
	var target_pos = mech.global_position + Vector2(600, 0)

	for i in range(TICKS):
		mech._tick_weapon_charges(DELTA)
		# Exact call-site logic from Mech.gd's AI combat-shooting block -
		# see _ai_shoot_timer's own field comment there.
		if mech.is_boss:
			mech._shoot(target_pos, true, true, DELTA)
		else:
			mech._ai_shoot_timer -= DELTA
			if mech._ai_shoot_timer <= 0.0:
				mech._ai_shoot_timer = 1.0 / Mech.AI_SHOOT_CHECK_HZ
				mech._shoot(target_pos, true, true, DELTA)

	var calls = Mech._perf_diag_shoot_call_count
	var fires = Mech._perf_diag_shots_fired_count

	_check("throttled _shoot() call count is meaningfully lower than TICKS (%d) - got %d calls" % [TICKS, calls],
		calls < TICKS)

	# Expected call count: roughly TICKS * (AI_SHOOT_CHECK_HZ * DELTA) - real
	# ticks-per-cycle can round UP by one tick versus the naive continuous-
	# time estimate (float accumulation over discrete 1/60s steps doesn't
	# divide 1/AI_SHOOT_CHECK_HZ evenly - the same decrement-and-flat-reset
	# timer shape as this file's own pre-existing _lod_ai_timer/
	# _lod_weapon_charge_timer, so this is an accepted, already-shipped
	# characteristic of this codebase's throttle pattern, not unique to this
	# fix). Bounded below by requiring a REAL cut versus unthrottled (TICKS),
	# and above by a generous ceiling that still proves it's throttling
	# something close to the intended rate, not silently doing nothing.
	var expected_calls_ideal = TICKS * (Mech.AI_SHOOT_CHECK_HZ * DELTA)
	_check("throttled call count (%d) is a real cut from TICKS (%d) and still in the right order of magnitude vs. the ideal-continuous-time estimate (%.1f)" % [calls, TICKS, expected_calls_ideal],
		calls >= expected_calls_ideal * 0.5 and calls <= expected_calls_ideal * 1.1)

	# Expected fire count: charge accumulates delta*r_mult/fire_rate per tick
	# (Mech.gd's own _tick_weapon_charges, completely untouched by this fix -
	# r_mult is _get_rarity_charge_multiplier(mount), 1.5x for a RARE mount
	# like this check's own _make_armed_mech uses) regardless of how often
	# _shoot() gets CALLED - over the whole simulated window that's
	# TICKS*DELTA*r_mult/fire_rate total charge, firing once every
	# CHARGE_REQUIRED banked. This is the steady-state DPS invariant the
	# throttle must preserve. (2026-08-13: this formula originally omitted
	# r_mult entirely, undercounting by 1.5x and reading as a false "DPS
	# changed" regression - not a real bug, the check just predated/missed
	# the rarity-charge-multiplier mechanic.)
	var r_mult = mech._get_rarity_charge_multiplier(mech.precalculated_weapons[0].mount)
	var expected_fires = floori((TICKS * DELTA * r_mult / mech.fire_rate) / CHARGE_REQUIRED)
	_check("throttled fire-event count (%d) matches the analytical steady-state expectation (%d, +/-2 for check-cadence boundary quantization) - DPS not meaningfully changed by the throttle" % [fires, expected_fires],
		abs(fires - expected_fires) <= 2)

	if failures == 0:
		print("PASS: AI _shoot() call-site throttle cuts call frequency while leaving actual fire-event cadence (steady-state DPS) unchanged")
	get_tree().quit(0 if failures == 0 else 1)
