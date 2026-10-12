class_name MapKitsB
extends RefCounted

# Map builders, part B: arenas, military, wild terrain and interiors. See MapKits for the contract.

const BT = MapKits.BT
const MapStructure = preload("res://scripts/core/MapStructure.gd")

static func _ellipse(m, cx: float, cy: float, a: float, b: float, x: int, y: int) -> float:
	return pow((x - cx) / a, 2.0) + pow((y - cy) / b, 2.0)

# ---- Colosseum (Elite Four arena) ------------------------------------------------------------------------------------
static func colosseum(m) -> void:
	var w = m.width
	var h = m.height
	var cx = w / 2.0
	var cy = h / 2.0
	var a = 62.0
	var b = 40.0
	for y in range(h):
		for x in range(w):
			var e = _ellipse(m, cx, cy, a, b, x, y)
			if e <= 1.0:
				m.terrain[y][x] = BT["DESERT"] # the sand
			elif e <= pow((a + 16.0) / a, 2.0):
				m.terrain[y][x] = BT["FLOOR"] # the stands
			else:
				m.terrain[y][x] = BT["GRASS"]
	# the arena wall, with four gates
	for y in range(h):
		for x in range(w):
			var e2 = _ellipse(m, cx, cy, a, b, x, y)
			if e2 > 0.95 and e2 <= 1.08:
				var dx = absi(x - int(cx))
				var dy = absi(y - int(cy))
				if (dx > 5 or dy < 14) and (dy > 5 or dx < 30):
					if m.era == "apocalypse" and randf() < 0.22:
						continue # crumbled sections
					m.obstacles[Vector2i(x, y)] = "StoneWall"
	# the stands: colonnades and grandstands round the rim
	var th = ["arena", "ancient", "monument"]
	for k in range(36):
		var ang = TAU * float(k) / 36.0
		var px = int(cx + cos(ang) * (a + 6.0)) - 3
		var py = int(cy + sin(ang) * (b + 6.0)) - 1
		var style = "colonnade" if k % 3 != 0 else ("column_ruin" if m.era != "prewar" else "statue")
		var sz = SetPieces.random_size(style, 0.0, 0.0)
		MapKits.place_piece(m, style, px, py, sz.x, sz.y, 0)
	# cover on the sand
	for k in range(14):
		var ang2 = randf() * TAU
		var rr = randf_range(0.25, 0.8)
		var style2 = ["column_ruin", "statue", "pillar_cluster", "sandstone_arch"][randi() % 4]
		var sz2 = SetPieces.random_size(style2, randf(), randf())
		MapKits.place_piece(m, style2, int(cx + cos(ang2) * a * rr) - sz2.x / 2, int(cy + sin(ang2) * b * rr) - sz2.y / 2, sz2.x, sz2.y, 1)
	for g in [Vector2(cx - a - 14, cy), Vector2(cx + a + 14, cy)]: # triumphal arches outside the east and west gates
		MapKits.place_piece(m, "triumphal_arch", int(g.x) - 3, int(g.y) - 3, 5, 5, 0)
	MapKits.scatter_pieces(m, th, 10, Rect2i(8, 8, w - 16, 18), 1)
	MapKits.scatter_pieces(m, th, 10, Rect2i(8, h - 26, w - 16, 18), 1)
	MapKits.add_zone(m, "fort", int(cx - 38), int(cy))
	MapKits.add_zone(m, "fort", int(cx + 38), int(cy))
	_era_dressing(m, Rect2i(int(cx - a), int(cy - b), int(a * 2), int(b * 2)))

