extends Node

# The graphics showcase builds, generates a map, switches to the piece gallery and the shop backdrops without errors.

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	var sc = load("res://scripts/debug/GraphicsShowcase.tscn").instantiate()
	add_child(sc)
	await get_tree().process_frame
	var waited = 0
	while (sc.map == null or sc._busy) and waited < 900:
		await get_tree().process_frame
		waited += 1
	_check("a map is generated on start", sc.map != null and is_instance_valid(sc.map) and sc.map.width > 0)
	_check("the type list covers the new and hypertech maps", "Ecumenopolis" in sc._types and "Mountains" in sc._types and "Hyper Hilly" in sc._types and sc._types.size() >= 40)
	sc._set_mode(1)
	await get_tree().process_frame
	_check("the gallery lists every catalogued piece", sc.piece_names().size() == SetPieces.PIECES.size())
	sc._era(1)
	sc._step(1)
	await get_tree().process_frame
	_check("the gallery filters by theme (%d)" % sc.piece_names().size(), sc.piece_names().size() < SetPieces.PIECES.size() and sc.piece_names().size() > 0)
	sc._set_mode(2)
	_check("the shop mode shows a backdrop", sc.shop_rect.texture != null and sc.shop_rect.visible)
	sc._set_mode(0)
	sc.type_index = sc._types.find("Hyper Mountains")
	sc.era_index = 2
	sc._generate()
	await get_tree().process_frame
	waited = 0
	while sc._busy and waited < 1200:
		await get_tree().process_frame
		waited += 1
	_check("switching map and era regenerates (%s, %s)" % [sc.map.map_type, sc.map.era], sc.map.map_type == "Hyper Mountains" and sc.map.era == "no_mans_land" and sc.map.has_heights)
	print("GraphicsShowcaseCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
