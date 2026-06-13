extends SceneTree

func _init():
	var main_scene = load("res://Main.tscn").instantiate()
	root.add_child(main_scene)
	
	await create_timer(0.1).timeout
	
	main_scene._open_garage()
	
	await create_timer(0.1).timeout
	
	var garage = main_scene.garage_ui
	if garage:
		print("Garage inventory array size: ", garage.inventory.size())
		print("Garage inventory UI children: ", garage.inv_vbox.get_child_count())
	else:
		print("Garage is null!")
		
	quit()