# ---- Sports Arena -------------------------------------------------------------------------------------------------------
static func sports_arena(m) -> void:
	var w = m.width
	var h = m.height
	var cx = w / 2
	var cy = h / 2
	var pitch = Rect2i(cx - 34, cy - 20, 68, 40)
	var track = pitch.grow(7)
	var concourse = track.grow(12)
	MapKits.fill(m, concourse, BT["FLOOR"])
	MapKits.fill(m, track, BT["ROAD"])
	MapKits.fill(m, pitch, BT["GRASS"])
	for x in range(concourse.position.x, concourse.end.x): # outer wall with gates
		for yy in [concourse.position.y, concourse.end.y - 1]:
			if absi(x - cx) > 6 and (x % 40) > 5:
				m.obstacles[Vector2i(x, yy)] = "StoneWall"
	for y in range(concourse.position.y, concourse.end.y):
		for xx in [concourse.position.x, concourse.end.x - 1]:
			if absi(y - cy) > 6 and (y % 30) > 5:
				m.obstacles[Vector2i(xx, y)] = "StoneWall"
	# stands along the long sides, floodlights at the corners, a scoreboard at one end
	for k in range(3):
		MapKits.place_piece(m, "grandstand", pitch.position.x + 4 + k * 22, track.position.y - 7, 9, 4, 0)
		MapKits.place_piece(m, "grandstand", pitch.position.x + 4 + k * 22, track.end.y + 3, 9, 4, 0)
	for p in [Vector2(concourse.position.x + 2, concourse.position.y + 2), Vector2(concourse.end.x - 5, concourse.position.y + 2), Vector2(concourse.position.x + 2, concourse.end.y - 7), Vector2(concourse.end.x - 5, concourse.end.y - 7)]:
		MapKits.place_piece(m, "floodlight_tower", int(p.x), int(p.y), 2, 5, 0)
	MapKits.place_piece(m, "scoreboard", concourse.end.x - 8, cy - 2, 4, 4, 0)
	# the outside: car parks, shops, and whatever the era brought
	var th = ["urban", "art_deco"]
	if m.era in ["skirmish", "no_mans_land"]:
		th += ["camp", "wreck", "fortification"]
	if m.era == "apocalypse":
		th += ["wreck", "apocalypse_relic"]
	MapKits.scatter_pieces(m, th, 26, Rect2i(6, 6, w - 12, concourse.position.y - 8), 1, 60)
	MapKits.scatter_pieces(m, th, 26, Rect2i(6, concourse.end.y + 2, w - 12, h - concourse.end.y - 8), 1, 60)
	MapKits.add_zone(m, "fort", cx - 24, cy)
	MapKits.add_zone(m, "fort", cx + 24, cy)
	_era_dressing(m, pitch)
	if m.era == "no_mans_land": # the pitch becomes a field camp
		MapKits.scatter_pieces(m, ["camp"], 8, pitch, 1)

