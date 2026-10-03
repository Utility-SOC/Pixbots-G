extends RefCounted

# Structure pass for MapGenerator: gives land maps regions with identity,
# built set pieces and connecting roads instead of a flat field with
# single-tile obstacle dust, and builds the Dungeon map as real rooms and
# corridors. Everything here only edits `m.terrain` / `m.obstacles` (the same
# data the rest of the generator, nav and rasterizer already consume), keeps
# the player's centre spawn clear, and leaves the usual connectivity carver to
# guarantee every pocket stays reachable.
#
# Mechs are ~3 tiles wide, so passages are authored at 5+ tiles, doors at 4.

const WALL := "Wall" # flat full-tile masonry (merged collision, no per-tile node)
const MAP_MARGIN := 8
const SPAWN_CLEAR := 22.0 # tiles around the centre spawn that structures avoid

# Region ("zone") kinds and how likely each is per map type.
const ZONE_WEIGHTS := {
	"Normal": {"clearing": 2, "thicket": 2, "lake": 2, "fort": 2, "village": 2, "stones": 1, "crater": 1},
	"Forest": {"thicket": 4, "clearing": 2, "lake": 1, "village": 1, "stones": 1, "fort": 1},
	"Desert": {"crater": 3, "fort": 2, "village": 1, "oasis": 1, "clearing": 2, "stones": 1},
	"Tundra": {"lake": 3, "fort": 1, "clearing": 2, "thicket": 2, "village": 1, "stones": 1},
	"Volcano": {"crater": 3, "thicket": 2, "fort": 2, "clearing": 2, "stones": 1},
}

# Biomes a Normal map's regions are drawn from (weighted by repeat).
const NORMAL_REGION_BIOMES := [0, 0, 3, 3, 2, 4, 5] # grass, grass, forest, forest, desert, tundra, volcano


# ---------------------------------------------------------------------------
# Normal map: big contiguous regions instead of noise camouflage.
# ---------------------------------------------------------------------------
static func prepare_regions(m) -> Array:
	var seeds: Array = []
	var tries := 0
	var count := randi_range(6, 9)
	while seeds.size() < count and tries < 400:
		tries += 1
		var p = Vector2(randf_range(0.0, m.width), randf_range(0.0, m.height))
		var ok := true
		for s in seeds:
			if s.pos.distance_to(p) < 90.0:
				ok = false
				break
		if ok:
			seeds.append({"pos": p, "biome": NORMAL_REGION_BIOMES[randi() % NORMAL_REGION_BIOMES.size()]})
	# Guarantee at least three distinct biomes so the map never reads as one.
	var distinct := {}
	for s in seeds:
		distinct[s.biome] = true
	var i := 0
	while distinct.size() < 3 and i < seeds.size():
		var b = NORMAL_REGION_BIOMES[randi() % NORMAL_REGION_BIOMES.size()]
		seeds[i].biome = b
		distinct[b] = true
		i += 1
	return seeds


static func region_biome(m, seeds: Array, x: int, y: int) -> int:
	# Domain warp so region borders meander instead of being straight Voronoi edges.
	var wx = m.noise.get_noise_2d(x * 3.0, y * 3.0) * 26.0
	var wy = m.noise.get_noise_2d(y * 3.0 + 311.0, x * 3.0) * 26.0
	var p = Vector2(x + wx, y + wy)
	var best = 1.0e12
	var biome := 0
	for s in seeds:
		var d = p.distance_squared_to(s.pos)
		if d < best:
			best = d
			biome = s.biome
	return biome


