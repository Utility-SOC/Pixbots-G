extends Node

# In the real Main (campaign): clearing wave 10 drops you into the Garage with the game paused; clearing wave 9 does not.

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	SaveManager.current_game_mode = "campaign"
	SaveManager.save_to_load = ""
	SaveManager.tutorial_completed = true
	SaveManager.pending_run_card = {"map_type": "Forest", "layout": "auto", "seed": 6}
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
	if main.garage_ui and is_instance_valid(main.garage_ui):
		main._close_garage()
		await get_tree().process_frame
	main.current_wave = 9
	main._on_wave_cleared()
	await get_tree().process_frame
	_check("clearing wave 9 does not force the Garage", main.garage_ui == null or not is_instance_valid(main.garage_ui))
	main.current_wave = 10
	main._on_wave_cleared()
	await get_tree().process_frame
	_check("clearing wave 10 forces the Garage open", main.garage_ui != null and is_instance_valid(main.garage_ui))
	_check("and pauses the game", get_tree().paused)
	print("ForcedGarageFlowCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
