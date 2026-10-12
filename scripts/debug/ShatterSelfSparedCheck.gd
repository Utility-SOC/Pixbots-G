extends Node

# A shatter hurts everything near the frozen victim EXCEPT the mech that fired the shot, whether the victim takes the hit
# through its parts (real enemies: the source is dropped on that path, so IceEffects reads Mech.hit_source) or directly.
# Also: a single gun carrying Ice + Kinetic shatters a target an earlier bullet froze.

const ProjectileBatchPoolScript = preload("res://scripts/entities/ProjectileBatchPool.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _mech(world: Node, pos: Vector2, hp: float, player := false) -> Node:
	var m = MechScript.new()
	m.is_player = player
	m.combat_role = "commander"
	world.add_child(m)
	m.set_physics_process(false)
	m.max_hp = hp
	m.hp = hp
	m.global_position = pos
	return m

func _ready():
	SimRng.seed_all(7)
	var world = Node2D.new()
	add_child(world)
	var pool = ProjectileBatchPoolScript.new(16)
	world.add_child(pool)
	var shooter = _mech(world, Vector2(240, 0), 1e6, true)
	shooter.add_to_group("player")
	var victim = _mech(world, Vector2(300, 0), 1e6)
	var neighbour = _mech(world, Vector2(330, 0), 1e6)
	pool.register_target(victim)
	pool.register_target(neighbour)
	# Freeze the victim with plenty of ice energy, then hit it with a 50/50 Ice+Kinetic shot big enough to clear the threshold.
	IceEffects.apply_hit(victim, 1.0, 400.0)
	_check("victim starts frozen", victim.status_effects.has("frozen") and victim.frozen_ice_energy > 0.0)
	var ratios = {EnergyPacket.SynergyType.ICE: 0.5, EnergyPacket.SynergyType.KINETIC: 0.5}
	pool.spawn(Vector2(295, 0), Vector2.RIGHT, 10.0, 3000.0, 20.0, 5.0, Color.WHITE, 1.0, true, shooter, EnergyPacket.SynergyType.ICE, ratios)
	var shooter_hp = shooter.hp
	var neighbour_hp = neighbour.hp
	EntityCache._stamp = -2
	pool._step_hit_test()
	_check("the shatter resolved (the same shot then re-freezes its victim, so frozen is not the signal)", victim.pending_shatter.is_empty())
	_check("the neighbour takes shatter collateral", neighbour.hp < neighbour_hp)
	_check("the mech that fired the shot is spared", shooter.hp == shooter_hp)
	print("ShatterSelfSparedCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
