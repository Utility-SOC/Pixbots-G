extends Node

const VentScript = preload("res://scripts/hazards/LavaVent.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")
const MapScript = preload("res://scripts/core/MapGenerator.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	var vent = VentScript.new()
	vent.radius = 50.0
	add_child(vent)
	vent.global_position = Vector2(500, 500)
	var near = MechScript.new(); add_child(near); near.set_physics_process(false)
	near.add_to_group("enemy"); near.global_position = Vector2(520, 500)
	var far = MechScript.new(); add_child(far); far.set_physics_process(false)
	far.add_to_group("enemy"); far.global_position = Vector2(900, 500)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("only the mech inside the radius is a victim", vent.victims() == [near])
	var hp0 = near.hp if "hp" in near else -1.0
	# nothing happens until a full telegraph has run
	vent._timer = 100.0
	vent.start_telegraph()
	vent._process(VentScript.TELEGRAPH * 0.5)
	_check("still telegraphing mid-warning, no eruption yet", vent.times_erupted == 0)
	vent._process(VentScript.TELEGRAPH * 0.6)
	_check("erupts once the telegraph ends", vent.times_erupted == 1)
	await get_tree().process_frame
	if true:
		_check("victim took damage (%.1f -> %.1f)" % [hp0, near.hp], near.hp < hp0)
		_check("distant mech untouched", far.hp >= far.max_hp - 0.01)
	vent._process(VentScript.BURST + 0.01)
	_check("returns to idle with a new randomised period", vent._phase == 0 and vent._timer >= VentScript.MIN_PERIOD)
	# placement: only on volcano ground, capped
	var map = MapScript.new()
	add_child(map)
	await get_tree().process_frame
	map.map_type = "Normal"
	map.tile_size = 32
	map.width = 120
	map.height = 80
	map.obstacles = {}
	map.terrain = []
	for y in range(80):
		var row = []
		for x in range(120):
			row.append(map.BiomeType.VOLCANO if x < 60 else map.BiomeType.GRASSLAND)
		map.terrain.append(row)
	for v in get_tree().get_nodes_in_group("lava_vent"):
		if v != vent:
			v.queue_free()
	await get_tree().process_frame
	var placed = map._scatter_lava_vents()
	_check("vents are placed on volcano ground (%d)" % placed, placed > 0 and placed <= MapScript.LAVA_VENT_MAX)
	var all_on_volcano = true
	var near_centre = false
	for v in map.get_children():
		if v is VentScript:
			var gx = int(v.global_position.x / 32)
			var gy = int(v.global_position.y / 32)
			if map.terrain[gy][gx] != map.BiomeType.VOLCANO:
				all_on_volcano = false
			if absi(gx - 60) + absi(gy - 40) < MapScript.VENT_SPAWN_CLEAR:
				near_centre = true
	_check("no vent off-volcano and none in the spawn clearing", all_on_volcano and not near_centre)
	map.map_type = "Arena"
	_check("arena maps get no vents", map._scatter_lava_vents() == 0)
	print("lava vent check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
