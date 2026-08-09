extends SceneTree

func _init():
	var file = FileAccess.open("user://test_result.txt", FileAccess.WRITE)
	if file:
		file.store_line("--- START TEST ---")
		var comp_class = load("res://scripts/core/ComponentEquipment.gd")
		file.store_line("Loaded comp_class: " + str(comp_class))
		if comp_class:
			var torso = comp_class.create_starter_torso()
			file.store_line("Torso created: " + str(torso))
		file.store_line("--- END TEST ---")
		file.close()
	quit()
