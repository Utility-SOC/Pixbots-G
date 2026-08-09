extends SceneTree
func _init():
	var n = Node.new()
	var x = n.get("foo", 5)
	print("x is: ", x)
	quit()
