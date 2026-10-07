extends Node

# Mech._refresh_water_state tile cache + _avoid_water_in_velocity any_water() skip must match the original
# per-tick computation: a bare Mech walks a random path over a real generated map; at every step the cached and
# uncached paths must agree on _in_water / terrain_speed_mult / terrain_traction and on the avoided velocity.
# Also: a runtime terrain edit (TerrainEditor.set_biome) must invalidate the cache.

const MapGeneratorScript = preload("res://scripts/core/MapGenerator.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")
const TerrainEditorScript = preload("res://scripts/core/TerrainEditor.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _state(m) -> Array:
	return [m._in_water, snappedf(m.terrain_speed_mult, 0.0001), snappedf(m.terrain_traction, 0.0001)]

func _walk(map, label: String) -> void:
	var cached = MechScript.new()
	var plain = MechScript.new()
	for m in [cached, plain]:
		m.is_player = false
		m.is_amphibious = false
		add_child(m)
		m._cached_map_ref = map
	seed(77)
	var pos = Vector2(map.width * map.tile_size * 0.5, map.height * map.tile_size * 0.5)
	var mism := 0
	var avoid_mism := 0
	var tiles_seen := {}
	for step in range(1500):
		pos += Vector2.from_angle(randf() * TAU) * randf_range(2.0, 40.0)
		pos.x = clampf(pos.x, 0.0, map.width * map.tile_size - 1.0)
		pos.y = clampf(pos.y, 0.0, map.height * map.tile_size - 1.0)
		cached.global_position = pos
		plain.global_position = pos
		MechScript.diag_no_water_cache = false
		cached._refresh_water_state()
		MechScript.diag_no_water_cache = true
		plain._refresh_water_state()
		if _state(cached) != _state(plain):
			mism += 1
		var vel = Vector2.from_angle(randf() * TAU) * randf_range(0.0, 300.0)
		MechScript.diag_no_water_cache = false
		var va = cached._avoid_water_in_velocity(vel, 1.0 / 60.0)
		MechScript.diag_no_water_cache = true
		var vb = plain._avoid_water_in_velocity(vel, 1.0 / 60.0)
		if not va.is_equal_approx(vb):
			avoid_mism += 1
		tiles_seen[Vector2i(int(pos.x / map.tile_size), int(pos.y / map.tile_size))] = true
	MechScript.diag_no_water_cache = false
	_check("%s: water/speed/traction agree on all 1500 steps (%d mismatches, %d tiles visited)" % [label, mism, tiles_seen.size()], mism == 0)
	_check("%s: avoided velocity agrees on all 1500 steps (%d mismatches)" % [label, avoid_mism], avoid_mism == 0)
	cached.queue_free()
	plain.queue_free()

func _ready():
	var map = MapGeneratorScript.new()
	map.map_type = "Water"
	map.map_seed = 4242
	add_child(map)
	await get_tree().process_frame
	_check("the Water map has water (any_water)", map.any_water())
	_walk(map, "water map")

	var dry = MapGeneratorScript.new()
	dry.map_type = "Open Field"
	dry.map_seed = 99
	add_child(dry)
	await get_tree().process_frame
	_walk(dry, "open field")

	# Runtime terrain edit invalidates the cache.
	var m = MechScript.new()
	m.is_player = false
	add_child(m)
	m._cached_map_ref = dry
	var c = Vector2i(60, 60)
	m.global_position = Vector2((c.x + 0.5) * dry.tile_size, (c.y + 0.5) * dry.tile_size)
	MechScript.diag_no_water_cache = false
	m._refresh_water_state()
	_check("dry tile: not in water before the edit", not m._in_water)
	var ed = TerrainEditorScript.new(dry)
	var before_ver: int = dry.terrain_version
	ed.set_biome(c, dry.BiomeType.WATER)
	_check("set_biome bumped terrain_version", dry.terrain_version > before_ver)
	m._refresh_water_state()
	_check("cached mech sees the tile turn to water (cache invalidated)", m._in_water)
	_check("any_water() sees the new water on the dry map", dry.any_water())
	print("MechWaterCacheParityCheck: %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)