# ---- Military Base -------------------------------------------------------------------------------------------------------
static func military_base(m) -> void:
	var w = m.width
	var h = m.height
	var cx = w / 2
	var cy = h / 2
	var comp = Rect2i(cx - 140, cy - 85, 280, 170)
	MapKits.fill(m, comp, BT["GRASS"])
	for y in range(h):
		for x in range(w):
			if not comp.has_point(Vector2i(x, y)) and MapKits.moisture_at(m, x, y, 0.03) > 0.2:
				m.terrain[y][x] = BT["FOREST"]
	# perimeter fence with gates and watchtowers
	for x in range(comp.position.x, comp.end.x):
		for yy in [comp.position.y, comp.end.y - 1]:
			if (x % 60) > 6:
				MapKits.put_obstacle(m, x, yy, "Fence", 2.0)
	for y in range(comp.position.y, comp.end.y):
		for xx in [comp.position.x, comp.end.x - 1]:
			if (y % 50) > 6:
				MapKits.put_obstacle(m, xx, y, "Fence", 2.0)
	for p in [Vector2(comp.position.x + 3, comp.position.y + 3), Vector2(comp.end.x - 6, comp.position.y + 3), Vector2(comp.position.x + 3, comp.end.y - 7), Vector2(comp.end.x - 6, comp.end.y - 7)]:
		MapKits.place_piece(m, "watchtower", int(p.x), int(p.y), 2, 2, 0)
	# the runway, a taxiway, and the road net
	MapKits.paint_line(m, Vector2(comp.position.x + 10, cy + 45), Vector2(comp.end.x - 10, cy + 45), 12, BT["ROAD"])
	MapKits.paint_line(m, Vector2(cx - 60, cy + 39), Vector2(cx - 60, cy - 10), 5, BT["ROAD"])
	MapKits.paint_line(m, Vector2(cx + 60, cy + 39), Vector2(cx + 60, cy - 10), 5, BT["ROAD"])
	MapKits.paint_line(m, Vector2(comp.position.x + 10, cy - 10), Vector2(comp.end.x - 10, cy - 10), 5, BT["ROAD"])
	MapKits.paint_line(m, Vector2(cx, comp.position.y + 10), Vector2(cx, cy - 10), 5, BT["ROAD"])
	# the buildings, in zones
	for k in range(4):
		MapKits.place_piece(m, "hangar", cx - 100 + k * 56, cy + 22, 8, 5, 1)
	var th_hous = Rect2i(comp.position.x + 12, comp.position.y + 12, 90, 40)
	MapKits.scatter_pieces(m, ["military", "camp"], 18, th_hous, 1, 60)
	var th_ops = Rect2i(cx + 10, comp.position.y + 12, 110, 40)
	MapKits.scatter_pieces(m, ["urban", "military", "power"], 14, th_ops, 1, 60)
	for k in range(3):
		MapKits.place_piece(m, "missile_silo", cx + 40 + k * 22, cy - 40, 3, 3, 1)
	MapKits.scatter_pieces(m, ["industrial", "wreck", "camp"], 20, Rect2i(comp.position.x + 10, cy + 60, comp.size.x - 20, 24), 1, 60)
	MapKits.scatter_pieces(m, ["fortification"], 20, comp.grow(-4), 1, 60)
	MapKits.scatter_pieces(m, ["military", "wreck"], 18, Rect2i(5, 5, w - 10, h - 10), 1, 60) # outposts outside the wire
	MapKits.add_zone(m, "fort", cx + 30, cy - 25)
	MapKits.add_zone(m, "fort", cx - 70, cy + 28)
	MapKits.add_zone(m, "village", comp.position.x + 50, comp.position.y + 30)
	for y in range(5, h - 5):
		for x in range(5, w - 5):
			if m.terrain[y][x] == BT["FOREST"] and randf() < 0.22:
				MapKits.put_obstacle(m, x, y, "Tree", 8.0)
	_era_dressing(m, comp)

# ---- Munitions Range -----------------------------------------------------------------------------------------------------
# An abandoned testing range: target lanes, earth berms, observation posts, and random unexploded ordnance lying about.
static func munitions_range(m) -> void:
	var w = m.width
	var h = m.height
	var lanes = 5
	var lane_h = (h - 40) / lanes
	for l in range(lanes):
		var y = 20 + l * lane_h + lane_h / 2
		MapKits.paint_line(m, Vector2(30, y), Vector2(w - 40, y), 6, BT["ROAD"])
		for x in range(34, w - 40):
			if (x % 5) < 2:
				MapKits.put_obstacle(m, x, y - lane_h / 2, "Boulder", 8.0) # earth berms between lanes
		MapKits.place_piece(m, "target_dummies", w - 60 - (l % 2) * 12, y - 1, 6, 2, 1)
		MapKits.place_piece(m, "target_dummies", w / 2 + (l % 3) * 14, y + 4, 5, 2, 1)
		MapKits.place_piece(m, "observation_tower", 24, y - 6, 2, 4, 1)
	MapKits.scatter_pieces(m, ["range", "military", "camp"], 26, Rect2i(5, 5, w - 10, h - 10), 1, 60)
	for i in range(int(w * h / 3000)):
		var x2 = randi_range(8, w - 8)
		var y2 = randi_range(8, h - 8)
		if not MapKits.in_keepout(m, x2, y2, 14.0) and not m.obstacles.has(Vector2i(x2, y2)):
			m.hazard_spots.append({"kind": "uxo", "pos": Vector2(x2, y2)})
			MapKits.add_decor(m, x2, y2, "scorch")
	for i in range(int(w * h / 500)):
		MapKits.add_decor(m, randi_range(5, w - 6), randi_range(5, h - 6), "crater" if randf() < 0.5 else "scorch")
	MapKits.add_zone(m, "fort", w / 2 + 40, h / 2 - 30)
	MapKits.add_zone(m, "village", 60, h / 2)
	_era_dressing(m, Rect2i(5, 5, w - 10, h - 10))

