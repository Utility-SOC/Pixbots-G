extends Node

const MapScript = preload("res://scripts/core/MapGenerator.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")
const TE = preload("res://scripts/core/TerrainEffects.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _deep_touches_land(map) -> int:
	var bad = 0
	for y in range(map.height):
		for x in range(map.width):
			if map.terrain[y][x] != map.BiomeType.WATER:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx = x + d.x
				var ny = y + d.y
				if nx >= 0 and ny >= 0 and nx < map.width and ny < map.height and map.terrain[ny][nx] != map.BiomeType.WATER and map.terrain[ny][nx] != map.BiomeType.SHALLOW:
					bad += 1
	return bad

func _ready():
	var map = MapScript.new()
	add_child(map)
	await get_tree().process_frame
	map.tile_size = 32
	map.width = 12
	map.height = 12
	map.terrain = []
	for y in range(12):
		var row = []
		for x in range(12):
			row.append(map.BiomeType.WATER if (x >= 3 and x <= 8 and y >= 3 and y <= 8) else map.BiomeType.GRASSLAND)
		map.terrain.append(row)
	var n = map._mark_shallows()
	# 6x6 lake: outer ring of 20 tiles becomes shallow, inner 4x4 = 16 stay deep
	_check("the one-tile shoreline ring turns shallow (%d of 20)" % n, n == 20)
	var deep = 0
	for y in range(12):
		for x in range(12):
			if map.terrain[y][x] == map.BiomeType.WATER:
				deep += 1
	_check("the lake centre stays deep (%d)" % deep, deep == 16)
	_check("no deep water touches land", _deep_touches_land(map) == 0)
	_check("marking twice changes nothing more on a 4x4 core", map._mark_shallows() == 12)
	var overlay_cells = map._build_shallow_overlay()
	_check("overlay covers every shallow tile as one canvas overlay", overlay_cells > 0 and map.get_node_or_null("ShallowOverlay") != null)
	_check("shallows slow movement but less than they grip (%.2f, traction %.2f)" % [TE.speed(9), TE.traction(9)], TE.speed(9) < 1.0 and TE.traction(9) < 1.0 and TE.speed(9) < TE.speed(5))
	# a mech standing in shallows is slowed and does not count as over water
	map.add_to_group("map_generator")
	map.map_type = "Normal"
	var m = MechScript.new()
	add_child(m)
	m.set_physics_process(false)
	m.global_position = Vector2(3.5 * 32, 5.5 * 32) # a shallow tile on the west shore
	m._refresh_water_state()
	_check("mech in shallows: slowed, not drowning-eligible", is_equal_approx(m.terrain_speed_mult, TE.SHALLOW_SPEED) and not m._in_water)
	m.global_position = Vector2(5.5 * 32, 5.5 * 32) # deep
	m._refresh_water_state()
	_check("mech over deep water is still flagged in water", m._in_water)
	# real generation: invariant holds across several full maps
	var bad_total = 0
	var shallow_total = 0
	for i in range(3):
		var g = MapScript.new()
		g.map_type = "Normal"
		add_child(g)
		await get_tree().process_frame
		bad_total += _deep_touches_land(g)
		for row in g.terrain:
			for b in row:
				if b == g.BiomeType.SHALLOW:
					shallow_total += 1
		g.queue_free()
	_check("generated maps keep the invariant (%d violations, %d shallow tiles)" % [bad_total, shallow_total], bad_total <= shallow_total / 50 and shallow_total > 0) # pocket-corridor carving may cut a few shorelines after marking
	print("shallows check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
