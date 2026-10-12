class_name MapKits
extends RefCounted

# Builders for the data-driven map types in MapTypes. MapGenerator calls three hooks for a MapTypes map:
#   prepare(m)          resolve the war era
#   base_biome(m, x, y) the biome under each tile (the terrain pass)
#   build(m)            everything else: shaping, roads, set pieces, obstacles, decor, objective zones
# Builders only write m.terrain / m.obstacles / m.ruin_specs / m.zones / m.decor; the generator's usual shallows, pocket
# carving and collision/nav passes run afterwards, so a builder never has to guarantee connectivity.
# Two more files hold the builders: MapKitsA (urban, coast, swamp, poppies) and others added as they are written.

const BT = {"GRASS": 0, "WATER": 1, "DESERT": 2, "FOREST": 3, "TUNDRA": 4, "VOLCANO": 5, "DUNGEON": 6, "ROAD": 7, "FLOOR": 8, "SHALLOW": 9}
const KEEPOUT = 12.0 # tiles around the player's spawn kept clear of set pieces

# ---- hooks --------------------------------------------------------------------------------------------------------

static func prepare(m) -> void:
	m.era = m.era_override if m.era_override != "" else MapTypes.roll_era(m.map_type, randf())

static func base_biome(m, x: int, y: int) -> int:
	match m.map_type:
		"Urban": return BT["FLOOR"]
		"Islands": return BT["WATER"]
		"Swamp", "Dense Forest": return BT["FOREST"]
		"Desert Arches": return BT["DESERT"]
		"Hydrothermal Park": return BT["TUNDRA"]
		"Caves", "Crypt", "Keep": return BT["DUNGEON"]
	return BT["GRASS"]

static func build(m) -> void:
	m.decor.clear()
	m.hazard_spots.clear()
	match m.map_type:
		"Urban": MapKitsA.urban(m)
		"Lakelands": MapKitsA.lakelands(m)
		"Islands": MapKitsA.islands(m)
		"Beach": MapKitsA.beach(m)
		"Swamp": MapKitsA.swamp(m)
		"Poppy Fields": MapKitsA.poppy_fields(m)
		"Colosseum": MapKitsB.colosseum(m)
		"Sports Arena": MapKitsB.sports_arena(m)
		"Military Base": MapKitsB.military_base(m)
		"Munitions Range": MapKitsB.munitions_range(m)
		"Desert Arches": MapKitsB.desert_arches(m)
		"Dense Forest": MapKitsB.dense_forest(m)
		"Hydrothermal Park": MapKitsB.hydrothermal(m)
		"Caves": MapKitsB.caves(m)
		"Crypt": MapKitsB.interior(m, "crypt")
		"Keep": MapKitsB.interior(m, "keep")
		"Dreamscape": MapKitsB.dreamscape(m)

# ---- shared helpers -----------------------------------------------------------------------------------------------

static func in_keepout(m, x: int, y: int, r: float = KEEPOUT) -> bool:
	return Vector2(x - m.width / 2.0, y - m.height / 2.0).length() < r

static func in_bounds(m, x: int, y: int, margin: int = 3) -> bool:
	return x >= margin and y >= margin and x < m.width - margin and y < m.height - margin

static func set_terrain(m, x: int, y: int, biome: int) -> void:
	if x >= 0 and y >= 0 and x < m.width and y < m.height:
		m.terrain[y][x] = biome

