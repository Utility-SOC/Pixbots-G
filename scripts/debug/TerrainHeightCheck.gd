extends Node

# Terrain height (Hilly / Mountains): slopes slow climbers and speed descenders; shots are stopped by ground more than one level
# above where they were fired; explosions are clipped by ridges between blast and victim; snow slows walking and a blizzard drags
# at everyone; the new maps generate with heights, a clear start and impassable peaks (Mountains).

const MapGen = preload("res://scripts/core/MapGenerator.gd")
const PoolScript = preload("res://scripts/entities/ProjectileBatchPool.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")
const TerrainEffects = preload("res://scripts/core/TerrainEffects.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

class StubMap extends Node2D:
	var has_heights = true
	var heights: PackedByteArray = PackedByteArray()
	var width = 40
	var height = 10
	var tile_size = 32.0
	func los_clear(a: Vector2, b: Vector2) -> bool:
		var ceiling = maxi(_h(a), _h(b)) + 1
		var steps = int(a.distance_to(b) / 16.0)
		for i in range(1, steps):
			if _h(a.lerp(b, float(i) / float(steps))) > ceiling:
				return false
		return true
	func _h(p: Vector2) -> int:
		var x = int(floor(p.x / tile_size))
		var y = int(floor(p.y / tile_size))
		if x < 0 or y < 0 or x >= width or y >= height:
			return 0
		return heights[y * width + x]

func _ready():
	# --- the map's own height API
	var m = MapGen.new()
	m.width = 40
	m.height = 10
	m.init_heights()
	for x in range(10, 20):
		for y in range(0, 10):
			m.set_height(x, y, 4)
	_check("height_level reads what was set and 0 off the map", m.height_level(12, 3) == 4 and m.height_level(2, 2) == 0 and m.height_level(-1, 0) == 0)
	var uphill = m.slope_mult(Vector2(9.5 * 32, 100), Vector2.RIGHT)
	var downhill = m.slope_mult(Vector2(19.5 * 32, 100), Vector2.RIGHT)
	var flat = m.slope_mult(Vector2(3 * 32, 100), Vector2.RIGHT)
	_check("uphill is slower (%.2f), downhill faster (%.2f), flat unchanged" % [uphill, downhill], uphill < 1.0 and downhill > 1.0 and flat == 1.0)
	_check("a hill between two valley points blocks the line of sight", not m.los_clear(Vector2(3 * 32, 100), Vector2(30 * 32, 100)))
	_check("clear ground is clear", m.los_clear(Vector2(22 * 32, 100), Vector2(30 * 32, 100)))
	_check("from the hilltop you can see over lower ground", m.los_clear(Vector2(12 * 32, 100), Vector2(30 * 32, 100)))
	var flat_map = MapGen.new()
	_check("a flat map never changes anything", flat_map.slope_mult(Vector2.ZERO, Vector2.RIGHT) == 1.0 and flat_map.los_clear(Vector2.ZERO, Vector2(500, 0)))

	# --- shots against a ridge, through the real pool
	var stub = StubMap.new()
	stub.heights.resize(stub.width * stub.height)
	for x in range(10, 12):
		for y in range(0, 10):
			stub.heights[y * stub.width + x] = 4
	stub.add_to_group("map_generator")
	add_child(stub)
	EntityCache._stamp = -2
	var pool = PoolScript.new(64)
	add_child(pool)
	pool._refresh_height_cache(10.0)
	_check("the pool picks up the heights", not pool._hm.is_empty())
	var a = pool.spawn(Vector2(3 * 32 + 16, 100), Vector2.RIGHT, 400.0, 10.0, 6.0, 5.0, Color.WHITE, 1.0, true, null)
	var b = pool.spawn(Vector2(11 * 32 + 16, 160), Vector2.RIGHT, 400.0, 10.0, 6.0, 5.0, Color.WHITE, 1.0, true, null)
	for i in range(60):
		EntityCache._stamp = -2
		pool._process(1.0 / 30.0)
	_check("a shot fired from the valley is stopped by the ridge", pool._alive[a] == 0)
	_check("a shot fired from the ridge top flies on", pool._alive[b] == 1)

	# --- explosions clipped by a ridge
	var blast = stub.los_clear(Vector2(4 * 32, 100), Vector2(18 * 32, 100))
	_check("a blast does not reach across a ridge", not blast and stub.los_clear(Vector2(4 * 32, 100), Vector2(8 * 32, 100)))

	# --- snow, blizzard
	_check("snow slows walking", TerrainEffects.SNOW_SPEED < 1.0)
	SimRng.seed_all(3)
	var w = WeatherSystem.new()
	w.kind = "blizzard"
	add_child(w)
	w.intensity = 1.0
	EntityCache._stamp = -2
	_check("a full blizzard drags at everyone (%.2f)" % WeatherSystem.move_mult(get_tree()), absf(WeatherSystem.move_mult(get_tree()) - 0.85) < 0.001)
	w.kind = "sandstorm"
	_check("a sandstorm does not slow walking", WeatherSystem.move_mult(get_tree()) == 1.0)
	w.remove_from_group("weather")

	# --- the maps
	for t in ["Hilly", "Mountains"]:
		var map = MapGen.new()
		map.map_type = t
		map.era_override = "prewar"
		map.map_seed = 424242
		add_child(map)
		await get_tree().process_frame
		var c = Vector2i(map.width / 2, map.height / 2)
		var lo = 99
		var hi = 0
		var walls = 0
		for y in range(map.height):
			for x in range(map.width):
				lo = mini(lo, map.height_level(x, y))
				hi = maxi(hi, map.height_level(x, y))
				if map.obstacles.get(Vector2i(x, y), "") == "Wall":
					walls += 1
		_check("%s has heights spanning several levels (%d..%d)" % [t, lo, hi], map.has_heights and hi - lo >= 3)
		_check("%s: the start is low ground and clear" % t, map.height_level(c.x, c.y) <= 1 and not map.obstacles.has(c) and map.main_continent_tiles.has(c))
		if t == "Mountains":
			_check("Mountains has impassable peaks (%d wall tiles) and snow (%d)" % [walls, map.snow_cells.size()], walls > 300 and map.snow_cells.size() > 300)
		map.queue_free()
		await get_tree().process_frame
	var tundra = MapGen.new()
	tundra.map_type = "Tundra"
	tundra.map_seed = 99
	add_child(tundra)
	await get_tree().process_frame
	_check("Tundra has snow drifts (%d)" % tundra.snow_cells.size(), tundra.snow_cells.size() > 200)
	print("TerrainHeightCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
