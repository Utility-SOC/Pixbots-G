extends Node

# Forest fire: a lit tree burns down, lights its neighbours over time (never trees out of reach), scorches mechs beside
# it, and is a hazard wary bots avoid; a FIRE hit can light a tree; a whole connected stand burns given time.

const MapGen = preload("res://scripts/core/MapGenerator.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _tree(map, cell: Vector2i):
	var t = TreeObstacle.new()
	t.map_ref = map
	t.cell = cell
	t.global_position = Vector2(cell.x * 32 + 16, cell.y * 32 + 16)
	map.tree_nodes[cell] = t
	map.add_child(t)
	return t

func _ready():
	SimRng.seed_all(11)
	seed(11)
	var map = Node2D.new()
	map.set_script(MapGen)
	# a bare stand of trees on a fake map: only tree_nodes/trees_near are used
	var holder = Node2D.new()
	add_child(holder)
	var stub = StubMap.new()
	holder.add_child(stub)
	var line: Array = []
	for i in range(8):
		line.append(_tree(stub, Vector2i(10 + i, 10)))
	var far = _tree(stub, Vector2i(30, 30))
	_check("an unlit tree is not a hazard", not line[0].is_dangerous())
	_check("lighting a tree works once", line[0].ignite() and not line[0].ignite() and line[0].is_dangerous())
	_check("a burning tree is in the hazard groups", line[0].is_in_group("burning_tree") and line[0].is_in_group("lava_vent"))
	var steps = 0
	while steps < 3600 and is_instance_valid(line[7]) and not line[7].burning:
		for t in line:
			if is_instance_valid(t):
				t._process(1.0 / 20.0)
		steps += 1
	_check("fire walks down the line (%.0f s)" % (steps / 20.0), is_instance_valid(line[7]) and line[7].burning or not is_instance_valid(line[7]))
	_check("a tree out of reach never catches", not far.burning)
	var gone = 0
	for t in line:
		if not is_instance_valid(t) or t.hp <= 0.0:
			gone += 1
	for k in range(400):
		for t in line:
			if is_instance_valid(t) and t.burning:
				t._process(1.0 / 20.0)
	var left = 0
	for t in line:
		if is_instance_valid(t) and not t.is_queued_for_deletion():
			left += 1
	_check("the burning stand burns down (%d of 8 left)" % left, left <= 1)
	_check("burnt trees leave the lookup", stub.tree_nodes.size() <= 2)
	var fresh = _tree(stub, Vector2i(50, 50))
	fresh.apply_damage(10.0, "RAW")
	_check("a non-fire hit never lights a tree", not fresh.burning)
	var lit = 0
	for i in range(40):
		var t2 = _tree(stub, Vector2i(60 + i * 2, 60))
		t2.apply_damage(1.0, "FIRE")
		if t2.burning:
			lit += 1
	_check("FIRE hits light trees often but not always (%d of 40)" % lit, lit > 10 and lit < 38)
	print("ForestFireCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

class StubMap extends Node2D:
	var tree_nodes: Dictionary = {}
	var obstacles: Dictionary = {}
	func trees_near(cell: Vector2i, r: int) -> Array:
		var out: Array = []
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var t = tree_nodes.get(Vector2i(cell.x + dx, cell.y + dy))
				if t != null and is_instance_valid(t):
					out.append(t)
		return out
	func register_tree_visual(_p): pass
	func unregister_tree_visual(_p): pass