# ---------------------------------------------------------------------------
# Land maps: zones + set pieces + roads.
# ---------------------------------------------------------------------------
static func build_regions(m) -> void:
	var weights: Dictionary = ZONE_WEIGHTS.get(m.map_type, ZONE_WEIGHTS["Normal"])
	var bag: Array = []
	for k in weights:
		for n in range(int(weights[k])):
			bag.append(k)

	# Zone centres: spread out, away from the spawn and the map edge.
	var zones: Array = []
	var tries := 0
	var target := randi_range(9, 12)
	var centre = Vector2(m.width / 2.0, m.height / 2.0)
	while zones.size() < target and tries < 800:
		tries += 1
		var p = Vector2(randf_range(MAP_MARGIN + 20, m.width - MAP_MARGIN - 20), randf_range(MAP_MARGIN + 20, m.height - MAP_MARGIN - 20))
		if p.distance_to(centre) < 38.0:
			continue
		var ok := true
		for z in zones:
			if z.pos.distance_to(p) < 62.0:
				ok = false
				break
		if ok:
			zones.append({"pos": p, "kind": bag[randi() % bag.size()], "r": randf_range(24.0, 36.0)})

	for z in zones:
		_stamp_zone(m, z)

	# The spawn area is always a small readable clearing with a few boulders for cover.
	_stamp_spawn_clearing(m)

	# Roads between zone centres (MST) and from the spawn out to the nearest zones.
	var nodes: Array = [centre]
	for z in zones:
		nodes.append(z.pos)
	_connect_with_roads(m, nodes)


# Ground accent painted under a zone so it reads as its own place:
# map type -> zone kind -> BiomeType (0 grass, 2 desert, 3 forest, 5 volcano, 6 dungeon).
const ZONE_GROUND := {
	"Forest": {"clearing": 0, "village": 0, "stones": 0, "fort": 0},
	"Desert": {"clearing": 5, "crater": 5, "stones": 5},
	"Tundra": {"thicket": 3, "village": 3},
	"Volcano": {"crater": 6, "clearing": 2, "fort": 6},
}


static func _paint_ground(m, c: Vector2, r: float, biome: int) -> void:
	var ri = int(ceil(r * 1.3))
	for y in range(int(c.y) - ri, int(c.y) + ri + 1):
		for x in range(int(c.x) - ri, int(c.x) + ri + 1):
			if not _in_map(m, x, y):
				continue
			var wob = 1.0 + 0.3 * m.noise.get_noise_2d(x * 3.0, y * 3.0)
			if Vector2(x, y).distance_to(c) / wob <= r and m.terrain[y][x] != m.BiomeType.WATER:
				m.terrain[y][x] = biome


static func _stamp_zone(m, z: Dictionary) -> void:
	var c: Vector2 = z.pos
	var r: float = z.r
	var accent = ZONE_GROUND.get(m.map_type, {}).get(z.kind, -1)
	if accent >= 0:
		_paint_ground(m, c, r * 1.05, accent)
	match z.kind:
		"clearing":
			_clear_disc(m, c, r * 0.85)
			_ring_of_cover(m, c, r * 0.55, randi_range(4, 7))
		"thicket":
			_thicket(m, c, r)
		"lake":
			_lake(m, c, r * 0.8, false)
		"oasis":
			_lake(m, c, r * 0.35, true)
		"fort":
			_clear_disc(m, c, r * 0.9)
			_stamp_fort(m, c, randi_range(26, 34), randi_range(18, 24))
		"village":
			_clear_disc(m, c, r * 0.9)
			_stamp_village(m, c, r)
		"stones":
			_clear_disc(m, c, r * 0.6)
			_stamp_stone_ring(m, c, 8.0)
		"crater":
			_stamp_crater(m, c, r * 0.8)


static func _in_map(m, x: int, y: int) -> bool:
	return x >= MAP_MARGIN and y >= MAP_MARGIN and x < m.width - MAP_MARGIN and y < m.height - MAP_MARGIN


static func _near_spawn(m, x: int, y: int) -> bool:
	return Vector2(x - m.width / 2.0, y - m.height / 2.0).length() < SPAWN_CLEAR


static func _set_obstacle(m, x: int, y: int, name: String) -> void:
	if not _in_map(m, x, y) or _near_spawn(m, x, y):
		return
	if m.terrain[y][x] == m.BiomeType.WATER:
		return
	m.obstacles[Vector2i(x, y)] = name


