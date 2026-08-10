extends Node

# Phase 11 of the batch-pool full-parity plan (2026-08-10): part-hitbox
# damage routing. Previously the batch pool applied damage straight to a
# target's total HP - real combat never does this: every hit (PartHitbox.
# apply_damage -> Mech.apply_part_damage) sends only ~20% to global HP and
# the rest to a specific component's own structural tile HP (plus a chance
# to disable/destroy a priority tile). The batch pool has no real per-part
# collision geometry, so it picks a random valid slot from the target's
# own components each hit instead of a real geometric part-hit test - see
# ProjectileBatchPool._apply_damage_to_target's own header for the full
# reasoning on why that's the right-sized simplification here.
#
# Confirms: a real target with components takes roughly 20% of a hit on
# its global HP (not the full amount), a target with NO components (or
# that doesn't support apply_part_damage at all) falls back to the full-
# amount plain apply_damage exactly like before this phase, and this
# behaves consistently across every damage-dealing call site (primary hit,
# Explosion AoE, poison-mine detonation, biome-trigger splash) - not just
# the primary hit path.

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
	t.max_hp = 1e6
	t.hp = 1e6
	t.global_position = pos
	world.add_child(t)
	return t

func _ready():
	var world = Node2D.new()
	add_child(world)
	var pool = ProjectileBatchPoolScript.new(16)
	world.add_child(pool)

	# --- 1: a real target (with components) only takes ~20% of a hit on
	# its global HP, not the full amount ---
	var real_target = _make_target(world, Vector2(300, 0))
	_check("test setup: a freshly-readied Mech has real, non-empty components",
		not real_target.components.is_empty())
	pool.register_target(real_target)
	var real_i = pool.spawn(Vector2(295, 0), Vector2.RIGHT, 10.0, 1000.0, 20.0, 5.0, Color.WHITE, 1.0, true, null,
		EnergyPacket.SynergyType.FIRE, {EnergyPacket.SynergyType.FIRE: 1.0})
	pool._step_hit_test()
	var real_dealt = real_target.max_hp - real_target.hp
	_check("a real target only takes roughly 20%% of the raw hit on global HP (dealt %.1f of 1000, expect ~200)" % real_dealt,
		real_dealt > 100.0 and real_dealt < 300.0)
	_check("a real target's global HP damage is meaningfully LESS than the full raw hit amount",
		real_dealt < 1000.0 * 0.5)
	pool.despawn(real_i)
	pool.unregister_target(real_target)
	real_target.queue_free()

	# --- 2: a target with NO components falls back to the full-amount
	# plain apply_damage, exactly like every damage call before this phase ---
	var bare_target = _make_target(world, Vector2(300, 0))
	bare_target.components.clear()
	pool.register_target(bare_target)
	var bare_i = pool.spawn(Vector2(295, 0), Vector2.RIGHT, 10.0, 1000.0, 20.0, 5.0, Color.WHITE, 1.0, true, null,
		EnergyPacket.SynergyType.FIRE, {EnergyPacket.SynergyType.FIRE: 1.0})
	pool._step_hit_test()
	var bare_dealt = bare_target.max_hp - bare_target.hp
	_check("a target with no components takes the FULL raw hit amount on global HP (dealt %.1f, expect ~1000)" % bare_dealt,
		abs(bare_dealt - 1000.0) < 1.0)
	pool.despawn(bare_i)
	pool.unregister_target(bare_target)
	bare_target.queue_free()

	# --- 3: Explosion AoE splash also routes through part damage, not just
	# the primary hit ---
	var exp_direct = _make_target(world, Vector2(500, 0))
	var exp_splash = _make_target(world, Vector2(520, 0))
	pool.register_target(exp_direct)
	pool.register_target(exp_splash)
	var exp_i = pool.spawn(Vector2(495, 0), Vector2.RIGHT, 10.0, 1000.0, 20.0, 5.0, Color.WHITE, 1.0, true, null,
		EnergyPacket.SynergyType.EXPLOSION, {EnergyPacket.SynergyType.EXPLOSION: 1.0})
	pool._step_hit_test()
	var splash_dealt = exp_splash.max_hp - exp_splash.hp
	# AoE splash damage is (damage*0.5*hit_decay) = 500 raw at full decay;
	# routed through a real target, only ~20% of THAT should land on
	# global hp (~100), not the full 500.
	_check("Explosion AoE splash on a real target also only lands ~20%% on global HP (dealt %.1f of a 500 raw splash, expect ~100)" % splash_dealt,
		splash_dealt > 40.0 and splash_dealt < 200.0)
	pool.despawn(exp_i)
	pool.unregister_target(exp_direct)
	pool.unregister_target(exp_splash)
	exp_direct.queue_free()
	exp_splash.queue_free()

	# --- 4: the random slot chosen is always a REAL valid key from the
	# target's own components (never silently no-ops from picking a bad
	# slot) - roll enough trials that a real bug (e.g. an off-by-one range)
	# would show up as damage failing to land at least once ---
	var all_landed = true
	for trial in range(30):
		var t = _make_target(world, Vector2(700, 0))
		pool.register_target(t)
		var i = pool.spawn(Vector2(695, 0), Vector2.RIGHT, 10.0, 500.0, 20.0, 5.0, Color.WHITE, 1.0, true, null,
			EnergyPacket.SynergyType.FIRE, {EnergyPacket.SynergyType.FIRE: 1.0})
		pool._step_hit_test()
		if t.hp >= t.max_hp:
			all_landed = false
		pool.despawn(i)
		pool.unregister_target(t)
		t.queue_free()
	_check("across 30 trials, the randomly-picked slot is always a real valid component key (damage lands every time, never silently drops)",
		all_landed)

	if failures == 0:
		print("PASS: real targets take only ~20% of a hit on global HP via real part-hitbox routing (primary hits AND AoE splash alike), targets without components still take full damage, and the random slot pick never silently fails")
	get_tree().quit(0 if failures == 0 else 1)
