extends Node

# Phases 5+6+7 of the batch-pool full-parity plan (2026-08-10): hit-pipeline
# effects landed together since they're all edits to the same on-hit block
# (_step_hit_test) - Concussed proc (Phase 5), Vampiric Heal + hit_decay
# tapering + the Lightning re-target chain (Phase 6), Explosion AoE splash
# (Phase 7), and Resonator Sync proc_synergies (Phase 5). All previously
# entirely absent: the batch pool's status-effect subset skipped Concussed
# outright (Explosion ratio wasn't even tracked per-slot), and anything
# that reached beyond the single hit target (heal the shooter, splash
# nearby targets) was explicitly out of scope until now.

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

	# --- 1: Concussed proc (Phase 5) - roll enough times to be confident
	# it's actually reachable, not just theoretically present in the table ---
	var concussed_ever = false
	for trial in range(200):
		var t = _make_target(world, Vector2(300, 0))
		pool.register_target(t)
		var i = pool.spawn(Vector2(295, 0), Vector2.RIGHT, 10.0, 5.0, 20.0, 5.0, Color.WHITE, 1.0, true, null,
			EnergyPacket.SynergyType.EXPLOSION, {EnergyPacket.SynergyType.EXPLOSION: 1.0})
		pool._step_hit_test()
		if t.status_effects.get("concussed", 0.0) > 0.0:
			concussed_ever = true
		pool.despawn(i)
		pool.unregister_target(t)
		t.queue_free()
		if concussed_ever:
			break
	_check("a full-Explosion-ratio shot can proc Concussed on hit (200-trial roll, 0.5*re=50% chance/hit)",
		concussed_ever)

	# --- 2: Vampiric Heal - heals the SHOOTER (a registered "player" group
	# member), not the hit target ---
	var shooter = MechScript.new()
	shooter.is_player = true
	shooter.max_hp = 1000.0
	shooter.hp = 500.0 # damaged, so healing is observable
	world.add_child(shooter)
	# Mech.gd itself never add_to_group("player")s the player Mech (only
	# "enemy" for non-player ones, confirmed by direct read) - real
	# gameplay's actual player-spawn flow does this; this test has to do it
	# itself since it isn't going through that flow.
	shooter.add_to_group("player")
	var heal_target = _make_target(world, Vector2(300, 0))
	pool.register_target(heal_target)
	var vamp_i = pool.spawn(Vector2(295, 0), Vector2.RIGHT, 10.0, 1000.0, 20.0, 5.0, Color.WHITE, 1.0, true, null,
		EnergyPacket.SynergyType.VAMPIRIC, {EnergyPacket.SynergyType.VAMPIRIC: 1.0})
	pool._step_hit_test()
	_check("a Vampiric hit heals the shooter (registered player-group member), not the target it hit (hp went from 500 to %.1f)" % shooter.hp,
		shooter.hp > 500.0)
	pool.despawn(vamp_i)
	pool.unregister_target(heal_target)
	heal_target.queue_free()

	# --- 3: Explosion AoE - a hit on target A splashes target B nearby ---
	var exp_a = _make_target(world, Vector2(500, 0))
	var exp_b = _make_target(world, Vector2(520, 0)) # close enough to be inside a real Explosion radius
	pool.register_target(exp_a)
	pool.register_target(exp_b)
	var exp_i = pool.spawn(Vector2(495, 0), Vector2.RIGHT, 10.0, 1000.0, 20.0, 5.0, Color.WHITE, 1.0, true, null,
		EnergyPacket.SynergyType.EXPLOSION, {EnergyPacket.SynergyType.EXPLOSION: 1.0})
	var b_hp_before = exp_b.hp
	pool._step_hit_test()
	_check("an Explosion hit on target A also splashes nearby target B (B's hp dropped from %.0f to %.0f)" % [b_hp_before, exp_b.hp],
		exp_b.hp < b_hp_before)
	pool.despawn(exp_i)
	pool.unregister_target(exp_a)
	pool.unregister_target(exp_b)
	exp_a.queue_free()
	exp_b.queue_free()

	# --- 4: a non-Explosion hit never splashes a nearby target (regression
	# guard) ---
	var plain_a = _make_target(world, Vector2(700, 0))
	var plain_b = _make_target(world, Vector2(720, 0))
	pool.register_target(plain_a)
	pool.register_target(plain_b)
	var plain_i = pool.spawn(Vector2(695, 0), Vector2.RIGHT, 10.0, 1000.0, 20.0, 5.0, Color.WHITE, 1.0, true, null,
		EnergyPacket.SynergyType.FIRE, {EnergyPacket.SynergyType.FIRE: 1.0})
	var plain_b_hp_before = plain_b.hp
	pool._step_hit_test()
	_check("a non-Explosion hit never splashes a nearby target",
		plain_b.hp == plain_b_hp_before)
	pool.despawn(plain_i)
	pool.unregister_target(plain_a)
	pool.unregister_target(plain_b)
	plain_a.queue_free()
	plain_b.queue_free()

	# --- 5: Lightning re-target chain - a full-Lightning shot survives its
	# first hit and re-targets to a second registered target instead of
	# despawning, hops_left decrementing correctly ---
	var ltg_a = _make_target(world, Vector2(900, 0))
	var ltg_b = _make_target(world, Vector2(950, 0))
	pool.register_target(ltg_a)
	pool.register_target(ltg_b)
	var ltg_i = pool.spawn(Vector2(895, 0), Vector2.RIGHT, 0.0, 10.0, 60.0, 5.0, Color.WHITE, 1.0, true, null,
		EnergyPacket.SynergyType.LIGHTNING, {EnergyPacket.SynergyType.LIGHTNING: 1.0})
	var hops_before = pool._hops_left[ltg_i]
	pool._step_hit_test() # hits ltg_a (in radius) this tick
	_check("a Lightning shot survives its first hit instead of despawning (hops_left was %d, now %d, still alive=%s)" % [hops_before, pool._hops_left[ltg_i], pool._alive[ltg_i] == 1],
		pool._alive[ltg_i] == 1 and pool._hops_left[ltg_i] == hops_before - 1)
	_check("the blink timer resets to 0 on re-target, forcing an immediate re-hop next tick",
		pool._blink_timer[ltg_i] == 0.0)
	# Step simulate + blink hop toward the second target now that the timer
	# is zeroed, then hit-test again - should hit ltg_b next.
	pool._step_simulate(1.0 / 60.0)
	pool._step_hit_test()
	_check("after re-hopping, the SAME shot goes on to hit the second target too",
		pool._handled_targets[ltg_i].has(ltg_b.get_instance_id()))
	pool.despawn(ltg_i)
	pool.unregister_target(ltg_a)
	pool.unregister_target(ltg_b)
	ltg_a.queue_free()
	ltg_b.queue_free()

	# --- 6: Resonator Sync proc_synergies - a packet with ZERO real
	# elemental ratio but a proc_synergies entry still applies that status ---
	var proc_target = _make_target(world, Vector2(1100, 0))
	pool.register_target(proc_target)
	var proc_i = pool.spawn(Vector2(1095, 0), Vector2.RIGHT, 10.0, 5.0, 20.0, 5.0, Color.WHITE, 1.0, true, null,
		0, {}, {EnergyPacket.SynergyType.ICE: 1.0}) # no real ratios at all, only a proc
	pool._step_hit_test()
	_check("a packet with zero real ratios but a proc_synergies entry still applies that status (Frozen from a proc'd ICE)",
		proc_target.status_effects.get("frozen", 0.0) > 0.0)
	pool.despawn(proc_i)
	pool.unregister_target(proc_target)
	proc_target.queue_free()

	if failures == 0:
		print("PASS: Concussed procs, Vampiric Heal targets the shooter, Explosion AoE splashes nearby targets (and only Explosion), Lightning shots survive to re-target a second victim, and Resonator Sync proc_synergies apply independently of real ratios")
	get_tree().quit(0 if failures == 0 else 1)
