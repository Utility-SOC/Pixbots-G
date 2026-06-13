extends SceneTree

func _init():
	print("Starting test...")
	var main_scene = load("res://Main.tscn").instantiate()
	# Wait, Main.gd isn't a packed scene? Main.tscn is.
	# But MainMenu.gd loads "res://main.tscn". Let's load that.
	if main_scene:
		# Simulate what happens
		main_scene._ready()
		var player = main_scene.player
		print("Player: ", player)
		var grid = player.get_node_or_null("HexGridComponent")
		print("Player Grid: ", grid)
		if grid:
			print("Grid tiles count: ", grid.get_all_tiles().size())
			
		var garage = main_scene.garage_ui
		if garage:
			print("Garage inventory: ", garage.inventory.size())
			print("Garage grid renderer hex_grid: ", garage.grid_renderer.hex_grid)
	quit()
