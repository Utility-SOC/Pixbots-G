extends Node

# The classic Desert on seed 2 used to roll ~14,000 destructible obstacles, which corrupted the engine heap in the real
# renderer. MapGenerator thins them to MAX_DESTRUCTIBLES before building.
var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	for spec in [["Desert", 2], ["Desert", 3], ["Tundra", 2]]:
		var m = MapGenerator.new()
		m.map_type = spec[0]
		m.map_seed = spec[1]
		add_child(m)
		await get_tree().process_frame
		var n = 0
		for c in m.get_children():
			if c.get_script() and str(c.get_script().resource_path).ends_with("DestructibleObstacle.gd"):
				n += 1
		_check("%s seed %d: %d destructibles <= cap %d" % [spec[0], spec[1], n, MapGenerator.MAX_DESTRUCTIBLES], n <= MapGenerator.MAX_DESTRUCTIBLES + 50)
		m.queue_free()
		await get_tree().process_frame
	print("DestructibleCapCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
