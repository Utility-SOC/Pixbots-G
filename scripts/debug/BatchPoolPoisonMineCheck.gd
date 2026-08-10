extends Node

# Phase 3 of the batch-pool full-parity plan (2026-08-10): Poison's mine-
# crawl movement mode. Previously the batch pool had no mine concept at
# all - every Poison-ratio shot always used the normal (Rust-driven)
# flight path regardless of ratio, when the real system switches to an
# entirely different movement model (stationary/crawling, bypasses every
# other synergy's flight distortion) once poison_ratio > MINE_POISON_
# THRESHOLD.
#
# Confirms: a high-Poison shot is correctly flagged _is_mine and crawls at
# exactly MINE_CRAWL_SPEED*r_kin (a dead stop with zero Kinetic - "a mine,"
# not "a projectile that happens to be slow"), a below-threshold Poison
# shot is NOT flagged and still moves through the normal Rust-driven path
# unaffected (regression guard against the mine-partition change leaking
# into ordinary shots), and a Poison+Lightning mine never blink-hops even
# though it has real hops_left (mine mode fully bypasses blink, matching
# the real system's own early-return ordering).

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
	var world = Node2D.new()
	add_child(world)
	var pool = ProjectileBatchPoolScript.new(16)
	world.add_child(pool)

	# --- 1: above-threshold Poison ratio -> flagged as a mine ---
	var mine_i = pool.spawn(Vector2.ZERO, Vector2.RIGHT, 500.0, 1.0, 5.0, 10.0, Color.WHITE, 1.0, true, null,
		EnergyPacket.SynergyType.POISON, {EnergyPacket.SynergyType.POISON: 0.5})
	_check("a Poison ratio above MINE_POISON_THRESHOLD (0.15) is flagged as a mine",
		pool._is_mine[mine_i] == 1)

	# --- 2: zero Kinetic -> a dead-stop stationary mine, NOT moving at the
	# shot's own high `speed` (500.0 passed to spawn - a mine must ignore
	# this entirely, per the real system's own "or a dead stop with no
	# KINETIC" framing) ---
	pool._step_simulate(1.0 / 60.0)
	_check("a zero-Kinetic mine is a genuine dead stop (doesn't move at all), not a slow-moving projectile using its passed-in speed",
		pool._position[mine_i].distance_to(Vector2.ZERO) < 0.001)
	pool.despawn(mine_i)

	# --- 3: real Kinetic ratio -> crawls at exactly MINE_CRAWL_SPEED*r_kin,
	# not the shot's own `speed` field ---
	var crawl_i = pool.spawn(Vector2.ZERO, Vector2.RIGHT, 999999.0, 1.0, 5.0, 10.0, Color.WHITE, 1.0, true, null,
		EnergyPacket.SynergyType.POISON, {EnergyPacket.SynergyType.POISON: 0.5, EnergyPacket.SynergyType.KINETIC: 0.5})
	pool._step_simulate(1.0 / 60.0)
	var expected_crawl = ProjectileScript.MINE_CRAWL_SPEED * 0.5 * (1.0 / 60.0)
	_check("a 0.5-Kinetic mine crawls at MINE_CRAWL_SPEED*r_kin (expected ~%.3f, got %.3f), completely ignoring its own absurd `speed` field" % [expected_crawl, pool._position[crawl_i].x],
		abs(pool._position[crawl_i].x - expected_crawl) < 0.01)
	pool.despawn(crawl_i)

	# --- 4: a Poison+Lightning mine has real hops_left but NEVER blink-hops -
	# mine mode fully bypasses blink, matching the real system's early-
	# return ordering (Projectile.gd:1247-1249 returns before _update_blink
	# is ever reached) ---
	var target = _make_target(world, Vector2(50, 0))
	pool.register_target(target)
	var mine_ltg_i = pool.spawn(Vector2.ZERO, Vector2.RIGHT, 0.0, 1.0, 5.0, 10.0, Color.WHITE, 1.0, true, null,
		EnergyPacket.SynergyType.POISON, {EnergyPacket.SynergyType.POISON: 0.5, EnergyPacket.SynergyType.LIGHTNING: 1.0})
	_check("a Poison+Lightning mine still gets real hops_left derived from its Lightning ratio",
		pool._hops_left[mine_ltg_i] > 0)
	for tick in range(10):
		pool._step_simulate(1.0 / 60.0)
	_check("but a mine never actually blink-hops even with a target adjacent and real hops_left (stays at/near origin, doesn't teleport onto the target)",
		pool._position[mine_ltg_i].distance_to(Vector2(50, 0)) > 10.0)
	pool.despawn(mine_ltg_i)
	pool.unregister_target(target)

	# --- 5: below-threshold Poison ratio -> NOT a mine, still moves through
	# the normal Rust-driven path at its real speed (regression guard) ---
	var normal_i = pool.spawn(Vector2.ZERO, Vector2.RIGHT, 500.0, 1.0, 5.0, 10.0, Color.WHITE, 1.0, true, null,
		EnergyPacket.SynergyType.POISON, {EnergyPacket.SynergyType.POISON: 0.1}) # below MINE_POISON_THRESHOLD=0.15
	_check("a Poison ratio below MINE_POISON_THRESHOLD is NOT flagged as a mine",
		pool._is_mine[normal_i] == 0)
	pool._step_simulate(1.0 / 60.0)
	_check("a below-threshold Poison shot still moves through the normal (non-mine) path, not frozen/crawling",
		pool._position[normal_i].x > 1.0)
	pool.despawn(normal_i)

	if failures == 0:
		print("PASS: Poison mines correctly switch to crawl-only movement (ignoring their own speed field), never blink-hop even with real Lightning ratio, and below-threshold Poison shots are unaffected")
	get_tree().quit(0 if failures == 0 else 1)

func _make_target(world: Node, pos: Vector2) -> Node:
	var t = preload("res://scripts/entities/Mech.gd").new()
	t.is_player = false
	t.max_hp = 1e9
	t.hp = 1e9
	t.global_position = pos
	world.add_child(t)
	return t
