extends SceneTree

func _init():
	print("[TEST] Starting save load test")
	
	print("Loading SaveManager...")
	var ScriptSaveManager = load("res://scripts/core/SaveManager.gd")
	var sm = ScriptSaveManager.new()
	root.add_child(sm)
	sm.name = "SaveManager"
	
	print("Finding saves...")
	var saves = sm.get_save_files()
	print("Saves: ", saves)
	
	if saves.size() > 0:
		var save_to_load = saves[saves.size() - 1]
		if saves.has("autosave"):
			save_to_load = "autosave"
		print("Attempting to load: ", save_to_load)
		var load_data = sm.load_game(save_to_load)
		print("Load Data Keys: ", load_data.keys())
		if load_data.has("components"):
			print("Components count: ", load_data["components"].size())
	else:
		print("No saves found.")
		
	print("Done.")
	quit()