static func _clear_disc(m, c: Vector2, r: float) -> void:
	var ri = int(ceil(r))
	for y in range(int(c.y) - ri, int(c.y) + ri + 1):
		for x in range(int(c.x) - ri, int(c.x) + ri + 1):
			if _in_map(m, x, y) and Vector2(x, y).distance_to(c) <= r:
				m.obstacles.erase(Vector2i(x, y))


# Standing cover: boulders in a ring with gaps so an open fight has something to hide behind.
static func _ring_of_cover(m, c: Vector2, r: float, count: int) -> void:
	var a0 = randf() * TAU
	for i in range(count):
		var a = a0 + TAU * float(i) / count
		var p = c + Vector2(cos(a), sin(a)) * r
		for dy in range(2):
			for dx in range(2):
				_set_obstacle(m, int(p.x) + dx, int(p.y) + dy, "Boulder")


static func _rock_name(m, x: int, y: int) -> String:
	return m._get_obstacle_name(m.terrain[y][x])


# Dense obstacle mass with winding passages: obstacles sit where a ridged noise
# value is high, passages follow its zero-crossings (never a flat wall).
static func _thicket(m, c: Vector2, r: float) -> void:
	var ri = int(ceil(r))
	for y in range(int(c.y) - ri, int(c.y) + ri + 1):
		for x in range(int(c.x) - ri, int(c.x) + ri + 1):
			if not _in_map(m, x, y) or _near_spawn(m, x, y):
				continue
			var d = Vector2(x, y).distance_to(c)
			if d > r or m.terrain[y][x] == m.BiomeType.WATER:
				continue
			var v = absf(m.obstacle_noise.get_noise_2d(x * 1.6, y * 1.6))
			var edge_fade = clampf((r - d) / (r * 0.35), 0.0, 1.0) # thins out toward the rim
			if v > 0.16 and randf() < 0.92 * edge_fade + 0.08:
				m.obstacles[Vector2i(x, y)] = _rock_name(m, x, y)
			else:
				m.obstacles.erase(Vector2i(x, y))


static func _lake(m, c: Vector2, r: float, oasis: bool) -> void:
	var ri = int(ceil(r * 1.4))
	for y in range(int(c.y) - ri, int(c.y) + ri + 1):
		for x in range(int(c.x) - ri, int(c.x) + ri + 1):
			if not _in_map(m, x, y) or _near_spawn(m, x, y):
				continue
			var wob = 1.0 + 0.28 * m.noise.get_noise_2d(x * 4.0, y * 4.0)
			var d = Vector2(x, y).distance_to(c) / wob
			if d <= r:
				m.terrain[y][x] = m.BiomeType.WATER
				m.obstacles.erase(Vector2i(x, y))
			elif oasis and d <= r + 7.0:
				m.terrain[y][x] = m.BiomeType.GRASSLAND
				m.obstacles.erase(Vector2i(x, y))
			elif d <= r + 2.0:
				m.obstacles.erase(Vector2i(x, y)) # clear shoreline so it's walkable around


# Crater / mesa: a broken rim of the biome's rock around an open floor, 3-4 wide gaps.
static func _stamp_crater(m, c: Vector2, r: float) -> void:
	var gaps: Array = []
	for i in range(randi_range(3, 4)):
		gaps.append(randf() * TAU)
	var steps = int(TAU * r * 2.0)
	for i in range(steps):
		var a = TAU * float(i) / steps
		var in_gap := false
		for g in gaps:
			if absf(angle_difference(a, g)) < 5.5 / r:
				in_gap = true
				break
		if in_gap:
			continue
		var wob = 1.0 + 0.1 * sin(a * 3.0 + c.x)
		for t in range(2):
			var p = c + Vector2(cos(a), sin(a)) * (r * wob + t)
			var x = int(p.x)
			var y = int(p.y)
			if _in_map(m, x, y):
				_set_obstacle(m, x, y, _rock_name(m, x, y))
	_clear_disc(m, c, r - 1.0)


# --- Built set pieces -------------------------------------------------------

