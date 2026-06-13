extends SceneTree

func _init():
	print("Starting minimal test")
	var bot = load("res://scripts/entities/Mech.gd").new()
	print("Bot instantiated: ", bot)
	if bot:
		# Need a dummy parent to call add_child
		var dummy = Node.new()
		root.add_child(dummy)
		dummy.add_child(bot)
		print("Bot added to tree, _ready called")
	quit()
