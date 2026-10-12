extends Node

# Every data-driven map type (MapTypes) generates: spawn clear and on the main continent, a big connected playable area,
# set pieces with real styles and valid eras that never overlap, hazard spots and zones in bounds, and the era stays what
# was asked. Each type runs in a rotating era so all four eras are exercised across the list; the three flagship types run
# all four.

const MapGen = preload("res://scripts/core/MapGenerator.gd")
const BT = MapGen.BiomeType

var failures := 0
func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _run(t: String, era: String) -> void:
	var m = MapGen.new()
	m.map_type = t
	m.era_override = era
	m.map_seed = 20261012
	add_child(m)
	await get_tree().process_frame
	var tag = "%s/%s" % [t, era]
	_check("%s: future flag matches the name" % tag, m.future == MapTypes.is_future(t))
	var c = Vector2i(m.width / 2, m.height / 2)
	_check("%s: size matches the registry" % tag, Vector2i(m.width, m.height) == MapTypes.size(t))
	_check("%s: the era is what was asked" % tag, m.era == era)
	_check("%s: spawn centre walkable, clear and on the main continent" % tag, not m.obstacles.has(c) and m.terrain[c.y][c.x] != BT.WATER and m.main_continent_tiles.has(c))
	var clear = true
	for dy in range(-5, 6):
		for dx in range(-5, 6):
			if m.obstacles.has(Vector2i(c.x + dx, c.y + dy)):
				clear = false
	_check("%s: nothing within 5 tiles of the spawn" % tag, clear)
	_check("%s: a big connected playable area (%d tiles)" % [tag, m.main_continent_tiles.size()], m.main_continent_tiles.size() > m.width * m.height * 0.12)
	var bad_style = []
	var bad_cells = 0
	var seen := {}
	var overlaps = 0
	for spec in m.ruin_specs:
		if not SetPieceArt.has_style(spec["type"]) or not SetPieceEra.is_era(spec["era"]):
			bad_style.append(spec["type"])
		for yy in range(spec.y, spec.y + spec.h):
			for xx in range(spec.x, spec.x + spec.w):
				var k = Vector2i(xx, yy)
				if seen.has(k):
					overlaps += 1
				seen[k] = true
				if m.obstacles.get(k, "") != "RuinPart":
					bad_cells += 1
	_check("%s: every piece has art and a valid era (%s)" % [tag, str(bad_style)], bad_style.is_empty())
	_check("%s: pieces never overlap (%d) and own their cells (%d lost to connectivity corridors)" % [tag, overlaps, bad_cells], overlaps == 0 and bad_cells <= maxi(8, seen.size() / 100))
	var tree_count = 0
	for k in m.obstacles:
		if m.obstacles[k] == "Tree":
			tree_count += 1
	_check("%s: a sane number of trees (%d, cap %d)" % [tag, tree_count, MapKits.MAX_TREES], tree_count <= MapKits.MAX_TREES + 300)
	var min_pieces = {"Islands": 15, "Lakelands": 15, "Swamp": 15, "Dense Forest": 10, "Hydrothermal Park": 8}.get(MapTypes.base(t), 25)
	_check("%s: enough set pieces (%d)" % [tag, m.ruin_specs.size()], m.ruin_specs.size() >= min_pieces)
	var spots_ok = true
	for s in m.hazard_spots:
		if s["pos"].x < 0 or s["pos"].y < 0 or s["pos"].x >= m.width or s["pos"].y >= m.height:
			spots_ok = false
	_check("%s: hazard spots in bounds (%d)" % [tag, m.hazard_spots.size()], spots_ok)
	if MapTypes.base(t) in ["Hydrothermal Park"]:
		_check("%s: has geysers" % tag, m.hazard_spots.any(func(s): return s["kind"] == "geyser"))
	if MapTypes.base(t) == "Munitions Range":
		_check("%s: has unexploded ordnance" % tag, m.hazard_spots.any(func(s): return s["kind"] == "uxo"))
	var zones_ok = true
	for z in m.zones:
		if z["pos"].x < 0 or z["pos"].y < 0 or z["pos"].x >= m.width or z["pos"].y >= m.height:
			zones_ok = false
	_check("%s: zones in bounds (%d)" % [tag, m.zones.size()], zones_ok)
	m.queue_free()
	await get_tree().process_frame

func _ready():
	var names = MapTypes.names()
	var flagship = ["Urban", "Beach", "Poppy Fields", "Ecumenopolis"]
	for i in range(names.size()):
		var t: String = names[i]
		if t in flagship:
			for e in MapTypes.ERAS:
				await _run(t, e)
		else:
			await _run(t, MapTypes.ERAS[i % 4])
	_check("every type has a hypertech twin", MapTypes.names().size() == MapTypes.classic_names().size() * 2 and "Ecumenopolis" in MapTypes.names() and "Hyper Beach" in MapTypes.names())
	_check("hyper names resolve to their base", MapTypes.base("Ecumenopolis") == "Urban" and MapTypes.base("Hyper Swamp") == "Swamp" and MapTypes.base("Swamp") == "Swamp")
	_check("era rolls are weighted and cover every era", MapTypes.roll_era("Beach", 0.0) == "prewar" and MapTypes.roll_era("Beach", 0.99) == "apocalypse" and MapTypes.roll_era("Beach", 0.55) == "no_mans_land")
	_check("tints darken with the war", MapTypes.tint("Urban", "apocalypse").r < MapTypes.tint("Urban", "prewar").r)
	print("map types check done, failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
