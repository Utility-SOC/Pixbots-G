extends SceneTree

func _init():
	print("Starting test_fire...")
	var mech_scene = load("res://scripts/entities/Mech.gd")
	if not mech_scene:
		print("Failed to load Mech")
		quit()
		return
		
	var m = mech_scene.new()
	print("Mech instantiated.")
	m.is_player = true
	m._ready()
	print("Mech _ready done.")
	m._shoot(Vector2(0,0), true)
	print("Mech _shoot done.")
	
	quit()
