extends Node

# Enemy capture of fort hold points and the capture-buff HUD strip: enemies in an empty ring fill it and then hold it (their
# buff goes to enemies nearby); a player inside stops and undoes it; a held point shows red; squads head for empty forts;
# the HUD lists the player's buffs with time left.

const MechScript = preload("res://scripts/entities/Mech.gd")
const SquadTactics = preload("res://scripts/ai/SquadTactics.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _mech(world: Node, pos: Vector2, is_player: bool):
	var m = MechScript.new()
	m.is_player = is_player
	world.add_child(m)
	m.set_physics_process(false)
	m.global_position = pos
	m.add_to_group("player" if is_player else "enemy")
	return m

func _ready():
	var world = Node2D.new()
	add_child(world)
	var obj = ZoneObjective.new()
	obj.kind = "hold"
	obj.radius = 100.0
	obj.buff_type = "weapons"
	world.add_child(obj)
	obj.global_position = Vector2(1000, 1000)
	var enemy = _mech(world, Vector2(1010, 1000), false)
	var far_enemy = _mech(world, Vector2(1000 + 100 * 1.4, 1000), false)
	var out_enemy = _mech(world, Vector2(1000 + 100 * 1.9, 1000), false)
	var player = _mech(world, Vector2(5000, 5000), true)
	EntityCache._stamp = -2
	for i in range(int(ZoneObjective.ENEMY_HOLD_SECONDS * 10.0) + 5):
		EntityCache._stamp = -2
		obj.step(0.1)
	_check("an enemy alone in an empty ring takes it (%.2f)" % obj.enemy_progress, obj.enemy_held and obj.enemy_progress >= 1.0)
	_check("the player's own progress is untouched", obj.progress == 0.0)
	for i in range(12):
		EntityCache._stamp = -2
		obj.step(0.1)
	_check("the enemy in the ring got the buff", CaptureBuffs.is_active(enemy, "weapons"))
	_check("an enemy near the ring got it too", CaptureBuffs.is_active(far_enemy, "weapons"))
	_check("an enemy far away did not", not CaptureBuffs.is_active(out_enemy, "weapons"))
	_check("the enemy buff is short-lived (%.1f s)" % enemy.capture_buffs["weapons"], float(enemy.capture_buffs["weapons"]) <= ZoneObjective.ENEMY_BUFF_SECONDS)
	_check("the player never got the buff", not CaptureBuffs.is_active(player, "weapons"))
	player.global_position = Vector2(1000, 1000)
	enemy.global_position = Vector2(5000, 5000)
	far_enemy.global_position = Vector2(5000, 5000)
	for i in range(80):
		EntityCache._stamp = -2
		obj.step(0.1)
	_check("the player retakes it (progress %.2f, held %s)" % [obj.progress, str(obj.enemy_held)], not obj.enemy_held and obj.progress > 0.5)
	# a second, fresh point: contested rings are not taken
	var obj2 = ZoneObjective.new()
	obj2.kind = "hold"
	obj2.radius = 100.0
	world.add_child(obj2)
	obj2.global_position = Vector2(3000, 3000)
	var e2 = _mech(world, Vector2(3000, 3000), false)
	var p2 = player
	p2.global_position = Vector2(3010, 3000)
	for i in range(300):
		EntityCache._stamp = -2
		obj2.step(0.1)
	_check("a player inside stops the enemy taking it (%.2f)" % obj2.enemy_progress, obj2.enemy_progress == 0.0 and not obj2.enemy_held)

	# squads going for empty forts (one squad in five, by instance id)
	obj.done = false
	obj.enemy_held = false
	obj.progress = 0.0
	var one_in_five = null
	var others = 0
	for i in range(30):
		var sq = StubSquad.new()
		world.add_child(sq)
		sq.position = Vector2(1300, 1000)
		if sq.get_instance_id() % 5 == 1:
			if one_in_five == null:
				one_in_five = sq
		else:
			others += 1
			if SquadTactics.capture_focus(sq, Vector2(8000, 8000)) != Vector2.INF:
				_check("only one squad in five goes for a fort", false)
	_check("a squad (one in five) heads for the empty fort", one_in_five != null and SquadTactics.capture_focus(one_in_five, Vector2(8000, 8000)) == obj.global_position)
	_check("...not while the player is near it", SquadTactics.capture_focus(one_in_five, obj.global_position + Vector2(300, 0)) == Vector2.INF)
	obj.enemy_held = true
	_check("...not once enemies hold it", SquadTactics.capture_focus(one_in_five, Vector2(8000, 8000)) == Vector2.INF)
	obj.enemy_held = false
	obj.done = true
	_check("...nor a finished one", SquadTactics.capture_focus(one_in_five, Vector2(8000, 8000)) == Vector2.INF)

	# HUD
	var hud = CaptureBuffHud.new()
	add_child(hud)
	player.capture_buffs = {}
	hud.refresh(player)
	_check("the HUD strip hides with no buffs", not hud.visible and hud.rows().is_empty())
	CaptureBuffs.grant(player, "armor")
	CaptureBuffs.grant(player, "speed")
	player.capture_buffs["speed"] = 12.3
	hud.refresh(player)
	_check("the HUD lists the player's buffs with time left", hud.visible and hud.rows().size() == 2 and is_equal_approx(float(hud.rows()[1]["left"]), 12.3))
	print("CaptureEnemyCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

class StubSquad extends Node2D:
	func get_center_position() -> Vector2:
		return position
