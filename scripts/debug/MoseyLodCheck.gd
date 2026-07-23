extends Node

# Regression harness for Mech.gd's "mosey" behavior (per the user: far
# enemies should amble passively toward the player instead of paying for
# full _execute_ai_tactics - sight raycast, separation query, flow-field
# lookup, weapon dispatch - until they're actually close enough to matter,
# and should approach staggered/slowly rather than "cramming in" all at
# once). Confirms:
#   1. A far (>1400 units), non-boss, non-fleeing enemy closes distance on
#      its target without ever gaining has_sight_of_player or firing a shot
#      (mosey never touches sight/shoot state).
#   2. It moves slower than full engagement speed (MOSEY_SPEED_MULT).
#   3. A far WILD mech (_has_gone_wild) stays in WILD state (mosey doesn't
#      override _update_flee_state) - velocity ZERO, AI label "WILD", not
#      "MOSEY". Uses _has_gone_wild rather than a live flee-threshold roll
#      since FLEE_SAFE_DISTANCE and the mosey LOD distance are both 1400 -
#      a mech far enough to mosey has, by definition, also just crossed
#      "safe" and _update_flee_state would immediately _finish_flee() it
#      before ever setting an away-pointing velocity to check. WILD's
#      distance-independent early return sidesteps that coincidence.
#   4. A far BOSS still runs full _execute_ai_tactics (AI state label
#      reflects real engagement/search, not "MOSEY").

const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0

# Named exactly like Main's handler on purpose - Mech._is_wave_enemy gates
# fleeing on a died-connection to a method with this name (see
# FleeThresholdCheck.gd's identical pattern).
func _on_enemy_died():
	pass

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var world = Node2D.new()
	add_child(world)

	var player = MechScript.new()
	player.is_player = true
	player.global_position = Vector2.ZERO
	world.add_child(player)
	player.set_physics_process(false)

	# --- 1/2: plain far enemy moseys, doesn't gain sight/fire ---------------
	var enemy = MechScript.new()
	enemy.is_player = false
	enemy.combat_role = "brawler"
	enemy.global_position = Vector2(2000, 0) # well past the 1400 LOD threshold
	world.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.target = player

	var start_pos = enemy.global_position
	for i in range(120): # 2s at 60Hz
		enemy._physics_process(1.0 / 60.0)

	# Not checking global_position movement here - move_and_slide() uses the
	# ENGINE's real physics delta internally, which a manually-ticked
	# _physics_process(1.0/60.0) call doesn't drive (same limitation
	# DroneChaseShootCheck.gd's header comment flags for Timers). Velocity
	# pointing at the target is the correct, methodology-independent check:
	# it's what move_and_slide() would actually move along on a real tick.
	var toward_dir = start_pos.direction_to(player.global_position)
	var vel_dir = enemy.velocity.normalized() if enemy.velocity.length() > 0.01 else Vector2.ZERO
	_check("far non-fleeing enemy's mosey velocity points toward its target", vel_dir.dot(toward_dir) > 0.9)
	_check("mosey never gained sight of the player", not enemy.has_sight_of_player)
	_check("mosey never fired (fire_cooldown still at its initial 0)", enemy.fire_cooldown <= 0.001)

	var expected_speed = enemy.current_move_speed * enemy.speed_modifier * enemy.MOSEY_SPEED_MULT
	var actual_speed = enemy.velocity.length()
	_check("mosey speed matches MOSEY_SPEED_MULT (got %.1f, expect ~%.1f)" % [actual_speed, expected_speed],
		abs(actual_speed - expected_speed) < 1.0)

	# --- 3: a far WILD mech stays wild, not moseying -----------------------
	var wild_enemy = MechScript.new()
	wild_enemy.is_player = false
	wild_enemy.combat_role = "brawler"
	wild_enemy.global_position = Vector2(2000, 500)
	world.add_child(wild_enemy)
	wild_enemy.set_physics_process(false)
	wild_enemy.target = player
	wild_enemy._has_gone_wild = true

	for i in range(30):
		wild_enemy._physics_process(1.0 / 60.0)

	_check("far WILD mech's AI state label is 'WILD', not 'MOSEY'",
		wild_enemy._ai_state_label and wild_enemy._ai_state_label.text == "WILD")
	_check("far WILD mech's velocity stayed zero (WILD loiters in place)", wild_enemy.velocity.length() < 0.01)

	# --- 4: a far boss still runs full AI tactics, not mosey ---------------
	var boss = MechScript.new()
	boss.is_player = false
	boss.is_boss = true
	boss.combat_role = "brawler"
	boss.global_position = Vector2(2000, -500)
	world.add_child(boss)
	boss.set_physics_process(false)
	boss.target = player

	for i in range(30):
		boss._physics_process(1.0 / 60.0)

	_check("far boss's AI state label is NOT 'MOSEY' (still runs full _execute_ai_tactics)",
		not boss._ai_state_label or boss._ai_state_label.text != "MOSEY")

	if failures == 0:
		print("PASS: far mechs mosey (cheap, slow, no sight/fire), except fleeing/wild mechs and bosses which keep their real behavior")
	get_tree().quit(0 if failures == 0 else 1)
