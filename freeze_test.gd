extends SceneTree

func _init():
	print("[TEST] Loading MainMenu to set up globals...")
	var main_menu = load("res://scripts/ui/MainMenu.gd").new()
	
	print("[TEST] Loading SaveManager...")
	var sm = load("res://scripts/core/SaveManager.gd").new()
	root.add_child(sm) # Autoloads are typically children of root, but let's just make it accessible if it's singleton.
	# Actually, SaveManager is an Autoload, so accessing it via SaveManager.foo won't work in a raw script unless we register it.
	# We can just patch Main.gd for the test.
	quit()
