extends Node

const MapGeneratorScript = preload("res://scripts/core/MapGenerator.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _gen(type: String, layout: String, seed_v: int):
	var m = MapGeneratorScript.new()
	m.map_type = type
	m.map_layout = layout
	m.map_seed = seed_v
	m.extra_scenery_enabled = false # these checks are about the macro layouts alone
	add_child(m)
	return m

func _ready():
	var base = _gen("Open Field", "none", 31)
	_check("none layout adds nothing on Open Field", base.obstacles.size() == 0 and base.layout_name == "none")
	var seen_layouts = {}
	for layout in MapGeneratorScript.LAYOUTS:
		if layout == "none":
			continue
		var m = _gen("Open Field", layout, 31)
		seen_layouts[layout] = true
		_check("%s applied (%s)" % [layout, m.layout_name], m.layout_name == layout)
		var changed = m.obstacles.size() > 0 or m.water_fraction > 0.0
		_check("%s changes the map (obstacles=%d water=%.3f)" % [layout, m.obstacles.size(), m.water_fraction], changed)
		var c = Vector2i(m.width / 2, m.height / 2)
		_check("%s keeps the spawn centre clear" % layout, not m.obstacles.has(c) and m.terrain[c.y][c.x] != MapGeneratorScript.BiomeType.WATER)
		var reach = m.main_continent_tiles.size()
		_check("%s leaves a big connected area (%d tiles)" % [layout, reach], reach >= m.width * m.height * 0.3)
		_check("%s centre is on the main continent" % layout, m.main_continent_tiles.has(c))
		var m2 = _gen("Open Field", layout, 31)
		_check("%s is deterministic for a seed" % layout, m2.obstacles.size() == m.obstacles.size() and abs(m2.water_fraction - m.water_fraction) < 1e-9)
		m.queue_free()
		m2.queue_free()
		await get_tree().process_frame
	# Non-layout types are untouched
	var tt = _gen("Tabletop", "river", 5)
	_check("Tabletop ignores layouts", tt.layout_name == "none")
	# auto picks vary across seeds
	var picks = {}
	for sd in range(1, 9):
		var a = _gen("Forest", "auto", sd * 97)
		picks[a.layout_name] = true
		a.queue_free()
		await get_tree().process_frame
	_check("auto roll varies (%s)" % str(picks.keys()), picks.size() >= 2)
	print("map layout check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
