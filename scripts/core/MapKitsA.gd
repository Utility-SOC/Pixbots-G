class_name MapKitsA
extends RefCounted

# Map builders, part A: Urban, Lakelands, Islands, Beach, Swamp, Poppy Fields. See MapKits for the contract.

const BT = MapKits.BT

# ---- Urban ---------------------------------------------------------------------------------------------------------
static func urban(m) -> void:
	var cx = m.width / 2
	var cy = m.height / 2
	var bw = 34
	var bh = 26
	var street = 5
	var th = MapKits.themes("Urban", m.era)
	# streets: a grid with the spawn at an intersection; every third street is a wider avenue
	for y in range(m.height):
		for x in range(m.width):
			var kx = int(floor(float(x - cx + bw / 2) / float(bw)))
			var ky = int(floor(float(y - cy + bh / 2) / float(bh)))
			var dx = x - cx - kx * bw
			var dy = y - cy - ky * bh
			var wide_x = 3 if posmod(kx, 3) == 0 else 2
			var wide_y = 3 if posmod(ky, 3) == 0 else 2
			if absi(dx) <= wide_x or absi(dy) <= wide_y:
				m.terrain[y][x] = BT["ROAD"]
	for kx in range(-7, 8):
		for ky in range(-6, 7):
			var x0 = cx + kx * bw + 5
			var y0 = cy + ky * bh + 5
			var rect = Rect2i(x0, y0, bw - 10, bh - 10)
			if rect.position.x < 5 or rect.position.y < 5 or rect.end.x > m.width - 5 or rect.end.y > m.height - 5:
				continue
			if kx == 0 and ky == 0:
				continue
			var roll = randf()
			if roll < 0.12:
				_park(m, rect)
			elif roll < 0.22:
				_plaza(m, rect)
			elif roll < 0.32:
				MapKits.scatter_pieces(m, ["industrial", "power", "wreck"] if m.era != "prewar" else ["industrial", "power"], 9, rect, 1, 80)
			elif roll < 0.40:
				MapKits.scatter_pieces(m, ["gothic", "monument"], 7, rect, 1, 80)
			elif roll < 0.45:
				pass # an empty lot: rubble and camps arrive with the era below
			else:
				MapKits.scatter_pieces(m, th, maxi(4, rect.size.x * rect.size.y / 26), rect, 1, 80)
	_urban_era(m, cx, cy, bw, bh)

static func _park(m, rect: Rect2i) -> void:
	MapKits.fill(m, rect, BT["GRASS"])
	for i in range(rect.size.x * rect.size.y / 6):
		MapKits.put_obstacle(m, rect.position.x + randi() % rect.size.x, rect.position.y + randi() % rect.size.y, "Tree")
	MapKits.scatter_pieces(m, ["monument"], 2, rect, 1)

static func _plaza(m, rect: Rect2i) -> void:
	MapKits.scatter_pieces(m, ["monument", "arena"], 3, rect, 2)
	var c = rect.get_center()
	if not MapKits.in_keepout(m, c.x, c.y, 30.0):
		MapKits.add_zone(m, "fort" if randf() < 0.55 else "village", c.x, c.y)

static func _urban_era(m, cx: int, cy: int, bw: int, bh: int) -> void:
	match m.era:
		"skirmish":
			for i in range(14): # barricades across streets, with a gap
				var x = cx + (randi_range(-6, 6)) * bw + randi_range(-2, 2)
				var y = cy + randi_range(-5, 5) * bh + randi_range(-14, 14)
				for k in range(-4, 5):
					if absi(k) > 1:
						MapKits.put_obstacle(m, x + k, y, "Boulder", 10.0)
		"no_mans_land":
			for y in range(5, m.height - 5):
				for x in range(5, m.width - 5):
					if m.terrain[y][x] == BT["ROAD"] and not m.obstacles.has(Vector2i(x, y)):
						var r = randf()
						if r < 0.012:
							MapKits.put_obstacle(m, x, y, "Boulder", 10.0) # rubble
						elif r < 0.05:
							MapKits.add_decor(m, x, y, "crater" if r < 0.02 else "debris")
						elif r < 0.058:
							MapKits.add_decor(m, x, y, "wire")
		"apocalypse":
			for y in range(5, m.height - 5):
				for x in range(5, m.width - 5):
					if not m.obstacles.has(Vector2i(x, y)) and m.terrain[y][x] in [BT["ROAD"], BT["FLOOR"]]:
						var r2 = randf()
						if r2 < 0.012:
							MapKits.put_obstacle(m, x, y, "Tree", 10.0) # trees pushing through the asphalt
						elif r2 < 0.06:
							MapKits.add_decor(m, x, y, "cracks" if r2 < 0.035 else "moss")

