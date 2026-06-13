extends SceneTree

func _init():
	print("Starting test...")
	var main_scene = load("res://Main.tscn").instantiate()
	root.add_child(main_scene) # Add to SceneTree to trigger proper _ready sequence!
	
	await create_timer(1.0).timeout
	
	var player = main_scene.player
	print("Player: ", player)
	var grid = player.get_node_or_null("HexGridComponent")
	print("Player Grid: ", grid)
	if grid:
		print("Grid tiles count: ", grid.get_all_tiles().size())
		
	var garage = main_scene.garage_ui
	if garage:
		print("Garage inventory: ", garage.inventory.size())
		if garage.grid_renderer:
			print("Garage grid renderer hex_grid: ", garage.grid_renderer.hex_grid)
	
	quit()
