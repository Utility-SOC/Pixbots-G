extends Node

# Phase 2 of the batch-pool full-parity plan (2026-08-10): Lightning's
# actual teleport-hop mechanic. Previously the batch pool only reproduced
# the COSMETIC jagged zig-zag visual offset (real shared Rust math) - the
# gameplay-defining part of Lightning's identity, a periodic teleport-hop
# toward the nearest target every BLINK_INTERVAL, was entirely absent.
# Confirms: a shot with no target in range never hops, a shot within range
# teleports (moves far more than speed*delta could account for) once its
# blink timer expires, a zero/low Lightning-ratio shot never hops at all,
# and the hop distance scales with the Lightning ratio like the real
# system's `hop = to_target * min(1.0, r_ltg)`.

const ProjectileBatchPoolScript = preload("res://scripts/entities/ProjectileBatchPool.gd")
const ProjectileScript = preload("res://scripts/entities/Projectile.gd")
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

	# --- 1: no target in range at all -> never hops, just drifts normally ---
	var far_target = _make_target(world, Vector2(10000, 10000))
	pool.register_target(far_target)
	var out_of_range_i = pool.spawn(Vector2.ZERO, Vector2.RIGHT, 50.0, 1.0, 5.0, 10.0, Color.WHITE, 1.0, true, null,
		EnergyPacket.SynergyType.LIGHTNING, {EnergyPacket.SynergyType.LIGHTNING: 1.0})
	_check("full-Lightning ratio grants hops_left (4 at full ratio, Projectile.gd's own round(4.0*r_ltg))",
		pool._hops_left[out_of_range_i] == 4)
	for tick in range(20): # well past BLINK_INTERVAL (0.11s) at 1/60s steps
		pool._step_simulate(1.0 / 60.0)
	var drifted_dist = pool._position[out_of_range_i].distance_to(Vector2.ZERO)
	_check("with no target within BLINK_ACQUIRE_RANGE, the shot never teleports - it just drifts at normal speed (dist=%.1f, expect ~%.1f)" % [drifted_dist, 50.0 * 20.0 / 60.0],
		abs(drifted_dist - (50.0 * 20.0 / 60.0)) < 2.0)
	pool.despawn(out_of_range_i)
	pool.unregister_target(far_target)

	# --- 2: a target within BLINK_ACQUIRE_RANGE (420px default) -> hops ---
	var near_target = _make_target(world, Vector2(300, 0))
	pool.register_target(near_target)
	var near_i = pool.spawn(Vector2.ZERO, Vector2.RIGHT, 50.0, 1.0, 5.0, 10.0, Color.WHITE, 1.0, true, null,
		EnergyPacket.SynergyType.LIGHTNING, {EnergyPacket.SynergyType.LIGHTNING: 1.0})
	# One tick alone won't hop yet (blink_timer starts at 0.0, but the first
	# _step_blink_hops call itself sets the timer THEN checks - matches
	# Projectile._update_blink's own "decrement, if still >0 return, else
	# reset timer and act" ordering, so the very first eligible tick DOES
	# act immediately since 0.0 - delta <= 0.0).
	pool._step_simulate(1.0 / 60.0)
	var hop_dist = pool._position[near_i].distance_to(Vector2.ZERO)
	_check("a full-Lightning shot with a target within range teleports far more than speed*delta could ever cover in one tick (dist=%.1f, speed*delta~=%.2f)" % [hop_dist, 50.0 / 60.0],
		hop_dist > 50.0)
	_check("full Lightning ratio (r_ltg=1.0) hops the FULL remaining distance (min(1.0, r_ltg)=1.0) - lands ~on the target",
		pool._position[near_i].distance_to(Vector2(300, 0)) < 5.0)
	pool.despawn(near_i)
	pool.unregister_target(near_target)

	# --- 3: a partial Lightning ratio hops only a fraction of the distance ---
	var partial_target = _make_target(world, Vector2(300, 0))
	pool.register_target(partial_target)
	var partial_i = pool.spawn(Vector2.ZERO, Vector2.RIGHT, 0.0, 1.0, 5.0, 10.0, Color.WHITE, 1.0, true, null,
		EnergyPacket.SynergyType.LIGHTNING, {EnergyPacket.SynergyType.LIGHTNING: 0.5, EnergyPacket.SynergyType.KINETIC: 0.5})
	pool._step_simulate(1.0 / 60.0)
	var partial_hop_dist = pool._position[partial_i].distance_to(Vector2.ZERO)
	_check("a 0.5-ratio Lightning shot hops roughly half the distance to its target (got %.1f, expect ~150)" % partial_hop_dist,
		abs(partial_hop_dist - 150.0) < 10.0)
	pool.despawn(partial_i)
	pool.unregister_target(partial_target)

	# --- 4: a shot with no real Lightning ratio never hops, even with a
	# target right next to it ---
	var no_ltg_target = _make_target(world, Vector2(50, 0))
	pool.register_target(no_ltg_target)
	var no_ltg_i = pool.spawn(Vector2.ZERO, Vector2.RIGHT, 10.0, 1.0, 5.0, 10.0, Color.WHITE, 1.0, true, null)
	_check("a shot with zero Lightning ratio gets zero hops_left",
		pool._hops_left[no_ltg_i] == 0)
	pool._step_simulate(1.0 / 60.0)
	_check("a shot with zero Lightning ratio never teleports even with a target adjacent (moves only speed*delta)",
		abs(pool._position[no_ltg_i].distance_to(Vector2.ZERO) - (10.0 / 60.0)) < 0.5)
	pool.despawn(no_ltg_i)
	pool.unregister_target(no_ltg_target)

	if failures == 0:
		print("PASS: Lightning shots actually teleport-hop toward the nearest live target, scaled by ratio, and never hop without a real Lightning ratio or a target in range")
	get_tree().quit(0 if failures == 0 else 1)
