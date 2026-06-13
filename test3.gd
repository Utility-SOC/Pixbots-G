extends SceneTree

func _init():
	var scr = load("res://scripts/tiles/MicrocoreTile.gd")
	if scr:
		var inst = scr.new()
		print("INST: ", inst)
	else:
		print("SCR FAILED")
	quit()
