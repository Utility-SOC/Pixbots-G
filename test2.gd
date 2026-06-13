extends MainLoop
func _initialize():
	var test = load("res://scripts/tiles/MicrocoreTile.gd")
	if test:
		print("LOAD SUCCESS")
		var inst = test.new()
		print("INST: ", inst)
	else:
		print("LOAD FAILED")
	return true