# ---- Desert Arches -------------------------------------------------------------------------------------------------------
static func desert_arches(m) -> void:
	var w = m.width
	var h = m.height
	for y in range(h):
		for x in range(w):
			if absf(MapKits.noise_at(m, x, y, 0.022)) < 0.025 and Vector2(x - w / 2.0, y - h / 2.0).length() > 20.0:
				m.terrain[y][x] = BT["DESERT"]
			if randf() < 0.01:
				MapKits.add_decor(m, x, y, "ripple")
	for i in range(8): # oases
		var c = Vector2(randi_range(20, w - 20), randi_range(20, h - 20))
		if c.distance_to(Vector2(w / 2.0, h / 2.0)) < 40.0:
			continue
		for y in range(int(c.y) - 7, int(c.y) + 8):
			for x in range(int(c.x) - 9, int(c.x) + 10):
				var e = pow((x - c.x) / 9.0, 2.0) + pow((y - c.y) / 7.0, 2.0)
				if MapKits.in_bounds(m, x, y):
					if e < 0.5:
						m.terrain[y][x] = BT["WATER"]
					elif e < 1.0:
						m.terrain[y][x] = BT["GRASS"]
						if randf() < 0.25:
							MapKits.put_obstacle(m, x, y, "Tree", 8.0)
	MapKits.scatter_pieces(m, ["ancient"], 40, Rect2i(5, 5, w - 10, h - 10), 2, 80)
	MapKits.scatter_pieces(m, ["desert_rock"], 40, Rect2i(5, 5, w - 10, h - 10), 1, 60)
	if m.era != "prewar":
		MapKits.scatter_pieces(m, ["wreck", "camp"] + (["apocalypse_relic"] if m.era == "apocalypse" else []), 14, Rect2i(5, 5, w - 10, h - 10), 1, 60)
	for y in range(5, h - 5):
		for x in range(5, w - 5):
			if m.terrain[y][x] == BT["DESERT"] and randf() < 0.004:
				MapKits.put_obstacle(m, x, y, "Cactus", 8.0)
	MapKits.add_zone(m, "fort", w / 2 + 50, h / 2 + 30)
	MapKits.add_zone(m, "village", w / 2 - 60, h / 2 - 40)

# ---- Dense Forest --------------------------------------------------------------------------------------------------------
static func dense_forest(m) -> void:
	var w = m.width
	var h = m.height
	var clearings: Array = []
	for i in range(14):
		clearings.append(Vector2(randi_range(25, w - 25), randi_range(25, h - 25)))
	clearings.append(Vector2(w / 2.0, h / 2.0))
	for y in range(5, h - 5):
		for x in range(5, w - 5):
			var open = MapKits.noise_at(m, x, y, 0.03) > 0.22 # winding glades
			for c in clearings:
				if Vector2(x, y).distance_to(c) < (13.0 if c.x == w / 2.0 and c.y == h / 2.0 else 7.0 + 4.0 * float(posmod(int(c.x * 7.0 + c.y), 3))):
					open = true
					break
			if not open and randf() < 0.13: # ~8,000 trees (see MapKits.MAX_TREES)
				MapKits.put_obstacle(m, x, y, "Tree", 6.0)
	MapKits.scatter_pieces(m, ["gothic", "camp", "agricultural", "monument"], 26, Rect2i(5, 5, w - 10, h - 10), 0, 80)
	if m.era != "prewar":
		MapKits.scatter_pieces(m, ["wreck", "fortification"], 10, Rect2i(5, 5, w - 10, h - 10), 0, 80)
	for c in clearings:
		if randf() < 0.3:
			MapKits.add_zone(m, "fort" if randf() < 0.5 else "village", int(c.x), int(c.y))

