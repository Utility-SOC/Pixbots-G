extends Node

# Missile impacts follow what is IN the missile: blast radius scales with explosive damage; a
# kinetic-dominant "sword" is tiny with no splash/puddle; lightning chains out from a small impact;
# poison deploys a turret; fire leaves burning ground that ignites what stands in it.

const MineEmitterScript = preload("res://scripts/attacks/MineEmitter.gd")
const ShellScript = preload("res://scripts/attacks/MortarShell.gd")
const PuddleScript = preload("res://scripts/attacks/ElementalPuddle.gd")

const MechScript = preload("res://scripts/entities/Mech.gd")

var failures := 0
var world: Node2D

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

# Real enemy mechs (the direct-hit pipeline reads many Mech properties a stand-in would lack).
func _dummy(pos: Vector2, _enemy := true):
	var m = MechScript.new()
	m.combat_role = "brawler"
	world.add_child(m)
	m.set_physics_process(false)
	m.max_hp = 1e9
	m.hp = 1e9
	m.global_position = pos
	return m

func _dmg(m) -> float:
	return 1e9 - m.hp

func _shell(syn: Dictionary, dmg: float, target := Vector2.ZERO):
	var sh = ShellScript.new()
	world.add_child(sh)
	sh.setup(target + Vector2(0, -300), target, 0.5, dmg, syn, true, null)
	return sh

