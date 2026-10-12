class_name ChallengeRunner
extends Node

# Runs one Frank's Challenge inside Main: spawns the scripted enemies around the player, applies the rule to each, and watches
# for the result (all down = win, player dead or time up = loss). Replaces the wave loop while SaveManager.current_game_mode is
# "challenge". On a win it pays the reward, records the time, and returns to the main menu after a short beat.

signal finished(won: bool)

var main: Node = null
var challenge: Dictionary = {}
var enemies: Array = []
var elapsed: float = 0.0
var state: String = "idle" # idle | running | won | lost
var _return_timer: float = -1.0

func start() -> void:
	var director = main._ensure_squad_director()
	var reference = FrankChallenges.reference_shot(main.player)
	main.current_wave = int(challenge.get("wave", 20))
	var idx = 0
	var total = 0
	for g in challenge["enemies"]:
		total += int(g["n"])
	for g in challenge["enemies"]:
		for i in range(int(g["n"])):
			var bot = director._spawn_bot_for_role(str(g["role"]), challenge["rule"].has("shield"), 0)
			var ang = TAU * float(idx) / float(maxi(1, total))
			var pos = main.player.global_position + Vector2.from_angle(ang) * (750.0 + 120.0 * float(idx % 3))
			bot.global_position = main.map.get_valid_spawn_position(pos)
			bot.target = main.player
			bot.hp = bot.max_hp
			FrankChallenges.apply_rule(bot, challenge["rule"], reference)
			bot.died.connect(_on_enemy_died.bind(bot))
			enemies.append(bot)
			idx += 1
	state = "running"
	if main.has_method("show_dialogue"):
		main.show_dialogue("Frank", str(challenge["brief"]), Color(0.7, 0.9, 1.0), 9.0)

func _on_enemy_died(bot = null) -> void:
	enemies.erase(bot)
	if state == "running" and _alive_count() == 0:
		_finish(true)

func _alive_count() -> int:
	var n = 0
	for e in enemies:
		if is_instance_valid(e) and e.get("is_dead") != true:
			n += 1
	return n

func _process(delta: float) -> void:
	if state == "running":
		elapsed += delta
		if main.player == null or not is_instance_valid(main.player) or main.player.get("is_dead") == true:
			_finish(false)
		elif elapsed >= float(challenge.get("seconds", 150.0)):
			_finish(false)
		elif _alive_count() == 0:
			_finish(true)
	elif _return_timer > 0.0:
		_return_timer -= delta
		if _return_timer <= 0.0:
			get_tree().change_scene_to_file("res://MainMenu.tscn")

func _finish(won: bool) -> void:
	if state != "running":
		return
	state = "won" if won else "lost"
	if won:
		SaveManager.set_challenge_record(str(challenge["id"]), elapsed)
		main.player_scrap += int(challenge.get("reward", 100))
		if main.has_method("show_dialogue"):
			main.show_dialogue("Frank", "Cleared in %d seconds. +%d scrap. I'll chalk it up." % [int(elapsed), int(challenge.get("reward", 100))], Color(0.6, 1.0, 0.6), 7.0)
	else:
		if main.has_method("show_dialogue"):
			main.show_dialogue("Frank", "No. Think about what the rule is asking, then try again.", Color(1.0, 0.6, 0.5), 7.0)
	_return_timer = 8.0
	finished.emit(won)