# ---- Hydrothermal Park (Grand Prismatic Spring) -----------------------------------------------------------------------------
static func hydrothermal(m) -> void:
	var w = m.width
	var h = m.height
	var pools: Array = [Vector2(w * 0.3, h * 0.35), Vector2(w * 0.72, h * 0.3), Vector2(w * 0.55, h * 0.72), Vector2(w * 0.22, h * 0.7), Vector2(w * 0.85, h * 0.78)]
	for k in range(6):
		pools.append(Vector2(randi_range(30, w - 30), randi_range(30, h - 30)))
	var radii: Array = []
	for p in pools:
		radii.append(randf_range(11.0, 20.0))
	for i in range(pools.size()):
		var p: Vector2 = pools[i]
		var r: float = radii[i]
		if p.distance_to(Vector2(w / 2.0, h / 2.0)) < r + 14.0:
			continue
		for y in range(int(p.y - r - 1), int(p.y + r + 2)):
			for x in range(int(p.x - r - 1), int(p.x + r + 2)):
				if not MapKits.in_bounds(m, x, y, 4):
					continue
				var d = Vector2(x, y).distance_to(p) / r
				if d > 1.0:
					continue
				var kind = "pool_deep" if d < 0.35 else ("pool_blue" if d < 0.55 else ("pool_green" if d < 0.72 else ("pool_yellow" if d < 0.87 else "pool_orange")))
				m.terrain[y][x] = BT["WATER"] if d < 0.55 else BT["SHALLOW"]
				m.decor[Vector2i(x, y)] = kind
		var gp = p + Vector2(r + 4.0, 0)
		if MapKits.in_bounds(m, int(gp.x), int(gp.y), 6):
			m.hazard_spots.append({"kind": "geyser", "pos": gp})
			MapKits.place_piece(m, "geyser_cone", int(gp.x) - 1, int(gp.y) - 1, 2, 3, 0)
	for k in range(4): # extra geysers on the flats
		var gx = randi_range(20, w - 20)
		var gy = randi_range(20, h - 20)
		if MapKits.rect_free(m, gx, gy, 2, 3, 1):
			m.hazard_spots.append({"kind": "geyser", "pos": Vector2(gx, gy)})
			MapKits.place_piece(m, "geyser_cone", gx, gy, 2, 3, 0)
	# boardwalks round the pools and a visitor centre
	var order: Array = range(pools.size())
	order.sort_custom(func(a, b): return pools[a].x < pools[b].x) # boardwalks run west to east, pool to pool
	for i in range(order.size() - 1):
		var pa: Vector2 = pools[order[i]]
		var pb: Vector2 = pools[order[i + 1]]
		var mid = Vector2((pa.x + pb.x) / 2.0, clampf((pa.y + pb.y) / 2.0 + randf_range(-10.0, 10.0), 12.0, h - 12.0))
		MapKits.paint_line(m, pa + Vector2(radii[order[i]] + 2, 0), mid, 2, BT["ROAD"])
		MapKits.paint_line(m, mid, pb + Vector2(-radii[order[i + 1]] - 2, 0), 2, BT["ROAD"])
	var th = ["urban", "art_deco", "coast"] if m.era == "prewar" else ["camp", "wreck", "fortification"]
	MapKits.scatter_pieces(m, th, 14, Rect2i(5, 5, w - 10, h - 10), 1, 80)
	for y in range(5, h - 5):
		for x in range(5, w - 5):
			if m.terrain[y][x] == BT["TUNDRA"] and randf() < 0.012:
				MapKits.put_obstacle(m, x, y, "IceBoulder" if randf() < 0.3 else "Boulder", 8.0)
	MapKits.add_zone(m, "fort", w / 2 + 30, h / 2 - 20)
	MapKits.add_zone(m, "village", w / 2 - 40, h / 2 + 30)

