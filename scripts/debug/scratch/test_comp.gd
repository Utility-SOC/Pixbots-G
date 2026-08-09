extends SceneTree
func _init():
	var script = load('res://scripts/core/ComponentEquipment.gd')
	print('script: ', script)
	print('has new: ', script.has_method('new'))
	quit()