static func fill(m, r: Rect2i, biome: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			set_terrain(m, x, y, biome)

static func put_obstacle(m, x: int, y: int, name: String, clear_r: float = 5.0) -> bool:
	if not in_bounds(m, x, y, 2) or in_keepout(m, x, y, clear_r):
		return false
	var b = m.terrain[y][x]
	if b == BT["WATER"] or m.obstacles.has(Vector2i(x, y)):
		return false
	m.obstacles[Vector2i(x, y)] = name
	return true

static func add_decor(m, x: int, y: int, kind: String) -> void:
	if x >= 0 and y >= 0 and x < m.width and y < m.height and (m.terrain[y][x] != BT["WATER"] or kind.begins_with("pool_")):
		m.decor[Vector2i(x, y)] = kind

static func noise_at(m, x: int, y: int, scale: float) -> float:
	return m.noise.get_noise_2d(x * scale / 0.05, y * scale / 0.05)

static func moisture_at(m, x: int, y: int, scale: float) -> float:
	return m.moisture_noise.get_noise_2d(x * scale / 0.04, y * scale / 0.04)

# Straight painted line (roads, trenches, causeways): `thick` tiles wide.
static func paint_line(m, a: Vector2, b: Vector2, thick: int, biome: int) -> void:
	var length = a.distance_to(b)
	var steps = maxi(1, int(length))
	for i in range(steps + 1):
		var p = a.lerp(b, float(i) / float(steps))
		for dy in range(-thick / 2, thick - thick / 2):
			for dx in range(-thick / 2, thick - thick / 2):
				set_terrain(m, int(p.x) + dx, int(p.y) + dy, biome)

# Is the w x h footprint (plus `margin` tiles around it) free for a set piece?
static func rect_free(m, x: int, y: int, w: int, h: int, margin: int = 1, keepout_r: float = KEEPOUT) -> bool:
	for yy in range(y - margin, y + h + margin):
		for xx in range(x - margin, x + w + margin):
			if not in_bounds(m, xx, yy, 3):
				return false
			var b = m.terrain[yy][xx]
			if b == BT["WATER"] or m.obstacles.has(Vector2i(xx, yy)):
				return false
	# footprint corners and edges against the spawn keepout (closest point on the rect to the centre)
	var cxp = clampf(m.width / 2.0, float(x), float(x + w - 1))
	var cyp = clampf(m.height / 2.0, float(y), float(y + h - 1))
	return Vector2(cxp - m.width / 2.0, cyp - m.height / 2.0).length() >= keepout_r

static func place_piece(m, style: String, x: int, y: int, w: int, h: int, margin: int = 1) -> bool:
	if not rect_free(m, x, y, w, h, margin):
		return false
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			m.obstacles[Vector2i(xx, yy)] = "RuinPart"
	m.ruin_specs.append({"x": x, "y": y, "w": w, "h": h, "type": style, "era": m.era})
	return true

# Scatters up to `count` library pieces from `themes` inside `region`; returns how many were placed.
static func scatter_pieces(m, themes: Array, count: int, region: Rect2i, margin: int = 1, tries_per: int = 30) -> int:
	var placed = 0
	var tries = 0
	while placed < count and tries < count * tries_per:
		tries += 1
		var style = SetPieces.random_piece(themes, randf())
		if style == "ruin":
			continue
		var sz = SetPieces.random_size(style, randf(), randf())
		var x = region.position.x + randi() % maxi(1, region.size.x - sz.x + 1)
		var y = region.position.y + randi() % maxi(1, region.size.y - sz.y + 1)
		if place_piece(m, style, x, y, sz.x, sz.y, margin):
			placed += 1
	return placed

static func add_zone(m, kind: String, x: int, y: int, r: float = 8.0) -> void:
	m.zones.append({"kind": kind, "pos": Vector2(x, y), "r": r})

# Themes for a map type in an era (the library themes the map draws from).
static func themes(map_type: String, era: String) -> Array:
	var t: Array = []
	match map_type:
		"Urban":
			t = ["urban", "art_deco", "monument"]
			match era:
				"prewar": t += ["gothic", "power"]
				"skirmish": t += ["fortification", "camp", "gothic"]
				"no_mans_land": t += ["fortification", "wreck", "camp"]
				"apocalypse": t += ["wreck", "apocalypse_relic", "kitbash"]
		"Lakelands":
			t = ["agricultural", "coast", "power"]
			if era == "prewar": t += ["art_deco"]
			if era in ["skirmish", "no_mans_land"]: t += ["camp", "wreck"]
			if era == "apocalypse": t += ["wreck", "gothic"]
		"Islands":
			t = ["coast", "ancient", "gothic"]
			if era in ["skirmish", "no_mans_land"]: t += ["fortification", "wreck"]
			if era == "apocalypse": t += ["wreck", "apocalypse_relic"]
		"Beach":
			match era:
				"prewar": t = ["coast", "art_deco", "urban"]
				"skirmish": t = ["coast", "fortification", "camp"]
				"no_mans_land": t = ["fortification", "wreck", "camp"]
				"apocalypse": t = ["wreck", "fortification", "apocalypse_relic"]
		"Swamp":
			t = ["swamp", "gothic", "monument"]
			if era in ["skirmish", "no_mans_land"]: t += ["wreck", "camp"]
			if era == "apocalypse": t += ["wreck", "apocalypse_relic", "surreal"]
		"Poppy Fields":
			match era:
				"prewar": t = ["oz", "agricultural"]
				"skirmish": t = ["agricultural", "camp", "fortification"]
				"no_mans_land": t = ["fortification", "wreck", "camp", "gothic"]
				"apocalypse": t = ["wreck", "gothic", "apocalypse_relic"]
		"Colosseum": t = ["arena", "ancient", "monument"]
		"Sports Arena": t = ["urban", "art_deco"]
		"Military Base": t = ["military", "fortification", "power", "camp"]
		"Munitions Range": t = ["range", "military", "camp"]
		"Desert Arches": t = ["ancient", "desert_rock"]
		"Dense Forest": t = ["gothic", "camp", "agricultural"]
		"Hydrothermal Park": t = ["urban", "art_deco", "coast"] if era == "prewar" else ["camp", "wreck", "fortification"]
		"Caves": t = ["cave", "dungeon", "ancient"]
		"Crypt": t = ["dungeon", "gothic"]
		"Keep": t = ["dungeon", "gothic"]
		"Dreamscape": t = ["surreal", "kitbash"]
		_:
			t = ["urban"]
	return t

# Turns m.hazard_spots into hazard nodes (called by MapGenerator once the map is built).
static func spawn_hazards(m) -> int:
	var made = 0
	for spot in m.hazard_spots:
		var node: Node2D = null
		match spot["kind"]:
			"geyser":
				node = Geyser.new()
			"uxo":
				node = UnexplodedOrdnance.new()
		if node == null:
			continue
		node.global_position = Vector2(spot["pos"].x * m.tile_size + m.tile_size / 2.0, spot["pos"].y * m.tile_size + m.tile_size / 2.0)
		m.add_child(node)
		made += 1
	return made