# Hollow rectangle of masonry with doors; interior gets flagstone floor.
static func _stamp_building(m, x0: int, y0: int, w: int, h: int, doors: int, door_w: int, ruin: float) -> void:
	var door_tiles := {}
	var sides = [0, 1, 2, 3]
	sides.shuffle()
	for i in range(mini(doors, 4)):
		var side: int = sides[i]
		match side:
			0: door_tiles[Vector2i(x0 + randi_range(2, maxi(2, w - door_w - 2)), y0)] = side
			1: door_tiles[Vector2i(x0 + randi_range(2, maxi(2, w - door_w - 2)), y0 + h - 1)] = side
			2: door_tiles[Vector2i(x0, y0 + randi_range(2, maxi(2, h - door_w - 2)))] = side
			3: door_tiles[Vector2i(x0 + w - 1, y0 + randi_range(2, maxi(2, h - door_w - 2)))] = side
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			if not _in_map(m, x, y) or m.terrain[y][x] == m.BiomeType.WATER:
				continue
			var edge = x == x0 or x == x0 + w - 1 or y == y0 or y == y0 + h - 1
			var key = Vector2i(x, y)
			if edge:
				var is_door := false
				for dt in door_tiles:
					var side: int = door_tiles[dt]
					if side <= 1 and y == dt.y and x >= dt.x and x < dt.x + door_w:
						is_door = true
					elif side >= 2 and x == dt.x and y >= dt.y and y < dt.y + door_w:
						is_door = true
				if is_door or (ruin > 0.0 and randf() < ruin):
					m.obstacles.erase(key)
					m.terrain[y][x] = m.BiomeType.FLOOR
				else:
					_set_obstacle(m, x, y, WALL)
			else:
				m.obstacles.erase(key)
				m.terrain[y][x] = m.BiomeType.FLOOR


static func _stamp_fort(m, c: Vector2, w: int, h: int) -> void:
	var x0 = int(c.x) - w / 2
	var y0 = int(c.y) - h / 2
	var ruin = 0.0 if randf() < 0.5 else 0.12
	_stamp_building(m, x0, y0, w, h, randi_range(2, 4), 4, ruin)
	# Corner towers.
	for corner in [Vector2i(x0, y0), Vector2i(x0 + w - 3, y0), Vector2i(x0, y0 + h - 3), Vector2i(x0 + w - 3, y0 + h - 3)]:
		for dy in range(3):
			for dx in range(3):
				_set_obstacle(m, corner.x + dx, corner.y + dy, WALL)
	# Interior cover: a few 2x2 pillars, spaced out.
	for i in range(randi_range(3, 5)):
		var px = x0 + randi_range(5, w - 7)
		var py = y0 + randi_range(5, h - 7)
		for dy in range(2):
			for dx in range(2):
				_set_obstacle(m, px + dx, py + dy, WALL)


static func _stamp_village(m, c: Vector2, r: float) -> void:
	var placed: Array = []
	var tries := 0
	var want = randi_range(4, 6)
	while placed.size() < want and tries < 60:
		tries += 1
		var w = randi_range(8, 12)
		var h = randi_range(7, 10)
		var p = c + Vector2(randf_range(-r * 0.8, r * 0.8), randf_range(-r * 0.6, r * 0.6))
		var rect = Rect2(p.x - w / 2.0, p.y - h / 2.0, w, h).grow(4.0)
		var clash := false
		for q in placed:
			if q.intersects(rect):
				clash = true
				break
		if clash:
			continue
		placed.append(rect)
		_stamp_building(m, int(p.x - w / 2.0), int(p.y - h / 2.0), w, h, randi_range(1, 2), 4, 0.0)


static func _stamp_stone_ring(m, c: Vector2, r: float) -> void:
	var n = randi_range(9, 12)
	for i in range(n):
		var a = TAU * float(i) / n
		var p = c + Vector2(cos(a), sin(a)) * r
		for dy in range(2):
			for dx in range(2):
				_set_obstacle(m, int(p.x) + dx, int(p.y) + dy, "Boulder")
	for y in range(int(c.y - r), int(c.y + r) + 1):
		for x in range(int(c.x - r), int(c.x + r) + 1):
			if _in_map(m, x, y) and Vector2(x, y).distance_to(c) < r - 2.0 and m.terrain[y][x] != m.BiomeType.WATER:
				m.terrain[y][x] = m.BiomeType.FLOOR


