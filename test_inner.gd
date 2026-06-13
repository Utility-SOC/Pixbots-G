extends SceneTree

func _init():
	var torso = ComponentEquipment.ComponentFactory.create_starter_torso()
	print("Torso: ", torso.component_name)
	quit()
