extends Node

# Regression check for B2 of this session's batch-pool visual/movement
# parity plan: ProjectileBatchPool._step_hit_test used to hardcode "RAW" as
# the damage element (bypassing all elemental resistance) and always
# despawned on first hit (no pierce, no dedup). Confirms the fix: real
# resistance now applies, pierce shots survive multiple hits, and a shot
# never double-hits the same target across repeated _step_hit_test calls.

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
	t.max_hp = 100000.0
	t.hp = 100000.0
	t.global_position = pos
	world.add_child(t)
	# Phase 11 of the batch-pool full-parity plan (2026-08-10) added part-
	# hitbox damage routing: a target with real components now only takes
	# ~20% of a hit on its global hp (the rest lands on structural tile hp
	# instead - see ProjectileBatchPool._apply_damage_to_target). This
	# check's whole purpose is verifying resistance/pierce/dedup math
	# against exact hp deltas, which is a property independent of THAT
	# routing (its own dedicated coverage lives in
	# BatchPoolPartDamageRoutingCheck.gd) - clearing components after
	# _ready() has already built them forces the plain apply_damage
	# fallback, keeping this check's original exact-magnitude assertions
	# meaningful without needing to guess at a random tile-damage split.
	t.components.clear()
	return t

func _ready():
	var world = Node2D.new()
	add_child(world)
	var pool = ProjectileBatchPoolScript.new(16)
	world.add_child(pool)

	# --- 1: elemental resistance actually reduces applied damage now ---
	var resisted = _make_target(world, Vector2(300, 0))
	resisted.elemental_resistances["FIRE"] = 0.25 # takes only 25% damage from FIRE
	pool.register_target(resisted)
	var i_fire = pool.spawn(Vector2(295, 0), Vector2.RIGHT, 10.0, 1000.0, 20.0, 5.0, Color.ORANGE, 1.0, true, null,
		EnergyPacket.SynergyType.FIRE, {EnergyPacket.SynergyType.FIRE: 1.0})
	pool._step_hit_test()
	var resisted_damage = resisted.max_hp - resisted.hp
	pool.unregister_target(resisted)

	var unresisted = _make_target(world, Vector2(300, 0))
	pool.register_target(unresisted)
	var i_fire2 = pool.spawn(Vector2(295, 0), Vector2.RIGHT, 10.0, 1000.0, 20.0, 5.0, Color.ORANGE, 1.0, true, null,
		EnergyPacket.SynergyType.FIRE, {EnergyPacket.SynergyType.FIRE: 1.0})
	pool._step_hit_test()
	var unresisted_damage = unresisted.max_hp - unresisted.hp
	pool.unregister_target(unresisted)

	_check("a FIRE batch shot deals full damage to an unresisted target (got %.1f, expect ~1000)" % unresisted_damage,
		abs(unresisted_damage - 1000.0) < 1.0)
	_check("a FIRE batch shot deals reduced damage to a FIRE-resistant target (got %.1f, expect ~250)" % resisted_damage,
		resisted_damage < unresisted_damage * 0.5 and resisted_damage > 0.0)

	# --- 2: a pierce shot survives multiple hits (pierce_count > 1), a
	# non-pierce shot still despawns after exactly one hit ---
	var t_a = _make_target(world, Vector2(500, 0))
	var t_b = _make_target(world, Vector2(500, 40))
	pool.register_target(t_a)
	pool.register_target(t_b)
	# r_prc=1.0 -> pierce_count = 1 + int(4.0*1.0) = 5 (Projectile.gd:599)
	var pierce_i = pool.spawn(Vector2(495, 0), Vector2.RIGHT, 10.0, 10.0, 60.0, 5.0, Color.WHITE, 1.0, true, null,
		EnergyPacket.SynergyType.PIERCE, {EnergyPacket.SynergyType.PIERCE: 1.0})
	_check("pierce ratio 1.0 grants pierce_count 5 at spawn (Projectile.gd's own formula)",
		pool._pierce_count[pierce_i] == 5)
	pool._step_hit_test() # hits t_a (in radius) this tick
	_check("a pierce shot survives its first hit instead of despawning immediately",
		pool._alive[pierce_i] == 1 and pool._pierce_count[pierce_i] == 4)
	pool.unregister_target(t_a)
	pool.unregister_target(t_b)

	var t_c = _make_target(world, Vector2(700, 0))
	pool.register_target(t_c)
	var plain_i = pool.spawn(Vector2(695, 0), Vector2.RIGHT, 10.0, 10.0, 20.0, 5.0, Color.WHITE, 1.0, true, null)
	pool._step_hit_test()
	_check("a non-pierce shot (pierce_count 1) still despawns after exactly one hit",
		pool._alive[plain_i] == 0)
	pool.unregister_target(t_c)

	# --- 3: dedup - a still-alive shot re-running _step_hit_test against a
	# target it ALREADY hit must not hit it again ---
	var t_d = _make_target(world, Vector2(900, 0))
	pool.register_target(t_d)
	var dedup_i = pool.spawn(Vector2(895, 0), Vector2.RIGHT, 0.0, 10.0, 60.0, 5.0, Color.WHITE, 1.0, true, null,
		EnergyPacket.SynergyType.PIERCE, {EnergyPacket.SynergyType.PIERCE: 1.0}) # speed 0 - stays in range across ticks
	pool._step_hit_test()
	var hp_after_first = t_d.hp
	var pierce_after_first = pool._pierce_count[dedup_i]
	pool._step_hit_test() # same target, still in range, same tick-equivalent call again
	_check("re-running hit-test against the same still-in-range target does not double-hit it",
		t_d.hp == hp_after_first and pool._pierce_count[dedup_i] == pierce_after_first)
	pool.unregister_target(t_d)

	if failures == 0:
		print("PASS: ProjectileBatchPool hit pipeline applies real elemental resistance, honors pierce_count, and never double-hits a target")
	get_tree().quit(0 if failures == 0 else 1)