static func _stamp_spawn_clearing(m) -> void:
	var c = Vector2(m.width / 2.0, m.height / 2.0)
	_clear_disc(m, c, SPAWN_CLEAR - 4.0)
	for y in range(int(c.y - SPAWN_CLEAR), int(c.y + SPAWN_CLEAR)):
		for x in range(int(c.x - SPAWN_CLEAR), int(c.x + SPAWN_CLEAR)):
			if Vector2(x, y).distance_to(c) < 14.0 and m.terrain[y][x] == m.BiomeType.WATER:
				m.terrain[y][x] = m.BiomeType.GRASSLAND


# --- Roads -----------------------------------------------------------------

# Minimum spanning tree over `nodes` (tile positions), each edge carved as a
# gently winding 4-wide road that clears obstacles and bridges water.
static func _connect_with_roads(m, nodes: Array) -> void:
	if nodes.size() < 2:
		return
	var in_tree := [0]
	var remaining: Array = range(1, nodes.size())
	while not remaining.is_empty():
		var best_d = 1.0e12
		var best_a := -1
		var best_b := -1
		for a in in_tree:
			for b in remaining:
				var d = nodes[a].distance_to(nodes[b])
				if d < best_d:
					best_d = d
					best_a = a
					best_b = b
		_carve_road(m, nodes[best_a], nodes[best_b])
		in_tree.append(best_b)
		remaining.erase(best_b)
	# One or two extra loops so the map isn't a pure tree (flanking routes).
	for k in range(2):
		var a = randi() % nodes.size()
		var b = randi() % nodes.size()
		if a != b and nodes[a].distance_to(nodes[b]) < 130.0:
			_carve_road(m, nodes[a], nodes[b])


static func _carve_road(m, a: Vector2, b: Vector2) -> void:
	var length = a.distance_to(b)
	var dir = (b - a) / maxf(length, 1.0)
	var perp = Vector2(-dir.y, dir.x)
	var phase = randf() * TAU
	var amp = randf_range(3.0, 7.0)
	var steps = int(length)
	for i in range(steps + 1):
		var t = float(i)
		var wobble = sin(t / 14.0 + phase) * amp * sin(PI * t / maxf(length, 1.0))
		var p = a + dir * t + perp * wobble
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if dx * dx + dy * dy > 5:
					continue
				var x = int(p.x) + dx
				var y = int(p.y) + dy
				if not _in_map(m, x, y):
					continue
				m.obstacles.erase(Vector2i(x, y))
				if m.terrain[y][x] != m.BiomeType.FLOOR:
					m.terrain[y][x] = m.BiomeType.ROAD


# ---------------------------------------------------------------------------
# Dungeon: BSP rooms joined by corridors, solid masonry everywhere else.
# ---------------------------------------------------------------------------
static func build_dungeon(m) -> void:
	var D = m.BiomeType.DUNGEON
	for y in range(m.height):
		for x in range(m.width):
			m.terrain[y][x] = D
			m.obstacles[Vector2i(x, y)] = WALL

	var rooms: Array = []
	_bsp(m, Rect2i(MAP_MARGIN, MAP_MARGIN, m.width - MAP_MARGIN * 2, m.height - MAP_MARGIN * 2), 0, rooms)

	# The spawn room: force a room around the map centre.
	var spawn_room = Rect2i(m.width / 2 - 14, m.height / 2 - 10, 28, 20)
	rooms = rooms.filter(func(r): return not r.intersects(spawn_room.grow(3)))
	rooms.append(spawn_room)

	for r in rooms:
		_carve_room(m, r)

	# Corridors: MST over room centres, plus a few extra loops.
	var centres: Array = []
	for r in rooms:
		centres.append(Vector2(r.position.x + r.size.x / 2.0, r.position.y + r.size.y / 2.0))
	var in_tree := [0]
	var remaining: Array = range(1, centres.size())
	while not remaining.is_empty():
		var best_d = 1.0e12
		var ba := -1
		var bb := -1
		for a in in_tree:
			for b in remaining:
				var d = centres[a].distance_to(centres[b])
				if d < best_d:
					best_d = d
					ba = a
					bb = b
		_carve_corridor(m, centres[ba], centres[bb])
		in_tree.append(bb)
		remaining.erase(bb)
	for k in range(maxi(3, rooms.size() / 4)):
		var a = randi() % centres.size()
		var b = randi() % centres.size()
		if a != b and centres[a].distance_to(centres[b]) < 90.0:
			_carve_corridor(m, centres[a], centres[b])

	# Cover pillars in the bigger rooms, braziers-as-boulders near the walls.
	for r in rooms:
		if r.size.x >= 22 and r.size.y >= 16 and r != spawn_room:
			var n = randi_range(2, 4)
			for i in range(n):
				var px = r.position.x + randi_range(5, r.size.x - 7)
				var py = r.position.y + randi_range(5, r.size.y - 7)
				for dy in range(2):
					for dx in range(2):
						m.obstacles[Vector2i(px + dx, py + dy)] = WALL