# ---- Caves -----------------------------------------------------------------------------------------------------------------
static func caves(m) -> void:
	var w = m.width
	var h = m.height
	var solid: Array = []
	for y in range(h):
		var row: Array = []
		for x in range(w):
			var edge = x < 4 or y < 4 or x >= w - 4 or y >= h - 4
			row.append(true if edge else (randf() < 0.46 and Vector2(x - w / 2.0, y - h / 2.0).length() > 16.0))
		solid.append(row)
	for it in range(5): # cellular automaton smoothing
		var nxt: Array = []
		for y in range(h):
			var row2: Array = []
			for x in range(w):
				var n = 0
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var xx = x + dx
						var yy = y + dy
						if xx < 0 or yy < 0 or xx >= w or yy >= h or solid[yy][xx]:
							n += 1
				row2.append(n >= 5 and Vector2(x - w / 2.0, y - h / 2.0).length() > 16.0 or x < 4 or y < 4 or x >= w - 4 or y >= h - 4)
			nxt.append(row2)
		solid = nxt
	for y in range(h):
		for x in range(w):
			m.terrain[y][x] = BT["DUNGEON"]
			if solid[y][x]:
				m.obstacles[Vector2i(x, y)] = "Wall"
	for y in range(6, h - 6): # underground pools
		for x in range(6, w - 6):
			if not solid[y][x] and MapKits.noise_at(m, x, y, 0.05) > 0.5 and Vector2(x - w / 2.0, y - h / 2.0).length() > 20.0:
				m.terrain[y][x] = BT["WATER"]
	MapKits.scatter_pieces(m, ["cave"], 70, Rect2i(6, 6, w - 12, h - 12), 0, 50)
	MapKits.scatter_pieces(m, ["dungeon", "ancient"], 24, Rect2i(6, 6, w - 12, h - 12), 0, 50)
	for i in range(220):
		MapKits.add_decor(m, randi_range(6, w - 7), randi_range(6, h - 7), ["bones", "moss", "blood_moon_glow", "debris"][randi() % 4])
	for k in range(3):
		MapKits.add_zone(m, "fort", w / 2 + randi_range(-60, 60), h / 2 + randi_range(-40, 40))

# ---- Interiors (Crypt, Keep, and furniture for Dungeon) ------------------------------------------------------------------------
static func interior(m, flavor: String) -> void:
	MapStructure.build_dungeon(m)
	furnish(m, flavor)