func _ready():
	world = Node2D.new()
	add_child(world)
	var E = EnergyPacket.SynergyType

	# --- 1. blast radius follows explosive damage ----------------------------------------------
	var r_small = _shell({E.EXPLOSION: 600.0}, 600.0).effective_radius
	var r_mid = _shell({E.EXPLOSION: 6000.0}, 6000.0).effective_radius
	var r_big = _shell({E.EXPLOSION: 60000.0}, 60000.0).effective_radius
	_check("radius grows with explosive damage (%.0f -> %.0f -> %.0f)" % [r_small, r_mid, r_big], r_mid > r_small * 1.8 and r_big > r_mid * 1.8)
	_check("60,000 explosive is ~5x the 600 blast but capped (%.1fx)" % (r_big / r_small), r_big / r_small >= 4.0 and r_big / r_small <= 5.1)
	var r_tiny = _shell({E.EXPLOSION: 20.0}, 20.0).effective_radius
	_check("a tiny payload still pops (min radius, %.0f)" % r_tiny, r_tiny >= 40.0 and r_tiny < r_small * 1.01)

	# --- 2. kinetic sword: tiny, no splash, no puddle --------------------------------------------
	var sword = _shell({E.KINETIC: 5000.0}, 5000.0, Vector2(2000, 0))
	_check("kinetic-only missile is a sword (radius %.0f)" % sword.effective_radius, sword._is_sword and sword.effective_radius <= 34.0)
	var direct = _dummy(Vector2(2000, 5))
	var bystander = _dummy(Vector2(2000, 80))
	await get_tree().process_frame # EntityCache snapshots enemy groups once per frame
	sword._elapsed = sword.flight_time
	sword._process(0.0)
	_check("sword: no splash on a bystander 80px away", _dmg(bystander) == 0.0)
	var puddles_after_sword = 0
	for c in world.get_children():
		if c.get_script() == PuddleScript:
			puddles_after_sword += 1
	_check("sword leaves no puddle", puddles_after_sword == 0)
	var blast = _shell({E.EXPLOSION: 5000.0}, 5000.0, Vector2(4000, 0))
	var d2 = _dummy(Vector2(4000, 5))
	var b2 = _dummy(Vector2(4000, 80))
	await get_tree().process_frame
	blast._elapsed = blast.flight_time
	blast._process(0.0)
	_check("explosive missile splashes the same bystander (%.0f dmg)" % _dmg(b2), _dmg(b2) > 0.0)

	# sword visual: an 8-pointed star (16 vertices), blades longer for bigger payloads
	var sw_small = _shell({E.KINETIC: 150.0}, 150.0, Vector2(2500, 300))
	var sw_big = _shell({E.KINETIC: 60000.0}, 60000.0, Vector2(2600, 300))
	_check("sword star has 8 blades (%d vertices)" % ShellScript.star_points(20.0, 0.0).size(), ShellScript.star_points(20.0, 0.0).size() == 16)
	_check("sword blades grow with the payload (%.0f -> %.0f px)" % [sw_small.sword_length(), sw_big.sword_length()], sw_big.sword_length() > sw_small.sword_length() * 2.5)
	var pts = ShellScript.star_points(20.0, 0.0)
	_check("blades are thick at the centre then taper (inner/outer %.2f)" % (pts[1].length() / pts[0].length()), pts[1].length() / pts[0].length() < 0.3)

	# --- 3. lightning: small impact + chain ----------------------------------------------------------
	var lt = _shell({E.LIGHTNING: 4000.0}, 4000.0, Vector2(6000, 0))
	_check("lightning missile impact stays small (%.0f)" % lt.effective_radius, lt.effective_radius <= 45.0)
	var c0 = _dummy(Vector2(6000, 10))
	var c1 = _dummy(Vector2(6150, 0))
	var c2 = _dummy(Vector2(6330, 20))
	var c3 = _dummy(Vector2(6450, -10))
	await get_tree().process_frame
	lt._elapsed = lt.flight_time
	lt._process(0.0)
	var chained = 0
	for c in [c1, c2, c3]:
		if _dmg(c) > 0.0 and c.status_effects.has("paralyzed"):
			chained += 1
	var arcs = 0
	for c in world.get_children():
		if c.get_script() and str(c.get_script().resource_path).ends_with("LightningChainVisual.gd"):
			arcs += 1
	_check("lightning chains to the next enemies (%d of 3 hit and paralyzed)" % chained, chained >= 2)
	_check("a lightning arc is drawn (%d)" % arcs, arcs >= 1)

	# --- 4. poison -> turret ------------------------------------------------------------------------------
	var before = MineEmitterScript.live_count
	var ps = _shell({E.POISON: 3000.0, E.KINETIC: 2000.0}, 5000.0, Vector2(8000, 0))
	ps._deploy_poison_turret()
	_check("a poison missile deploys a turret emitter (%d -> %d)" % [before, MineEmitterScript.live_count], MineEmitterScript.live_count == before + 1)
	var pure = _shell({E.POISON: 3000.0}, 3000.0, Vector2(9000, 0))
	var before2 = MineEmitterScript.live_count
	pure._deploy_poison_turret()
	_check("a pure-poison missile also deploys a turret", MineEmitterScript.live_count == before2 + 1)
	var sword_psn = _shell({E.POISON: 100.0, E.KINETIC: 4000.0}, 4100.0, Vector2(9500, 0))
	var before3 = MineEmitterScript.live_count
	sword_psn._deploy_poison_turret()
	_check("is_sword_composition: kinetic-dominant yes, explosive no", ShellScript.is_sword_composition({EnergyPacket.SynergyType.KINETIC: 9.0, EnergyPacket.SynergyType.POISON: 1.0}) and not ShellScript.is_sword_composition({EnergyPacket.SynergyType.KINETIC: 5.0, EnergyPacket.SynergyType.EXPLOSION: 5.0}))
	_check("a kinetic sword with a trace of poison does not", MineEmitterScript.live_count == before3)

	# --- 5. fire -> burning ground ------------------------------------------------------------------------------
	var fs = _shell({E.FIRE: 3000.0, E.EXPLOSION: 3000.0}, 6000.0, Vector2(10000, 0))
	var victim = _dummy(Vector2(10000, 30))
	fs._spawn_puddle()
	var puddle = null
	for c in world.get_children():
		if c.get_script() == PuddleScript and c.global_position.x > 9000.0:
			puddle = c
	_check("fire leaves a puddle", puddle != null)
	if puddle:
		_check("a fire-heavy puddle is burning ground and lasts (%.1fs)" % puddle._duration, puddle._fire_ratio >= PuddleScript.BURNING_GROUND_THRESHOLD and puddle._duration >= 7.0)
		for f in range(40):
			await get_tree().physics_frame
		_check("standing in it sets you on fire", victim.status_effects.has("burning") and _dmg(victim) > 0.0)

	if failures == 0:
		print("PASS: missile impacts scale with composition (blast, sword, chain lightning, poison turret, burning ground)")
	get_tree().quit(0 if failures == 0 else 1)