static func _bsp(m, area: Rect2i, depth: int, out: Array) -> void:
	var min_leaf := 28
	var can_split_x = area.size.x >= min_leaf * 2
	var can_split_y = area.size.y >= min_leaf * 2
	if depth < 6 and (can_split_x or can_split_y) and (depth < 2 or randf() < 0.85):
		var split_x = can_split_x and (not can_split_y or area.size.x > area.size.y or randf() < 0.4)
		if split_x:
			var cut = randi_range(min_leaf, area.size.x - min_leaf)
			_bsp(m, Rect2i(area.position.x, area.position.y, cut, area.size.y), depth + 1, out)
			_bsp(m, Rect2i(area.position.x + cut, area.position.y, area.size.x - cut, area.size.y), depth + 1, out)
		else:
			var cut = randi_range(min_leaf, area.size.y - min_leaf)
			_bsp(m, Rect2i(area.position.x, area.position.y, area.size.x, cut), depth + 1, out)
			_bsp(m, Rect2i(area.position.x, area.position.y + cut, area.size.x, area.size.y - cut), depth + 1, out)
		return
	# Leaf: a room inset from the leaf bounds, leaving 3+ tiles of wall around it.
	var rw = randi_range(maxi(16, area.size.x * 6 / 10), area.size.x - 6)
	var rh = randi_range(maxi(12, area.size.y * 6 / 10), area.size.y - 6)
	var rx = area.position.x + randi_range(3, maxi(3, area.size.x - rw - 3))
	var ry = area.position.y + randi_range(3, maxi(3, area.size.y - rh - 3))
	out.append(Rect2i(rx, ry, rw, rh))


static func _carve_room(m, r: Rect2i) -> void:
	for y in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			if x < 2 or y < 2 or x >= m.width - 2 or y >= m.height - 2:
				continue
			m.obstacles.erase(Vector2i(x, y))
			m.terrain[y][x] = m.BiomeType.FLOOR


# L-shaped 6-wide corridor between two points (horizontal first or vertical first).
static func _carve_corridor(m, a: Vector2, b: Vector2) -> void:
	var w := 6
	var horizontal_first = randf() < 0.5
	var ax = int(a.x)
	var ay = int(a.y)
	var bx = int(b.x)
	var by = int(b.y)
	var corner = Vector2i(bx, ay) if horizontal_first else Vector2i(ax, by)
	_carve_strip(m, Vector2i(ax, ay), corner, w)
	_carve_strip(m, corner, Vector2i(bx, by), w)


static func _carve_strip(m, p: Vector2i, q: Vector2i, w: int) -> void:
	var x0 = mini(p.x, q.x) - w / 2
	var x1 = maxi(p.x, q.x) + w / 2
	var y0 = mini(p.y, q.y) - w / 2
	var y1 = maxi(p.y, q.y) + w / 2
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if x < 2 or y < 2 or x >= m.width - 2 or y >= m.height - 2:
				continue
			m.obstacles.erase(Vector2i(x, y))
			m.terrain[y][x] = m.BiomeType.FLOOR
