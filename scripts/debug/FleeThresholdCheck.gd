extends Node

# Regression harness for class-specific wild-bot flee thresholds
# (Status.md queue): a skittish role below its HP threshold must break off,
# leave its squad (with the squad's member accounting ticked), hand its
# wave slot back via the _on_enemy_died connection, register as wild, and
# rejoin cleanly when a new squad recruits it. Heavy roles (threshold 0.0)
# must never flee.

const MechScript = preload("res://scripts/entities/Mech.gd")
const SquadScript = preload("res://scripts/ai/Squad.gd")

const DT := 1.0 / 30.0

var wave_slots: int = 0
var _fled_signal_count: int = 0

# Named exactly like Main's handler on purpose - Mech._is_wave_enemy gates
# fleeing on a died-connection to a method with this name.
func _on_enemy_died():
	wave_slots -= 1

func _ready():
	var failures = 0
	var world = Node2D.new()
	add_child(world)

	# A stand-in player - _get_player_ref only needs group membership + position.
	var player = Node2D.new()
	player.add_to_group("player")
	player.global_position = Vector2.ZERO
	world.add_child(player)

	# --- ambusher: flees at 50% ------------------------------------------
	var mech = MechScript.new()
	mech.is_player = false
	mech.combat_role = "ambusher"
	world.add_child(mech)
	mech.set_physics_process(false)
	mech.global_position = Vector2(400, 0)
	mech.died.connect(_on_enemy_died)
	wave_slots = 1
	mech.fled_to_wild.connect(func(_bot): _fled_signal_count += 1)

	var squad = SquadScript.new()
	world.add_child(squad)
	squad.add_member(mech)

	# Healthy: no fleeing.
	mech.hp = mech.max_hp
	mech._execute_ai_tactics(DT)
	if mech.is_fleeing:
		push_error("FAIL: healthy ambusher fled")
		failures += 1

	# Drop below 50%: must start fleeing, leave the squad, run AWAY.
	mech.hp = mech.max_hp * 0.4
	mech._execute_ai_tactics(DT)
	var away_dir = (mech.global_position - player.global_position).normalized()
	if not mech.is_fleeing or _fled_signal_count != 1:
		push_error("FAIL: ambusher at 40%% didn't flee (fleeing=%s signals=%d)" % [mech.is_fleeing, _fled_signal_count])
		failures += 1
	elif mech.squad != null or squad.active_members != 0:
		push_error("FAIL: fleeing bot didn't leave its squad (active_members=%d)" % squad.active_members)
		failures += 1
	elif mech.velocity.normalized().dot(away_dir) < 0.99:
		push_error("FAIL: flee velocity not pointing away from player: %s" % str(mech.velocity))
		failures += 1
	else:
		print("1) ambusher at 40%: flees away, signal emitted, squad ticked to 0 members")

	# --- reaching safe distance: goes wild, hands the wave slot back ------
	mech.global_position = player.global_position + Vector2(2000, 0)
	mech._execute_ai_tactics(DT)
	var died_still_wired = false
	for conn in mech.died.get_connections():
		if conn.callable.get_method() == "_on_enemy_died":
			died_still_wired = true
	if not mech._has_gone_wild or wave_slots != 0 or died_still_wired:
		push_error("FAIL: wild transition wrong (wild=%s slots=%d still_wired=%s)" % [mech._has_gone_wild, wave_slots, died_still_wired])
		failures += 1
	else:
		print("2) past safe distance: wild, wave slot returned exactly once, death un-wired")

	# --- wild loiter: no re-targeting, wounds regenerate -------------------
	var hp_before = mech.hp
	for i in range(60):
		mech._execute_ai_tactics(DT)
	if mech.target != null or mech.velocity != Vector2.ZERO or mech.hp <= hp_before:
		push_error("FAIL: wild loiter wrong (target=%s vel=%s hp %f -> %f)" % [mech.target, mech.velocity, hp_before, mech.hp])
		failures += 1
	else:
		print("3) wild loiter: stays out of the fight, regenerated %.1f hp over 2s" % (mech.hp - hp_before))

	# --- recruitment clears the wild state ---------------------------------
	var squad2 = SquadScript.new()
	world.add_child(squad2)
	squad2.add_member(mech)
	if mech._has_gone_wild or mech.is_fleeing or mech.squad != squad2:
		push_error("FAIL: recruitment didn't clear wild state")
		failures += 1
	else:
		print("4) recruited into a fresh squad: back in the fight")

	# --- brawler (threshold 0.0) never flees -------------------------------
	var tank = MechScript.new()
	tank.is_player = false
	tank.combat_role = "brawler"
	world.add_child(tank)
	tank.set_physics_process(false)
	tank.global_position = Vector2(300, 0)
	tank.died.connect(_on_enemy_died)
	tank.hp = tank.max_hp * 0.01
	tank._execute_ai_tactics(DT)
	if tank.is_fleeing or tank._has_gone_wild:
		push_error("FAIL: brawler at 1%% fled - heavies fight to the end")
		failures += 1
	else:
		print("5) brawler at 1%: fights to the bitter end")

	# --- no wave slot (rival/champion/debug spawn) never flees --------------
	var rival = MechScript.new()
	rival.is_player = false
	rival.combat_role = "ambusher"
	world.add_child(rival)
	rival.set_physics_process(false)
	rival.global_position = Vector2(300, 0)
	rival.hp = rival.max_hp * 0.1 # no died -> _on_enemy_died connection
	rival._execute_ai_tactics(DT)
	if rival.is_fleeing:
		push_error("FAIL: non-wave enemy (rival-style) fled - would stall its own lifecycle")
		failures += 1
	else:
		print("6) enemy without a wave slot: exempt from fleeing")

	if failures == 0:
		print("PASS: flee thresholds - skittish roles bail, heavies hold, wave accounting stays honest")
	get_tree().quit(0 if failures == 0 else 1)
