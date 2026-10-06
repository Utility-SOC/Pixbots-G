extends Node

const MapGen = preload("res://scripts/core/MapGenerator.gd")
const Props = preload("res://scripts/visuals/BiomeProps.gd")
var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	var atlas = Props.make_atlas()
	_check("atlas is 8 cells wide", atlas.get_width() == Props.CELL * 8 and atlas.get_height() == Props.CELL)
	var img = atlas.get_image()
	if img != null:
		for k in range(8):
			var filled = 0
			for y in range(Props.CELL):
				for x in range(Props.CELL):
					if img.get_pixel(k * Props.CELL + x, y).a > 0.5:
						filled += 1
			_check("shape %d has pixels (%d)" % [k, filled], filled > 8)
	for t in ["Normal", "Forest", "Volcano", "Tundra", "Desert", "Open Field"]:
		var m = MapGen.new()
		m.map_type = t
		add_child(m)
		await get_tree().process_frame
		var p = m.get_node_or_null("BiomeProps")
		_check("%s: props were scattered (%d)" % [t, p.count() if p else -1], p != null and p.count() > 150 and p.count() <= Props.MAX_PROPS)
		m.queue_free()
		await get_tree().process_frame
	for t in ["Tabletop", "FightShovel", "Dungeon"]:
		var m = MapGen.new()
		m.map_type = t
		add_child(m)
		await get_tree().process_frame
		var p = m.get_node_or_null("BiomeProps")
		_check("%s: carries its own scenery, no ambient props" % t, p == null or p.count() == 0)
		m.queue_free()
		await get_tree().process_frame
	# deterministic for a given seed
	var a = Props.new(); add_child(a)
	var m2 = MapGen.new(); m2.map_type = "Forest"; add_child(m2)
	await get_tree().process_frame
	var b = Props.new(); add_child(b)
	var n1 = a.build(m2, 1234)
	var n2 = b.build(m2, 1234)
	_check("same seed, same props (%d)" % n1, n1 == n2 and a._pos == b._pos)
	# coverage: with a cap, props must still reach the lower half of the map
	var low = 0
	for q in a._pos:
		if q.y > m2.height * m2.tile_size * 0.5:
			low += 1
	_check("props cover the whole map, not just the top rows (%d of %d in the lower half)" % [low, a._pos.size()], low > a._pos.size() * 0.3)
	print("biome props check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
