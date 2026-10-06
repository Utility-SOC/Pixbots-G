extends Node

const TE = preload("res://scripts/core/TerrainEffects.gd")
const MapScript = preload("res://scripts/core/MapGenerator.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	_check("road is faster than grass", TE.speed(7) > 1.0 and TE.speed(0) == 1.0)
	_check("ash and undergrowth cost speed", TE.speed(5) < 1.0 and TE.speed(3) < 1.0)
	_check("only tundra is slippery", TE.traction(4) < 0.3 and TE.traction(0) == 1.0 and TE.traction(7) == 1.0)
	# Player steering: on ice the same input gains speed several times slower and brakes slower.
	var dt = 0.1
	var grass = TE.steer(Vector2.ZERO, Vector2(200, 0), 600.0, 1.0, dt)
	var ice = TE.steer(Vector2.ZERO, Vector2(200, 0), 600.0, TE.traction(4), dt)
	_check("ice accelerates slower (%.0f vs %.0f)" % [ice.x, grass.x], ice.x < grass.x * 0.3)
	var brake_grass = TE.steer(Vector2(200, 0), Vector2.ZERO, 600.0, 1.0, dt)
	var brake_ice = TE.steer(Vector2(200, 0), Vector2.ZERO, 600.0, TE.traction(4), dt)
	_check("ice brakes slower (%.0f vs %.0f)" % [brake_ice.x, brake_grass.x], brake_ice.x > brake_grass.x + 40.0)
	# AI slide: heading flips, velocity only creeps toward the new one on ice.
	var s = TE.slide(Vector2(100, 0), Vector2(-100, 0), TE.traction(4), 1.0 / 60.0)
	_check("AI keeps most of its old heading for a tick on ice (%.0f)" % s.x, s.x > 50.0)
	_check("AI turns instantly on normal ground", TE.slide(Vector2(100, 0), Vector2(-100, 0), 1.0, 1.0 / 60.0) == Vector2(-100, 0))
	# Mech integration: standing on a road / ice tile sets its terrain factors.
	var map = MapScript.new()
	add_child(map)
	await get_tree().process_frame
	map.tile_size = 32
	map.width = 3
	map.height = 1
	map.terrain = [[map.BiomeType.GRASSLAND, map.BiomeType.ROAD, map.BiomeType.TUNDRA]]
	map.map_type = "Normal"
	map.add_to_group("map_generator")
	var m = MechScript.new()
	add_child(m)
	m.set_physics_process(false)
	for case in [[16.0, 1.0, 1.0], [48.0, TE.ROAD_SPEED, 1.0], [80.0, 1.0, TE.ICE_TRACTION]]:
		m.global_position = Vector2(case[0], 16.0)
		m._refresh_water_state()
		_check("mech at x=%.0f: speed x%.2f traction %.2f" % [case[0], m.terrain_speed_mult, m.terrain_traction], is_equal_approx(m.terrain_speed_mult, case[1]) and is_equal_approx(m.terrain_traction, case[2]))
	print("terrain effects check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
