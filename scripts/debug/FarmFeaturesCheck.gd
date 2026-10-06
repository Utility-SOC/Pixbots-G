extends Node

const MapGen = preload("res://scripts/core/MapGenerator.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	for run in range(2):
		var m = MapGen.new()
		m.map_type = "FightShovel"
		add_child(m)
		await get_tree().process_frame
		var water = 0
		var shallow = 0
		var roads = 0
		for row in m.terrain:
			for b in row:
				if b == m.BiomeType.WATER: water += 1
				elif b == m.BiomeType.SHALLOW: shallow += 1
				elif b == m.BiomeType.ROAD: roads += 1
		_check("run %d: ponds exist with a shallow rim (deep %d, shallow %d)" % [run, water, shallow], water + shallow > 40 and shallow > 0)
		_check("run %d: farm tracks exist (%d road tiles)" % [run, roads], roads > 60)
		var ruin_cells = 0
		for k in m.obstacles:
			if m.obstacles[k] == "RuinPart":
				ruin_cells += 1
		var expected = 0
		for s in m.ruin_specs:
			expected += s.w * s.h
		_check("run %d: tracks did not demolish buildings (%d of %d cells)" % [run, ruin_cells, expected], ruin_cells == expected and expected > 0)
		var c = Vector2i(m.width / 2, m.height / 2)
		_check("run %d: spawn centre is dry land" % run, m.terrain[c.y][c.x] != m.BiomeType.WATER and not m.obstacles.has(c))
		var corn_in_water = 0
		for k in m.corn_field_cells:
			if m.terrain[k.y][k.x] == m.BiomeType.WATER:
				corn_in_water += 1
		_check("run %d: no corn growing in ponds" % run, corn_in_water == 0)
		m.queue_free()
		await get_tree().process_frame
	print("farm features check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
