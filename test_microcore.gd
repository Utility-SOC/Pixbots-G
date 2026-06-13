extends MainLoop
func _initialize():
	print("Testing MicrocoreTile")
	var core = load("res://scripts/tiles/MicrocoreTile.gd").new()
	print("Core created: ", core)
	return true
