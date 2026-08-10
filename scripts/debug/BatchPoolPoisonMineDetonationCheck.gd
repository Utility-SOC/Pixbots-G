extends Node

# Phase 8 of the batch-pool full-parity plan (2026-08-10): Poison-mine
# detonation. Previously a mine slot (Phase 3's crawl-only movement mode)
# just silently vanished on contact or expiry with no AoE burst at all -
# the real system's whole point of a mine ("no gravity lob... a straight
# crawl... until it hits something or its lifetime Timer calls _expire()")
# was only half-ported: the movement half, not the payload half.
#
# Confirms: a mine that contacts a target detonates on contact (AoE damage
# to nearby targets, themed status effect), a mine that never contacts
# anything still detonates when its lifetime/range runs out instead of
# silently vanishing, and a mine never detonates twice regardless of which
# trigger (contact vs expiry) fires first.

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

	# --- 1: contact detonation - a Poison+Fire mine (Fire is the strongest
	# non-Poison/Kinetic/RAW ratio, so it should theme as Fire: "burning") ---
	var direct = _make_target(world, Vector2(300, 0))
	var nearby = _make_target(world, Vector2(340, 0)) # inside the 220px detonation radius
	pool.register_target(direct)
	pool.register_target(nearby)
	var mine_i = pool.spawn(Vector2(300, 0), Vector2.RIGHT, 0.0, 10.0, 20.0, 10.0, Color.WHITE, 1.0, true, null,
		EnergyPacket.SynergyType.POISON, {EnergyPacket.SynergyType.POISON: 0.5, EnergyPacket.SynergyType.FIRE: 0.3})
	_check("a Poison+Fire ratio spawns as a real mine", pool._is_mine[mine_i] == 1)
	var nearby_hp_before = nearby.hp
	pool._step_hit_test() # direct is at the exact same position - contact
	_check("contact detonates the mine (_mine_detonated set)", pool._mine_detonated[mine_i] == 1)
	_check("contact detonation splashes a nearby target too, not just the direct hit (nearby hp dropped from %.0f to %.0f)" % [nearby_hp_before, nearby.hp],
		nearby.hp < nearby_hp_before)
	_check("contact detonation themes its status effect by the strongest non-Poison/Kinetic ratio (Fire -> burning)",
		nearby.status_effects.get("burning", 0.0) > 0.0)
	_check("the mine slot is consumed (despawned) by contact detonation, not left alive to pierce through",
		pool._alive[mine_i] == 0)
	pool.unregister_target(direct)
	pool.unregister_target(nearby)
	direct.queue_free()
	nearby.queue_free()

	# --- 2: expiry detonation - a mine that NEVER contacts anything still
	# detonates when its lifetime runs out, not silently despawning ---
	var far_target = _make_target(world, Vector2(500, 500)) # far from the mine's own position, never contacted directly
	var expiry_splash_target = _make_target(world, Vector2(1005, 1005)) # near where the mine WILL be sitting
	pool.register_target(far_target)
	pool.register_target(expiry_splash_target)
	var expiry_i = pool.spawn(Vector2(1000, 1000), Vector2.RIGHT, 0.0, 10.0, 5.0, 0.2, Color.WHITE, 1.0, true, null,
		EnergyPacket.SynergyType.POISON, {EnergyPacket.SynergyType.POISON: 0.5}) # short lifetime, no Kinetic so it never moves
	var splash_hp_before = expiry_splash_target.hp
	# Step past the 0.2s lifetime - the lifetime-expiry pre-pass in
	# _step_simulate should trigger detonation-on-timeout, not just despawn.
	for tick in range(20):
		pool._step_simulate(1.0 / 60.0)
	_check("a mine that runs out of lifetime without ever being contacted still detonates (_mine_detonated set)",
		pool._mine_detonated[expiry_i] == 1)
	_check("expiry detonation splashes nearby targets just like contact detonation would (hp dropped from %.0f to %.0f)" % [splash_hp_before, expiry_splash_target.hp],
		expiry_splash_target.hp < splash_hp_before)
	pool.unregister_target(far_target)
	pool.unregister_target(expiry_splash_target)
	far_target.queue_free()
	expiry_splash_target.queue_free()

	# --- 3: never detonates twice - contact then a later expiry check
	# (simulated directly) must not double-fire ---
	var guard_target = _make_target(world, Vector2(1300, 0))
	pool.register_target(guard_target)
	var guard_i = pool.spawn(Vector2(1300, 0), Vector2.RIGHT, 0.0, 10.0, 20.0, 10.0, Color.WHITE, 1.0, true, null,
		EnergyPacket.SynergyType.POISON, {EnergyPacket.SynergyType.POISON: 0.5})
	pool._step_hit_test() # detonates on contact, despawns the slot
	_check("guard test setup: contact detonation fired once", pool._mine_detonated[guard_i] == 1)
	# Calling the detonation function again directly (simulating a second
	# trigger racing in) must be a hard no-op - the function itself checks
	# _mine_detonated, this proves the guard actually works, not just that
	# it happens to only be called once in practice.
	var hp_after_first_detonation = guard_target.hp
	pool._trigger_poison_mine_detonation(guard_i)
	_check("calling the detonation function again is a guaranteed no-op (guard checked, not just 'happens to only be called once')",
		guard_target.hp == hp_after_first_detonation)
	pool.unregister_target(guard_target)
	guard_target.queue_free()

	if failures == 0:
		print("PASS: Poison mines detonate with a real themed AoE burst on contact, still detonate on expiry instead of vanishing silently, and never detonate twice")
	get_tree().quit(0 if failures == 0 else 1)
