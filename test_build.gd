extends SceneTree

func _init():
	print("Checking Main.tscn for errors...")
	var main_scene = load("res://Main.tscn")
	if not main_scene:
		print("Failed to load Main.tscn")
	else:
		var main_node = main_scene.instantiate()
		print("Main instantiated successfully.")
		
	print("Checking MainMenu.tscn for errors...")
	var menu_scene = load("res://MainMenu.tscn")
	if not menu_scene:
		print("Failed to load MainMenu.tscn")
	else:
		var menu_node = menu_scene.instantiate()
		print("MainMenu instantiated successfully.")
		
	quit()
