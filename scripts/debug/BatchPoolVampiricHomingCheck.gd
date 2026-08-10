extends Node

# Phase 4 of the batch-pool full-parity plan (2026-08-10): Vampiric homing
# ("The Hunter"). The shared Rust flight code already had this steering
# branch fully implemented and parity-tested (BatchPoolFlightParityCheck.
# gd) - _step_simulate just used to hardcode has_homing_target=0.0/
# target_direction=zero into every request unconditionally, so the branch
# never actually engaged for any batch-pool shot regardless of ratio.
#
# Confirms: a Vampiric shot aimed away from a registered target rotates
# its direction measurably toward that target over several ticks (not
# staying fixed), a shot with no real Vampiric ratio never homes even with
# a target adjacent (regression guard), and a Vampiric shot with no target
# within its own acquire range doesn't home either (falls back to whatever
# passive drift/straight flight the Rust code does with target_direction
# left at zero).

const ProjectileBatchPoolScript = preload("res://scripts/entities/ProjectileBatchPool.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _make_target(world: Node, pos: Vector2) -> Node:
	var t = MechScript.new()
	t.is_player = false
	t.max_hp = 1e9
	t.hp = 1e9
	t.global_position = pos
	world.add_child(t)
	return t

func _ready():
	var world = Node2D.new()
	add_child(world)
	var pool = ProjectileBatchPoolScript.new(16)
	world.add_child(pool)

	# --- 1: a Vampiric shot fired AWAY from a target rotates toward it ---
	var target = _make_target(world, Vector2(500, 0))
	pool.register_target(target)
	# Fired straight UP (0,-1) - target is due EAST, about as far from the
	# shot's own heading as this scenario can put it, so any real steering
	# reads unambiguously.
	var vamp_i = pool.spawn(Vector2.ZERO, Vector2.UP, 100.0, 1.0, 5.0, 10.0, Color.WHITE, 1.0, true, null,
		EnergyPacket.SynergyType.VAMPIRIC, {EnergyPacket.SynergyType.VAMPIRIC: 1.0})
	var start_dir = pool._direction[vamp_i]
	for tick in range(30):
		pool._step_simulate(1.0 / 60.0)
	var end_dir = pool._direction[vamp_i]
	var angle_turned = abs(start_dir.angle_to(end_dir))
	_check("a full-Vampiric shot fired away from a live target measurably turns toward it over 30 ticks (turned %.1f degrees)" % rad_to_deg(angle_turned),
		angle_turned > deg_to_rad(10.0))
	var dir_to_target = (target.global_position - pool._position[vamp_i]).normalized()
	_check("after turning, the shot's direction is noticeably closer to pointing at the target than its original heading was",
		end_dir.angle_to(dir_to_target) < start_dir.angle_to(dir_to_target))
	pool.despawn(vamp_i)

	# --- 2: a shot with no real Vampiric ratio never homes, even with the
	# same target adjacent (regression guard - every other synergy-only
	# shot must keep flying straight/undistorted by target position) ---
	var plain_i = pool.spawn(Vector2.ZERO, Vector2.UP, 100.0, 1.0, 5.0, 10.0, Color.WHITE, 1.0, true, null)
	var plain_start_dir = pool._direction[plain_i]
	for tick in range(30):
		pool._step_simulate(1.0 / 60.0)
	var plain_turned = abs(plain_start_dir.angle_to(pool._direction[plain_i]))
	_check("a shot with zero Vampiric ratio never homes toward the target (turned only %.2f degrees, expect ~0)" % rad_to_deg(plain_turned),
		plain_turned < deg_to_rad(1.0))
	pool.despawn(plain_i)
	pool.unregister_target(target)

	# --- 3: a Vampiric shot with no target within its own acquire range
	# doesn't home either (falls back to normal flight) ---
	var far_target = _make_target(world, Vector2(100000, 100000))
	pool.register_target(far_target)
	var out_of_range_i = pool.spawn(Vector2.ZERO, Vector2.UP, 100.0, 1.0, 5.0, 10.0, Color.WHITE, 1.0, true, null,
		EnergyPacket.SynergyType.VAMPIRIC, {EnergyPacket.SynergyType.VAMPIRIC: 1.0})
	var oor_start_dir = pool._direction[out_of_range_i]
	for tick in range(30):
		pool._step_simulate(1.0 / 60.0)
	var oor_turned = abs(oor_start_dir.angle_to(pool._direction[out_of_range_i]))
	_check("a Vampiric shot with no target within acquire range doesn't home (turned only %.2f degrees, expect ~0)" % rad_to_deg(oor_turned),
		oor_turned < deg_to_rad(1.0))
	pool.despawn(out_of_range_i)
	pool.unregister_target(far_target)

	if failures == 0:
		print("PASS: Vampiric shots genuinely home toward the nearest live target within range, and never distort flight without real ratio or a target to chase")
	get_tree().quit(0 if failures == 0 else 1)
