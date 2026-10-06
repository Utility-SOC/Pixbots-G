extends Node

const ObjScript = preload("res://scripts/hazards/ZoneObjective.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")
const MapScript = preload("res://scripts/core/MapGenerator.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _drops() -> int:
	var n = 0
	for c in get_children():
		if c.get_script() != null and "equipment_data" in c and c.equipment_data != null:
			n += 1
	return n

func _ready():
	var player = MechScript.new(); player.is_player = true; add_child(player); player.set_physics_process(false)
	player.add_to_group("player")
	var foe = MechScript.new(); add_child(foe); foe.set_physics_process(false)
	foe.add_to_group("enemy")
	foe.global_position = Vector2(5000, 0)
	var hold = ObjScript.new()
	hold.kind = "hold"
	hold.radius = 100.0
	hold.set_process(false) # the test drives step() itself
	add_child(hold)
	hold.global_position = Vector2(0, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	# player outside: nothing fills
	player.global_position = Vector2(500, 0)
	await get_tree().process_frame
	hold.step(5.0)
	_check("no progress while the player is outside", hold.progress == 0.0)
	# inside, uncontested: fills
	player.global_position = Vector2(10, 0)
	await get_tree().process_frame
	hold.step(5.0)
	_check("half full after half the hold time (%.6f)" % hold.progress, absf(hold.progress - 0.5) < 0.001)
	# an enemy inside stalls it
	foe.global_position = Vector2(20, 0)
	await get_tree().process_frame
	hold.step(3.0)
	_check("contested: an enemy inside stalls the fill", hold.contested and absf(hold.progress - 0.5) < 0.001)
	# leaving drains at half speed
	foe.global_position = Vector2(5000, 0)
	player.global_position = Vector2(500, 0)
	await get_tree().process_frame
	hold.step(4.0)
	_check("drains slowly when the player leaves (%.2f)" % hold.progress, absf(hold.progress - 0.3) < 0.001)
	# finish it
	player.global_position = Vector2(10, 0)
	await get_tree().process_frame
	hold.step(8.0)
	_check("completing the ring pays out exactly once", hold.done and hold.rewards_given == 1)
	hold.step(8.0)
	_check("no second payout", hold.rewards_given == 1)
	# reward rarity scaling
	_check("rarity rises a tier per 40 waves, capped below mythic", ObjScript.rarity_for_wave(1, 2) == 2 and ObjScript.rarity_for_wave(41, 2) == 3 and ObjScript.rarity_for_wave(400, 2) == 3)
	# cache: opens on approach
	var cache = ObjScript.new()
	cache.kind = "cache"
	add_child(cache)
	cache.global_position = Vector2(2000, 0)
	await get_tree().process_frame
	cache._process(0.1)
	_check("cache stays shut while the player is away", not cache.done)
	player.global_position = Vector2(2010, 0)
	await get_tree().process_frame
	cache._process(0.1)
	_check("cache opens when the player walks up", cache.done and cache.rewards_given == 1)
	# map wiring: forts and villages become objectives
	var map = MapScript.new()
	add_child(map)
	await get_tree().process_frame
	for o in get_tree().get_nodes_in_group("zone_objective"):
		if o != hold and o != cache:
			o.queue_free()
	await get_tree().process_frame
	map.tile_size = 32
	map.zones = [{"pos": Vector2(50, 50), "kind": "fort", "r": 30.0}, {"pos": Vector2(90, 40), "kind": "village", "r": 30.0}, {"pos": Vector2(20, 20), "kind": "lake", "r": 30.0}]
	var made = map._spawn_zone_objectives()
	_check("fort and village become objectives, lake does not (%d)" % made, made == 2)
	print("zone objective check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