# ---- Lakelands -----------------------------------------------------------------------------------------------------
static func lakelands(m) -> void:
	var w = m.width
	var h = m.height
	for y in range(h):
		for x in range(w):
			var n = MapKits.noise_at(m, x, y, 0.035)
			var dist = Vector2(x - w / 2.0, y - h / 2.0).length()
			var edge = mini(mini(x, w - 1 - x), mini(y, h - 1 - y))
			if n > 0.1 and dist > 22.0 and edge > 6:
				m.terrain[y][x] = BT["WATER"]
			elif MapKits.moisture_at(m, x, y, 0.04) > 0.25:
				m.terrain[y][x] = BT["FOREST"]
			else:
				m.terrain[y][x] = BT["GRASS"]
	for y in range(5, h - 5):
		for x in range(5, w - 5):
			if m.terrain[y][x] == BT["FOREST"] and randf() < 0.26:
				MapKits.put_obstacle(m, x, y, "Tree", 8.0)
			elif m.terrain[y][x] == BT["GRASS"] and randf() < 0.012:
				MapKits.put_obstacle(m, x, y, "Boulder", 8.0)
	MapKits.scatter_pieces(m, MapKits.themes("Lakelands", m.era), 46, Rect2i(5, 5, w - 10, h - 10), 1)
	_era_ground(m, 0.03)

# ---- Islands -------------------------------------------------------------------------------------------------------
static func islands(m) -> void:
	var w = m.width
	var h = m.height
	for y in range(h):
		for x in range(w):
			var n = MapKits.noise_at(m, x, y, 0.045)
			var dist = Vector2(x - w / 2.0, y - h / 2.0).length()
			var edge = mini(mini(x, w - 1 - x), mini(y, h - 1 - y))
			if (n > 0.12 or dist < 22.0) and edge > 5:
				var wet = MapKits.moisture_at(m, x, y, 0.04)
				m.terrain[y][x] = BT["FOREST"] if wet > 0.2 else (BT["DESERT"] if wet < -0.25 else BT["GRASS"])
			else:
				# the sea: wadeable shoals with deep channels cut through, so the islands are separate but not unreachable
				m.terrain[y][x] = BT["WATER"] if MapKits.noise_at(m, x + 400, y, 0.03) > 0.22 or edge <= 5 else BT["SHALLOW"]
	# a sandy ring where land meets water
	for y in range(2, h - 2):
		for x in range(2, w - 2):
			if m.terrain[y][x] != BT["WATER"] and m.terrain[y][x] != BT["DESERT"]:
				for d in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
					if m.terrain[y + d.y][x + d.x] in [BT["WATER"], BT["SHALLOW"]]:
						m.terrain[y][x] = BT["DESERT"]
						break
	for y in range(5, h - 5):
		for x in range(5, w - 5):
			if m.terrain[y][x] == BT["FOREST"] and randf() < 0.24:
				MapKits.put_obstacle(m, x, y, "Tree", 8.0)
	MapKits.scatter_pieces(m, MapKits.themes("Islands", m.era), 40, Rect2i(5, 5, w - 10, h - 10), 1)
	_era_ground(m, 0.02)

