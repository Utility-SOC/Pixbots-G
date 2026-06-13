extends SceneTree

func _init():
	print("[TEST] Starting equip test")
	
	var sm = load("res://scripts/core/SaveManager.gd").new()
	var load_data = sm.load_game("autosave")
	
	var Mech = load("res://scripts/entities/Mech.gd")
	var player = Mech.new()
	player.is_player = true
	player.name = "PlayerMech"
	root.add_child(player)
	
	print("Equipping components...")
	if load_data.has("components"):
		for slot in player.components.keys():
			player.components[slot].queue_free()
		player.components.clear()
		
		for slot in load_data["components"].keys():
			print("Equipping slot: ", slot)
			player.equip_component(load_data["components"][slot])
			
	print("Recalculating grid...")
	player._recalculate_grid()
	
	print("Done.")
	quit()
