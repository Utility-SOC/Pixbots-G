extends Node

# Phase 1 of the batch-pool full-parity plan (2026-08-10): Kinetic range/
# lifetime scaling. Previously every batch shot used one flat caller-
# supplied lifetime (GarageTestRange's old BATCH_SHOT_LIFETIME=3.0)
# regardless of synergy - Fire-dominant shots lived too long, Kinetic-
# dominant ones too short (KINETIC_RANGE_BONUS had nothing to spend it on).
# Confirms: the ported _compute_lifetime()/_compute_max_range() pure
# functions match Projectile._get_lifetime()/_calculate_stats()'s own
# formulas at known ratio values, spawn() only auto-computes when the
# caller passes lifetime <= 0.0 (every existing check's explicit positive
# lifetime stays authoritative - zero behavior change for them), and a
# live full-Kinetic shot actually survives long enough in _step_simulate to
# travel further than a zero-Kinetic shot before either despawns.

const ProjectileBatchPoolScript = preload("res://scripts/entities/ProjectileBatchPool.gd")
const ProjectileScript = preload("res://scripts/entities/Projectile.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# --- 1: pure function parity with Projectile.gd's own formulas ---
	_check("no-Fire no-Kinetic lifetime is the flat 4.0 baseline",
		abs(ProjectileBatchPoolScript._compute_lifetime(0.0, 0.0) - 4.0) < 0.001)
	_check("full-Fire (no Kinetic) lifetime is 0.4 (very short plume)",
		abs(ProjectileBatchPoolScript._compute_lifetime(1.0, 0.0) - 0.4) < 0.001)
	_check("full-Fire + full-Kinetic lifetime is 0.4 + 1.0 (Kinetic stretches the plume, doesn't fully override it)",
		abs(ProjectileBatchPoolScript._compute_lifetime(1.0, 1.0) - 1.4) < 0.001)
	_check("full-Kinetic (no Fire) lifetime is 4.0 + 8.0 = 12.0 (the full-range travel budget)",
		abs(ProjectileBatchPoolScript._compute_lifetime(0.0, 1.0) - 12.0) < 0.001)

	_check("zero-Kinetic max_range is exactly BASE_RANGE",
		abs(ProjectileBatchPoolScript._compute_max_range(0.0) - ProjectileScript.BASE_RANGE) < 0.001)
	_check("full-Kinetic max_range is BASE_RANGE + KINETIC_RANGE_BONUS",
		abs(ProjectileBatchPoolScript._compute_max_range(1.0) - (ProjectileScript.BASE_RANGE + ProjectileScript.KINETIC_RANGE_BONUS)) < 0.001)

	# --- 2: spawn()'s lifetime param stays authoritative when positive
	# (regression guard - every existing BatchPool*Check.gd relies on this) ---
	var world = Node2D.new()
	add_child(world)
	var pool = ProjectileBatchPoolScript.new(16)
	world.add_child(pool)

	var explicit_i = pool.spawn(Vector2.ZERO, Vector2.RIGHT, 10.0, 1.0, 5.0, 5.0, Color.WHITE, 1.0, true, null,
		EnergyPacket.SynergyType.FIRE, {EnergyPacket.SynergyType.FIRE: 1.0})
	_check("an explicit positive lifetime (5.0) is used as-is, not overridden by auto-compute (Fire would otherwise force ~0.4)",
		abs(pool._lifetime[explicit_i] - 5.0) < 0.001)
	pool.despawn(explicit_i)

	var auto_i = pool.spawn(Vector2.ZERO, Vector2.RIGHT, 10.0, 1.0, 5.0, -1.0, Color.WHITE, 1.0, true, null,
		EnergyPacket.SynergyType.FIRE, {EnergyPacket.SynergyType.FIRE: 1.0})
	_check("lifetime <= 0.0 opts into auto-compute from ratios (Fire-dominant -> short lifetime)",
		abs(pool._lifetime[auto_i] - 0.4) < 0.001)
	pool.despawn(auto_i)

	# --- 3: live integration - a full-Kinetic shot survives long enough to
	# travel further than a zero-Kinetic shot of the same base speed before
	# either despawns (distance-cap or lifetime-cap, whichever hits first) ---
	var kinetic_i = pool.spawn(Vector2.ZERO, Vector2.RIGHT, 500.0, 1.0, 5.0, -1.0, Color.WHITE, 1.0, true, null,
		EnergyPacket.SynergyType.KINETIC, {EnergyPacket.SynergyType.KINETIC: 1.0})
	var plain_i = pool.spawn(Vector2.ZERO, Vector2.RIGHT, 500.0, 1.0, 5.0, -1.0, Color.WHITE, 1.0, true, null)

	# At ~500px/s: the plain shot's max_range (BASE_RANGE=1400) caps it at
	# ~2.8s, well inside its own 4.0s lifetime, and it then stays dead/frozen
	# for the rest of the loop (despawn() never resets _distance_traveled, so
	# its final value is still readable and meaningful after death). The
	# Kinetic shot's much bigger budget (max_range ~7000px / lifetime 12.0s -
	# the 12.0s lifetime cap wins, at ~6000px) needs real simulated time to
	# actually separate from the plain shot's early cap - 15s (900 ticks)
	# comfortably covers both caps landing.
	for tick in range(900):
		pool._step_simulate(1.0 / 60.0)
	var kinetic_traveled = pool._distance_traveled[kinetic_i]
	var plain_traveled = pool._distance_traveled[plain_i]

	_check("a full-Kinetic shot travels measurably further than a zero-Kinetic shot of the same speed before despawning (kinetic=%.0f, plain=%.0f)" % [kinetic_traveled, plain_traveled],
		kinetic_traveled > plain_traveled * 1.5)

	if failures == 0:
		print("PASS: Kinetic range/lifetime scaling matches Projectile.gd's own formulas, explicit lifetimes stay authoritative, and Kinetic shots genuinely travel further")
	get_tree().quit(0 if failures == 0 else 1)
