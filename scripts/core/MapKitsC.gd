class_name MapKitsC
extends RefCounted

# Map builders, part C: terrain with height. Hilly (low rolling hills that block shots fired from the valley, slow climbers and
# speed descenders) and Mountains (ridges and impassable peaks that channel the fight into valleys; explosions stay in the valley
# they land in plus what they can see). Heights live in MapGenerator.heights (see slope_mult, los_clear, ProjectileBatchPool).

const BT = MapKits.BT

# ---- Hilly -------------------------------------------------------------------------------------------------------------------
static func hilly(m) -> void:
	var w = m.width
	var h = m.height
	m.init_heights()
	for y in range(h):
		for x in range(w):
			var n = MapKits.noise_at(m, x, y, 0.03) * 0.6 + MapKits.noise_at(m, x + 900, y, 0.07) * 0.4
			var d = Vector2(x - w / 2.0, y - h / 2.0).length()
			var level = clampi(int((n + 0.15) * 7.0), 0, 4)
			if d < 22.0:
				level = mini(level, 1) # a gentle start
			m.set_height(x, y, level)
			m.terrain[y][x] = BT["FOREST"] if (level >= 3 and MapKits.moisture_at(m, x, y, 0.05) > 0.0) else BT["GRASS"]
	for y in range(5, h - 5):
		for x in range(5, w - 5):
			var lv = m.height_level(x, y)
			if m.terrain[y][x] == BT["FOREST"] and randf() < 0.2:
				MapKits.put_obstacle(m, x, y, "Tree", 8.0)
			elif lv == 0 and randf() < 0.004:
				MapKits.put_obstacle(m, x, y, "Boulder", 8.0)
	MapKits.scatter_pieces(m, MapKits.themes("Hilly", m.era), 44, Rect2i(5, 5, w - 10, h - 10), 1, 60)
	# hold points on the hilltops: the high ground is worth fighting for
	var tops = _peaks(m, 5, 4)
	for p in tops:
		MapKits.add_zone(m, "fort", p.x, p.y)
	MapKits.add_zone(m, "village", w / 2 + 40, h / 2 + 20)
	for i in range(int(w * h / 1500)):
		MapKits.add_decor(m, randi_range(5, w - 6), randi_range(5, h - 6), "grass_tuft")

# ---- Mountains --------------------------------------------------------------------------------------------------------------------
static func mountains(m) -> void:
	var w = m.width
	var h = m.height
	m.init_heights()
	for y in range(h):
		for x in range(w):
			var n = MapKits.noise_at(m, x, y, 0.018)
			var ridged = clampf(1.0 - absf(n) * 2.0, 0.0, 1.0) # high along the zero-crossings of the noise: long ridge lines
			var level = clampi(int(pow(ridged, 1.6) * 10.0), 0, 9)
			var d = Vector2(x - w / 2.0, y - h / 2.0).length()
			if d < 30.0:
				level = int(float(level) * clampf((d - 12.0) / 18.0, 0.0, 1.0)) # a valley floor round the start
			m.set_height(x, y, level)
			if level <= 1:
				m.terrain[y][x] = BT["GRASS"]
			elif level <= 4:
				m.terrain[y][x] = BT["FOREST"]
			elif level <= 7:
				m.terrain[y][x] = BT["DESERT"] # bare rock
			else:
				m.terrain[y][x] = BT["TUNDRA"] # snow-capped
				m.snow_cells[Vector2i(x, y)] = true
				MapKits.add_decor(m, x, y, "snow")
				if level >= 9 or (level >= 8 and ((x * 7 + y * 13) % 5) != 0):
					m.obstacles[Vector2i(x, y)] = "Wall" # impassable peaks
			if level >= 6 and level <= 7 and randf() < 0.3:
				m.snow_cells[Vector2i(x, y)] = true
				MapKits.add_decor(m, x, y, "snow")
	for y in range(5, h - 5):
		for x in range(5, w - 5):
			if m.terrain[y][x] == BT["FOREST"] and randf() < 0.22:
				MapKits.put_obstacle(m, x, y, "Tree", 8.0)
	# the valleys are where the fight is: pieces and hold points go on low ground
	var valley = Rect2i(5, 5, w - 10, h - 10)
	MapKits.scatter_pieces(m, MapKits.themes("Mountains", m.era), 36, valley, 1, 80)
	var lows: Array = []
	for i in range(400):
		var x2 = randi_range(10, w - 10)
		var y2 = randi_range(10, h - 10)
		if m.height_level(x2, y2) <= 1 and not m.obstacles.has(Vector2i(x2, y2)) and Vector2(x2 - w / 2.0, y2 - h / 2.0).length() > 40.0:
			lows.append(Vector2i(x2, y2))
		if lows.size() >= 4:
			break
	for p in lows:
		MapKits.add_zone(m, "fort", p.x, p.y)
	MapKits.add_zone(m, "village", w / 2 + 30, h / 2 - 30)

# The `count` highest, well-separated points of the map (at least `min_level`), for hold points on hilltops.
static func _peaks(m, count: int, min_level: int) -> Array:
	var out: Array = []
	var tries = 0
	while out.size() < count and tries < 4000:
		tries += 1
		var x = randi_range(15, m.width - 15)
		var y = randi_range(15, m.height - 15)
		if m.height_level(x, y) < min_level or m.obstacles.has(Vector2i(x, y)) or Vector2(x - m.width / 2.0, y - m.height / 2.0).length() < 40.0:
			continue
		var ok = true
		for q in out:
			if Vector2(q.x - x, q.y - y).length() < 55.0:
				ok = false
				break
		if ok:
			out.append(Vector2i(x, y))
	return out
