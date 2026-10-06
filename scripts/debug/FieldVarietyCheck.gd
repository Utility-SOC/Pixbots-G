extends Node

const MapGen = preload("res://scripts/core/MapGenerator.gd")
var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _gen(t: String):
	var m = MapGen.new()
	m.map_type = t
	add_child(m)
	await get_tree().process_frame
	return m

func _ready():
	var of = await _gen("Open Field")
	var boulders = 0
	var bad = 0
	var centre = Vector2(of.width / 2.0, of.height / 2.0)
	for k in of.obstacles:
		if of.obstacles[k] == "Boulder":
			boulders += 1
			if Vector2(k).distance_to(centre) < 10.0 or of.terrain[k.y][k.x] == of.BiomeType.WATER:
				bad += 1
	_check("Open Field has boulder cover (%d)" % boulders, boulders >= 12)
	_check("none of it on water or in the spawn clearing", bad == 0)
	var c0 = Vector2i(of.width / 2, of.height / 2)
	_check("spawn centre stays open", not of.obstacles.has(c0))
	of.queue_free()
	await get_tree().process_frame
	var tt = await _gen("Tabletop")
	var trees = 0
	var green = 0
	for k in tt.obstacles:
		if tt.obstacles[k] == "Tree":
			trees += 1
	for row in tt.terrain:
		for b in row:
			if b == tt.BiomeType.GRASSLAND:
				green += 1
	_check("Tabletop has flocked forest bases (%d trees, %d green tiles)" % [trees, green], trees >= 8 and green >= 60)
	var ruin_ok = true
	var expected = 0
	for s in tt.ruin_specs:
		expected += s.w * s.h
	var ruin_cells = 0
	for k in tt.obstacles:
		if tt.obstacles[k] == "RuinPart":
			ruin_cells += 1
	_check("ruins are untouched (%d of %d cells)" % [ruin_cells, expected], ruin_cells == expected)
	_check("spawn centre stays open", not tt.obstacles.has(Vector2i(tt.width / 2, tt.height / 2)))
	tt.queue_free()
	print("field variety check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
