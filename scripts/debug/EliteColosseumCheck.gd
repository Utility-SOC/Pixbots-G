extends Node

# An Elite Four rival moves the fight to the Colosseum (the fourth to the Hyper one), in the prewar era, and a Regular rival does not.

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	SaveManager.current_game_mode = "sandbox"
	SaveManager.save_to_load = ""
	SaveManager.pending_run_card = {"map_type": "Forest", "layout": "auto", "seed": 4}
	var main = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	(func(): get_tree().current_scene = main).call_deferred()
	await get_tree().process_frame
	await get_tree().process_frame
	var waited = 0
	while (main.get("player") == null or not is_instance_valid(main.player)) and waited < 600:
		await get_tree().process_frame
		waited += 1
	await get_tree().create_timer(1.0).timeout
	var director = main._ensure_squad_director()
	_check("the game starts on a normal map", MapTypes.base(main.map.map_type) != "Colosseum")
	main._spawn_rival(director, -1, SaveManager.REGULAR_RIVAL_NAMES[0])
	await get_tree().process_frame
	_check("a Regular rival stays on the current map", MapTypes.base(main.map.map_type) != "Colosseum")
	main._spawn_rival(director, -1, SaveManager.ELITE_FOUR_NAMES[0])
	await get_tree().process_frame
	await get_tree().process_frame
	_check("an Elite Four rival moves the fight to the Colosseum (%s)" % main.map.map_type, main.map.map_type == "Colosseum")
	_check("in the prewar era", main.map.era == "prewar")
	main._spawn_rival(director, -1, SaveManager.ELITE_FOUR_NAMES[3])
	await get_tree().process_frame
	await get_tree().process_frame
	_check("the fourth uses the hypertech Colosseum (%s)" % main.map.map_type, main.map.map_type == "Hyper Colosseum")
	print("EliteColosseumCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