# ---- Beach ---------------------------------------------------------------------------------------------------------
# Sea along the bottom, a sand band, a seawall, then bluffs. Prewar is a seaside resort; later eras are the same coast as a
# landing under fire (Normandy): hedgehogs in the surf, wire and craters on the sand, bunkers on the bluffs.
static func beach(m) -> void:
	var w = m.width
	var h = m.height
	var coast = int(h * 0.78)
	for x in range(w):
		var cy = coast + int(MapKits.noise_at(m, x, 0, 0.08) * 6.0)
		for y in range(h):
			if y >= cy:
				m.terrain[y][x] = BT["WATER"]
			elif y >= cy - 26:
				m.terrain[y][x] = BT["DESERT"]
			else:
				m.terrain[y][x] = BT["GRASS"]
	var wall_y = coast - 27
	for x in range(5, w - 5):
		if m.terrain[wall_y][x] != BT["WATER"] and (x % 38) > 5: # the seawall, with gaps (the draws)
			MapKits.put_obstacle(m, x, wall_y, "StoneWall", 2.0)
			MapKits.put_obstacle(m, x, wall_y - 1, "StoneWall", 2.0)
	var themes = MapKits.themes("Beach", m.era)
	var bluff = Rect2i(5, 5, w - 10, int(h * 0.25))
	var sand = Rect2i(5, coast - 24, w - 10, 20)
	match m.era:
		"prewar":
			MapKits.scatter_pieces(m, ["coast"], 26, sand, 1)
			MapKits.scatter_pieces(m, themes, 22, bluff, 1)
			MapKits.paint_line(m, Vector2(5, wall_y + 2), Vector2(w - 6, wall_y + 2), 3, BT["ROAD"]) # the boardwalk
		"skirmish":
			MapKits.scatter_pieces(m, ["coast"], 8, sand, 1)
			MapKits.scatter_pieces(m, themes, 20, bluff, 1)
			_surf_obstacles(m, coast, 0.5)
		_:
			MapKits.scatter_pieces(m, ["fortification", "military"], 40, bluff, 1, 60)
			MapKits.scatter_pieces(m, ["agricultural", "gothic", "monument"], 16, bluff, 1, 60)
			MapKits.scatter_pieces(m, ["wreck"] if m.era == "apocalypse" else ["wreck", "camp"], 14, Rect2i(5, coast - 40, w - 10, 38), 1)
			_surf_obstacles(m, coast, 1.0)
			for i in range(260):
				var x = randi_range(6, w - 7)
				var y = randi_range(coast - 24, coast - 1)
				MapKits.add_decor(m, x, y, ["crater", "wire", "debris", "bones"][randi() % 4])
	_bocage(m, wall_y)
	for i in range(int(w * 0.5)):
		var x2 = randi_range(6, w - 7)
		var y2 = randi_range(5, wall_y - 3)
		if m.terrain[y2][x2] == BT["GRASS"] and randf() < 0.4:
			MapKits.put_obstacle(m, x2, y2, "Tree" if randf() < 0.5 else "Boulder", 8.0)
	for k in range(4): # hold points on the beach and the bluffs
		MapKits.add_zone(m, "fort" if k % 2 == 0 else "village", int(w * (0.2 + 0.2 * k)), wall_y - 8 - (k % 2) * 14)

# Hedgerow field boundaries behind the bluffs (bocage): lines of trees with gateways, the cover that made inland fighting hard.
static func _bocage(m, wall_y: int) -> void:
	for y in range(18, wall_y - 14, 26):
		for x in range(6, m.width - 6):
			if (x % 30) > 4 and randf() < 0.85:
				MapKits.put_obstacle(m, x, y, "Tree", 9.0)
	for x in range(30, m.width - 30, 44):
		for y in range(6, wall_y - 16):
			if (y % 22) > 4 and randf() < 0.85:
				MapKits.put_obstacle(m, x, y, "Tree", 9.0)

static func _surf_obstacles(m, coast: int, density: float) -> void:
	# rows of steel hedgehogs and stakes in the shallows, in the manner of the beach obstacle belts
	for row in range(3):
		var y = coast - 2 + row * 3
		for x in range(8, m.width - 8, 5):
			if randf() < 0.55 * density and m.terrain[mini(y, m.height - 1)][x] != BT["GRASS"]:
				m.obstacles[Vector2i(x, y)] = "IceBoulder" if row == 1 else "Boulder"

# ---- Swamp ---------------------------------------------------------------------------------------------------------
static func swamp(m) -> void:
	var w = m.width
	var h = m.height
	for y in range(h):
		for x in range(w):
			var n = MapKits.noise_at(m, x, y, 0.02)
			var dist = Vector2(x - w / 2.0, y - h / 2.0).length()
			if dist > 18.0 and n > 0.36:
				m.terrain[y][x] = BT["WATER"]
			elif n > 0.0:
				m.terrain[y][x] = BT["SHALLOW"] # bog: slow, loose ground
			else:
				m.terrain[y][x] = BT["FOREST"]
	MapKits.scatter_pieces(m, MapKits.themes("Swamp", m.era), 34, Rect2i(5, 5, w - 10, h - 10), 1, 60)
	for y in range(5, h - 5):
		for x in range(5, w - 5):
			if m.terrain[y][x] == BT["FOREST"] and randf() < 0.14:
				MapKits.put_obstacle(m, x, y, "Tree", 8.0)
			elif m.terrain[y][x] == BT["SHALLOW"] and randf() < 0.012:
				MapKits.put_obstacle(m, x, y, "Tree", 8.0) # cypress knees
	_era_ground(m, 0.04)