static func furnish(m, flavor: String) -> void:
	var rooms: Array = m.dungeon_rooms
	var sets = {
		"crypt": [["sarcophagus", "altar", "iron_cage", "brazier"], ["sarcophagus", "pillar_cluster", "gargoyle"], ["graveyard", "crypt", "mausoleum"]],
		"keep": [["banquet_table", "hearth", "bookshelves", "brazier"], ["throne", "pillar_cluster", "brazier"], ["iron_cage", "torture_rack", "stone_well"], ["treasure_hoard", "gargoyle", "pillar_cluster"]],
		"dungeon": [["altar", "sarcophagus", "brazier"], ["treasure_hoard", "iron_cage", "gargoyle"], ["summoning_circle", "brazier", "bookshelves"], ["pillar_cluster", "stone_well", "hearth"]],
	}
	var kit: Array = sets.get(flavor, sets["dungeon"])
	for r in rooms:
		var styles: Array = kit[randi() % kit.size()]
		var n = clampi(r.size.x * r.size.y / 60, 2, 9)
		var inner = Rect2i(r.position.x + 2, r.position.y + 2, maxi(4, r.size.x - 4), maxi(4, r.size.y - 4))
		var placed = 0
		var tries = 0
		while placed < n and tries < n * 40:
			tries += 1
			var style: String = styles[randi() % styles.size()]
			if not SetPieces.has_piece(style):
				continue
			var sz = SetPieces.random_size(style, randf(), randf())
			if MapKits.place_piece(m, style, inner.position.x + randi() % maxi(1, inner.size.x - sz.x + 1), inner.position.y + randi() % maxi(1, inner.size.y - sz.y + 1), sz.x, sz.y, 2):
				placed += 1
		if r.size.x >= 20 and randf() < 0.5:
			MapKits.add_zone(m, "fort" if randf() < 0.5 else "village", r.get_center().x, r.get_center().y)
		for i in range(r.size.x * r.size.y / 70):
			MapKits.add_decor(m, r.position.x + randi() % r.size.x, r.position.y + randi() % r.size.y, ["bones", "cracks", "moss", "debris"][randi() % 4] if flavor == "crypt" else ["cracks", "debris"][randi() % 2])

# ---- Dreamscape (surreal) --------------------------------------------------------------------------------------------------------
static func dreamscape(m) -> void:
	var w = m.width
	var h = m.height
	for y in range(h):
		for x in range(w):
			var n = MapKits.noise_at(m, x, y, 0.03)
			var wet = MapKits.moisture_at(m, x, y, 0.03)
			m.terrain[y][x] = BT["GRASS"]
			if n > 0.38 and Vector2(x - w / 2.0, y - h / 2.0).length() > 20.0:
				m.terrain[y][x] = BT["WATER"] # mirror ponds
			elif wet > 0.35:
				m.terrain[y][x] = BT["DESERT"]
			elif wet < -0.35:
				m.terrain[y][x] = BT["TUNDRA"]
			if randf() < 0.18:
				MapKits.add_decor(m, x, y, "flowers")
	for k in range(5): # chessboard plazas
		var c = Vector2(randi_range(30, w - 30), randi_range(30, h - 30))
		for y in range(int(c.y) - 10, int(c.y) + 10):
			for x in range(int(c.x) - 10, int(c.x) + 10):
				if MapKits.in_bounds(m, x, y, 4) and Vector2(x, y).distance_to(c) < 10.0:
					m.terrain[y][x] = BT["FLOOR"] if ((x / 4) + (y / 4)) % 2 == 0 else BT["ROAD"]
	MapKits.scatter_pieces(m, ["surreal", "kitbash"], 90, Rect2i(5, 5, w - 10, h - 10), 1, 60)
	for y in range(5, h - 5):
		for x in range(5, w - 5):
			if randf() < 0.004:
				MapKits.put_obstacle(m, x, y, "Tree", 9.0)
	for k in range(3):
		MapKits.add_zone(m, "fort" if k != 1 else "village", int(w * (0.25 + 0.25 * k)), int(h * (0.35 if k % 2 == 0 else 0.65)))

# ---- shared war-era dressing (craters, wire, moss) over a region ----------------------------------------------------------------
static func _era_dressing(m, region: Rect2i) -> void:
	var n = region.size.x * region.size.y / 120
	for i in range(n):
		var x = region.position.x + randi() % maxi(1, region.size.x)
		var y = region.position.y + randi() % maxi(1, region.size.y)
		match m.era:
			"skirmish": if randf() < 0.3: MapKits.add_decor(m, x, y, "scorch")
			"no_mans_land": MapKits.add_decor(m, x, y, ["crater", "wire", "scorch", "debris"][randi() % 4])
			"apocalypse": MapKits.add_decor(m, x, y, ["moss", "cracks", "ash", "bones"][randi() % 4])
