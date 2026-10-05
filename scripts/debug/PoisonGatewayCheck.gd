extends Node

# Poison is the gateway to mines/turrets. A mine whose only added element is
# Fire (a sustain element) is all emitter -> MineEmitter damaging a target over
# time (no named recipe: see Projectile.mine_profile); Poison+Explosion mine -> larger blast
# than the plain 220px mine + a poison ElementalPuddle left behind.

const PoolScript = preload("res://scripts/entities/ProjectileBatchPool.gd")
const MineEmitterScript = preload("res://scripts/attacks/MineEmitter.gd")

class Dummy extends CharacterBody2D:
	var hp := 0.0
	var statuses := []
	var is_dead := false
	func apply_damage(amount, _el = "RAW", _src = null, _r = false, _l = ""):
		hp += amount
	func apply_status(n, _d):
		statuses.append(n)

func _make_dummy(world, pos) -> Dummy:
	var d = Dummy.new()
	d.collision_layer = 4
	var cs = CollisionShape2D.new()
	var sh = CircleShape2D.new()
	sh.radius = 12.0
	cs.shape = sh
	d.add_child(cs)
	world.add_child(d)
	d.global_position = pos
	return d

func _ready():
	var failures = 0
	var world = Node2D.new()
	add_child(world)
	var pool = PoolScript.new()
	world.add_child(pool)
	var src = Node2D.new()
	world.add_child(src)

	# --- Poison + Fire -> turret -------------------------------------------
	var d1 = _make_dummy(world, Vector2(200, 0))
	var ratios = {EnergyPacket.SynergyType.POISON: 0.5, EnergyPacket.SynergyType.FIRE: 0.5}
	var i = pool.spawn(Vector2.ZERO, Vector2.RIGHT, 0.01, 40.0, 10.0, 100.0, Color.WHITE, 1.0, true, src, EnergyPacket.SynergyType.POISON, ratios)
	pool._trigger_poison_mine_detonation(i)
	var turrets = 0
	for c in world.get_children():
		if c.get_script() == MineEmitterScript:
			turrets += 1
	if turrets != 1:
		push_error("FAIL: expected 1 MineEmitter, got %d" % turrets)
		failures += 1
	for f in range(60): # ~1s of physics
		await get_tree().physics_frame
	if d1.hp <= 0.0 or not d1.statuses.has("burning"):
		push_error("FAIL: turret did not burn the dummy 200px away (hp dmg %f, statuses %s)" % [d1.hp, d1.statuses])
		failures += 1
	else:
		print("1) Poison+Fire mine deploys a flame turret: %.0f damage + burning after 1s" % d1.hp)

	# --- Poison + Explosion -> big blast + poison puddle ---------------------
	var d2 = _make_dummy(world, Vector2(5000, 0)) # 330px from the blast centre: outside 220, inside 374
	d2.global_position = Vector2(5330, 0)
	await get_tree().physics_frame
	var ratios2 = {EnergyPacket.SynergyType.POISON: 0.5, EnergyPacket.SynergyType.EXPLOSION: 0.5}
	var j = pool.spawn(Vector2(5000, 0), Vector2.RIGHT, 0.01, 40.0, 10.0, 100.0, Color.WHITE, 1.0, true, src, EnergyPacket.SynergyType.POISON, ratios2)
	pool.register_target(d2)
	pool._trigger_poison_mine_detonation(j)
	var puddles = get_tree().get_nodes_in_group("missile_puddle").size()
	if d2.hp <= 0.0:
		push_error("FAIL: Poison+Explosion blast did not reach a target 330px away")
		failures += 1
	elif puddles < 1:
		push_error("FAIL: no poison puddle left behind")
		failures += 1
	else:
		print("2) Poison+Explosion mine: large blast reached 330px (%.0f dmg) and left %d poison puddle(s)" % [d2.hp, puddles])

	# --- Emergent: Poison + Vortex + Fire -> pulled (burst) AND flamed (emitter) ----
	var d3 = _make_dummy(world, Vector2(9100, 0))
	var ratios3 = {EnergyPacket.SynergyType.POISON: 0.4, EnergyPacket.SynergyType.VORTEX: 0.3, EnergyPacket.SynergyType.FIRE: 0.3}
	var k = pool.spawn(Vector2(9000, 0), Vector2.RIGHT, 0.01, 40.0, 10.0, 100.0, Color.WHITE, 1.0, true, src, EnergyPacket.SynergyType.POISON, ratios3)
	pool.register_target(d3)
	pool._trigger_poison_mine_detonation(k)
	var turrets_after = 0
	for c in world.get_children():
		if c.get_script() == MineEmitterScript:
			turrets_after += 1
	for f in range(60):
		await get_tree().physics_frame
	if not (d3.statuses.has("vortexed") and d3.statuses.has("burning")) or turrets_after < 2:
		push_error("FAIL: Poison+Vortex+Fire should vortex (burst) AND burn (emitter) (statuses %s, turrets %d)" % [d3.statuses, turrets_after])
		failures += 1
	else:
		print("3) Poison+Vortex+Fire mine: target gets %s from burst + emitter (emergent combo)" % [d3.statuses])

	# --- Kinetic + Pierce mine -> emitter firing one-generation sub-shots -----
	var d4 = _make_dummy(world, Vector2(14400, 0))
	var ratios4 = {EnergyPacket.SynergyType.POISON: 0.4, EnergyPacket.SynergyType.KINETIC: 0.3, EnergyPacket.SynergyType.PIERCE: 0.3}
	var m4 = pool.spawn(Vector2(14000, 0), Vector2.RIGHT, 0.01, 40.0, 10.0, 100.0, Color.WHITE, 1.0, true, src, EnergyPacket.SynergyType.POISON, ratios4)
	pool.register_target(d4)
	var emitters_before = 0
	for c in world.get_children():
		if c.get_script() == MineEmitterScript:
			emitters_before += 1
	pool._trigger_poison_mine_detonation(m4)
	var emitters_after = 0
	for c in world.get_children():
		if c.get_script() == MineEmitterScript:
			emitters_after += 1
	var live_before = pool.live_count()
	for f in range(150): # ~2.5s: expect 3-4 sub-shots
		await get_tree().physics_frame
	var subs = 0
	var sub_mines = 0
	for idx in range(pool._highest_active + 1):
		if pool._alive[idx] == 1 and pool._r_psn[idx] > 0.3 and pool._r_kin[idx] > 0.2 and idx != m4:
			subs += 1
			if pool._is_mine[idx] == 1:
				sub_mines += 1
	var emitters_final = 0
	for c in world.get_children():
		if c.get_script() == MineEmitterScript:
			emitters_final += 1
	if emitters_after != emitters_before + 1 or emitters_final > emitters_after:
		push_error("FAIL: Kinetic+Pierce mine should deploy exactly one emitter and sub-shots must not add more (%d -> %d -> %d)" % [emitters_before, emitters_after, emitters_final])
		failures += 1
	elif d4.hp <= 0.0 and subs == 0:
		push_error("FAIL: emitter fired no sub-shots (dummy hp %f)" % d4.hp)
		failures += 1
	elif sub_mines > 0:
		push_error("FAIL: %d sub-shots became mines (one generation only)" % sub_mines)
		failures += 1
	else:
		print("4) Poison+Kinetic+Pierce mine: 1 emitter, sub-shots carry the mix (%d in flight, dummy took %.0f), none are mines" % [subs, d4.hp])

	# --- Regression: the mine (and its shooter) are freed while the emitter lives -----
	# A lambda capturing the freed projectile crashed the game (signal 11); the emitter
	# must run its full life with no errors after both are gone.
	var shooter = Node2D.new()
	world.add_child(shooter)
	var d5 = _make_dummy(world, Vector2(20300, 0))
	var mine = load("res://scripts/entities/Projectile.gd").new()
	world.add_child(mine)
	mine.global_position = Vector2(20000, 0)
	mine.source_mech = shooter
	mine.ratios = {EnergyPacket.SynergyType.POISON: 0.4, EnergyPacket.SynergyType.KINETIC: 0.3, EnergyPacket.SynergyType.FIRE: 0.3}
	mine._deploy_mine_emitter(30.0, 60.0)
	mine.queue_free()
	shooter.queue_free()
	var live_emitters = 0
	for c in world.get_children():
		if c.get_script() == MineEmitterScript and c.global_position.x > 19000.0:
			live_emitters += 1
	for f in range(150): # 2.5 s of ticks with the mine and shooter already gone
		await get_tree().physics_frame
	if live_emitters != 1:
		push_error("FAIL: expected the deployed emitter to exist (got %d)" % live_emitters)
		failures += 1
	else:
		print("5) emitter survives its mine and shooter being freed (no dangling callbacks)")

	# --- Emitter cap: a flood of mines must not leave unbounded emitters ----------
	var before_cap = MineEmitterScript.live_count
	for n in range(40):
		var pm = pool.spawn(Vector2(30000 + n * 5, 0), Vector2.RIGHT, 0.01, 10.0, 10.0, 100.0, Color.WHITE, 1.0, true, src, EnergyPacket.SynergyType.POISON, {EnergyPacket.SynergyType.POISON: 0.4, EnergyPacket.SynergyType.KINETIC: 0.6})
		pool._trigger_poison_mine_detonation(pm)
	if MineEmitterScript.live_count > MineEmitterScript.MAX_LIVE:
		push_error("FAIL: %d live emitters exceeds the cap of %d" % [MineEmitterScript.live_count, MineEmitterScript.MAX_LIVE])
		failures += 1
	else:
		print("6) 40 simultaneous Kinetic mines -> %d live emitters (cap %d); the rest detonated as plain bursts" % [MineEmitterScript.live_count, MineEmitterScript.MAX_LIVE])

	if failures == 0:
		print("PASS: poison gateway (turret + poison blast)")
	get_tree().quit(0 if failures == 0 else 1)