# ---- Poppy Fields ----------------------------------------------------------------------------------------------------
# Flanders in the war eras (trenches, wire, craters, poppies growing in the churned earth); prewar is Oz: a yellow brick
# road through the poppies to an emerald city.
static func poppy_fields(m) -> void:
	var w = m.width
	var h = m.height
	for y in range(h):
		for x in range(w):
			m.terrain[y][x] = BT["GRASS"]
			var p = MapKits.moisture_at(m, x, y, 0.05)
			if p > -0.1 and randf() < 0.55:
				MapKits.add_decor(m, x, y, "poppy_dense" if p > 0.2 else "poppy")
	if m.era == "prewar":
		_oz(m)
		return
	# two trench lines with wire in front of each, no man's land between
	for t in range(2):
		var y0 = int(h * (0.3 + 0.4 * t))
		var pts: Array = []
		for x in range(6, w - 6, 3):
			pts.append(Vector2(x, y0 + int(MapKits.noise_at(m, x, t * 40, 0.07) * 8.0)))
		for i in range(pts.size() - 1):
			MapKits.paint_line(m, pts[i], pts[i + 1], 2, BT["ROAD"])
			if i % 2 == 0:
				MapKits.put_obstacle(m, int(pts[i].x), int(pts[i].y) - 3, "Boulder", 6.0) # parapet sandbags
		var wy = y0 + (-9 if t == 0 else 9)
		for x in range(8, w - 8):
			if (x % 24) > 3:
				MapKits.add_decor(m, x, wy, "wire")
				if x % 6 == 0:
					MapKits.put_obstacle(m, x, wy, "Fence", 8.0)
	for k in range(3): # communication trenches linking the two lines
		var tx = int(w * (0.2 + 0.3 * k)) + randi_range(-6, 6)
		MapKits.paint_line(m, Vector2(tx, h * 0.3), Vector2(tx + randi_range(-8, 8), h * 0.7), 2, BT["ROAD"])
	for i in range(int(w * h / 4000)):
		MapKits.put_obstacle(m, randi_range(8, w - 8), randi_range(8, h - 8), "Tree", 12.0) # shattered trees
	var scatter = int(w * h / 900)
	for i in range(scatter):
		MapKits.add_decor(m, randi_range(5, w - 6), randi_range(5, h - 6), "crater" if randf() < 0.6 else "scorch")
	MapKits.scatter_pieces(m, MapKits.themes("Poppy Fields", m.era), 60, Rect2i(5, 5, w - 10, h - 10), 1, 60)
	for k in range(3):
		MapKits.add_zone(m, "fort" if k != 1 else "village", int(w * (0.25 + 0.25 * k)), int(h * (0.3 if k % 2 == 0 else 0.7)))

static func _oz(m) -> void:
	var w = m.width
	var h = m.height
	var a = Vector2(w / 2.0, h / 2.0)
	var pts: Array = [a]
	var x = a.x
	var y = a.y
	for i in range(22):
		x += 14.0
		y += sin(float(i) * 0.7) * 9.0
		pts.append(Vector2(minf(x, w - 14.0), clampf(y, 14.0, h - 14.0)))
	for i in range(pts.size() - 1):
		MapKits.paint_line(m, pts[i], pts[i + 1], 3, BT["ROAD"])
		var steps = int(pts[i].distance_to(pts[i + 1]))
		for s in range(steps):
			var p = pts[i].lerp(pts[i + 1], float(s) / float(maxi(1, steps)))
			for dy in range(-1, 2):
				MapKits.add_decor(m, int(p.x), int(p.y) + dy, "yellow_road")
	var end = pts[pts.size() - 1]
	for k in range(6): # the emerald city at the end of the road
		MapKits.place_piece(m, "emerald_tower", clampi(int(end.x) - 8 + (k % 3) * 6 - 12, 6, w - 12), clampi(int(end.y) - 14 + (k / 3) * 12, 6, h - 14), 4, 6, 1)
	MapKits.scatter_pieces(m, ["oz", "agricultural"], 24, Rect2i(5, 5, w - 10, h - 10), 1)
	MapKits.add_zone(m, "fort", int(end.x) - 6, int(end.y))
	MapKits.add_zone(m, "village", int(w * 0.3), int(h * 0.3))

# Era wear on open ground (moss and cracks later, scorch and wire in the war eras).
static func _era_ground(m, density: float) -> void:
	for i in range(int(m.width * m.height * density * 0.1)):
		var x = randi_range(5, m.width - 6)
		var y = randi_range(5, m.height - 6)
		match m.era:
			"skirmish": MapKits.add_decor(m, x, y, "scorch" if randf() < 0.3 else "grass_tuft")
			"no_mans_land": MapKits.add_decor(m, x, y, ["crater", "wire", "scorch", "debris"][randi() % 4])
			"apocalypse": MapKits.add_decor(m, x, y, ["moss", "cracks", "bones", "ash"][randi() % 4])
			_: MapKits.add_decor(m, x, y, "grass_tuft")
