class_name SetPieceEra
extends RefCounted

# War eras for the set-piece library. The same building looks different at each stage of a conflict:
#   prewar        everything is great: pieces are drawn as designed
#   skirmish      first skirmishes: chipped edges, scorch marks, a few cracks
#   no_mans_land  ragged shell-torn ruins, craters, barbed wire, poppies growing in the churned earth
#   apocalypse    long after: mostly collapsed, rusted, overgrown
# `apply` takes the art's [Rect2, Color] list, rasterizes it to PIX cells, ages it, and run-length merges it back into
# rects (so an aged piece is also cheap to draw). Deterministic per seed; pure, so it is testable headless.

const PIX = 4.0
const ERAS = ["prewar", "skirmish", "no_mans_land", "apocalypse"]

# chip: ragged-top / blown-out share; holes: shell holes per 100 cells; scorch: blotch share; cracks: crack count;
# desat/dark: colour wear; grow: overgrowth height share; wire: barbed wire at the base; poppy: poppy density at the base;
# craters: shell craters at the base.
const PARAMS = {
	"skirmish": {"chip": 0.06, "holes": 0.05, "scorch": 0.10, "cracks": 2, "desat": 0.08, "dark": 0.05, "grow": 0.0, "wire": false, "poppy": 0.0, "craters": 0},
	"no_mans_land": {"chip": 0.24, "holes": 0.22, "scorch": 0.28, "cracks": 5, "desat": 0.30, "dark": 0.14, "grow": 0.04, "wire": true, "poppy": 0.06, "craters": 2},
	"apocalypse": {"chip": 0.42, "holes": 0.34, "scorch": 0.30, "cracks": 9, "desat": 0.45, "dark": 0.22, "grow": 0.32, "wire": false, "poppy": 0.015, "craters": 1},
}

static func is_era(name: String) -> bool:
	return name in ERAS

# Index 0..3, for evolution chains; unknown eras count as prewar.
static func index_of(name: String) -> int:
	var i = ERAS.find(name)
	return maxi(0, i)

static func apply(rects: Array, footprint: Vector2, era: String, seed_v: int) -> Array:
	if era == "prewar" or not PARAMS.has(era) or rects.is_empty():
		return rects
	var p: Dictionary = PARAMS[era]
	var cols = int(footprint.x / PIX)
	var rows = int(footprint.y / PIX)
	if cols <= 0 or rows <= 0:
		return rects
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_v
	var g = _raster(rects, cols, rows)
	_wear(g, cols, rows, float(p["desat"]), float(p["dark"]))
	_scorch(g, cols, rows, float(p["scorch"]), rng)
	_cracks(g, cols, rows, int(p["cracks"]), rng)
	_chip(g, cols, rows, float(p["chip"]), float(p["holes"]), rng)
	if float(p["grow"]) > 0.0:
		_overgrow(g, cols, rows, float(p["grow"]), rng)
	for i in range(int(p["craters"])):
		_crater(g, cols, rows, rng)
	if bool(p["wire"]):
		_wire(g, cols, rows)
	if float(p["poppy"]) > 0.0:
		_poppies(g, cols, rows, float(p["poppy"]), rng)
	return _merge(g, cols, rows)

# ---- grid ---------------------------------------------------------------------------------------------------------

static func _raster(rects: Array, cols: int, rows: int) -> Array:
	var g: Array = []
	for r in range(rows):
		var row: Array = []
		row.resize(cols)
		g.append(row)
	for item in rects:
		var rc: Rect2 = item[0]
		var c0 = clampi(int(round(rc.position.x / PIX)), 0, cols)
		var c1 = clampi(int(round(rc.end.x / PIX)), 0, cols)
		var r0 = clampi(int(round(rc.position.y / PIX)), 0, rows)
		var r1 = clampi(int(round(rc.end.y / PIX)), 0, rows)
		for r in range(r0, r1):
			for c in range(c0, c1):
				g[r][c] = item[1]
	return g

static func _wear(g: Array, cols: int, rows: int, desat: float, dark: float) -> void:
	for r in range(rows):
		for c in range(cols):
			var col = g[r][c]
			if col != null:
				var grey = (col.r + col.g + col.b) / 3.0
				var worn = Color(col.r, col.g, col.b).lerp(Color(grey, grey, grey), desat).darkened(dark)
				worn.a = col.a
				g[r][c] = worn

static func _blob(g: Array, cols: int, rows: int, cx: int, cy: int, rad: int, fn: Callable) -> void:
	for r in range(maxi(0, cy - rad), mini(rows, cy + rad + 1)):
		for c in range(maxi(0, cx - rad), mini(cols, cx + rad + 1)):
			if (c - cx) * (c - cx) + (r - cy) * (r - cy) <= rad * rad:
				fn.call(r, c)

static func _scorch(g: Array, cols: int, rows: int, share: float, rng: RandomNumberGenerator) -> void:
	var n = int(share * float(cols * rows) / 40.0)
	for i in range(n):
		var rad = rng.randi_range(2, 5)
		_blob(g, cols, rows, rng.randi() % cols, rng.randi() % rows, rad, func(r, c):
			if g[r][c] != null:
				g[r][c] = g[r][c].darkened(0.35 + 0.1 * float(rng.randi() % 3)))

static func _cracks(g: Array, cols: int, rows: int, n: int, rng: RandomNumberGenerator) -> void:
	for i in range(n):
		var c = rng.randi() % cols
		var r = 0
		while r < rows - 1:
			if g[r][c] != null:
				g[r][c] = g[r][c].darkened(0.55)
			r += 1
			c = clampi(c + rng.randi_range(-1, 1), 0, cols - 1)
			if rng.randf() < 0.04:
				break

static func _chip(g: Array, cols: int, rows: int, chip: float, holes: float, rng: RandomNumberGenerator) -> void:
	# Ragged tops: knock a random depth off the top of each column, squared so most columns lose little and a few lose a lot.
	for c in range(cols):
		var depth = int(pow(rng.randf(), 2.0) * chip * float(rows) * 1.6)
		if rng.randf() < chip * 0.35:
			depth += int(chip * float(rows) * 0.5) # a blown-out section
		var cleared = 0
		for r in range(rows - 2):
			if cleared >= depth:
				break
			if g[r][c] != null:
				g[r][c] = null
				cleared += 1
	var n = int(holes * float(cols * rows) / 100.0 * 4.0)
	for i in range(n):
		var rad = rng.randi_range(1, 3)
		_blob(g, cols, rows, rng.randi() % cols, rng.randi() % maxi(1, rows - 2), rad, func(r, c):
			if r < rows - 2:
				g[r][c] = null)

static func _overgrow(g: Array, cols: int, rows: int, grow: float, rng: RandomNumberGenerator) -> void:
	var greens = [Color(0.2, 0.42, 0.16), Color(0.28, 0.5, 0.2), Color(0.16, 0.33, 0.14)]
	for c in range(cols):
		var h = int(rng.randf() * grow * float(rows) * 2.0)
		for k in range(h):
			var r = rows - 1 - k
			if r < 0:
				break
			if g[r][c] != null or k < 2:
				if rng.randf() < 0.8:
					g[r][c] = greens[rng.randi() % greens.size()]
	# a few climbing vines
	for i in range(maxi(1, cols / 16)):
		var c = rng.randi() % cols
		var r = rows - 1
		while r > rows / 3 and rng.randf() < 0.96:
			if g[r][c] != null:
				g[r][c] = greens[rng.randi() % greens.size()]
			r -= 1
			c = clampi(c + rng.randi_range(-1, 1), 0, cols - 1)

static func _crater(g: Array, cols: int, rows: int, rng: RandomNumberGenerator) -> void:
	var rad = rng.randi_range(3, maxi(4, mini(8, cols / 6)))
	var cx = rng.randi() % cols
	var cy = rows - 1 - rng.randi() % 2
	for r in range(maxi(0, cy - rad), rows):
		for c in range(maxi(0, cx - rad), mini(cols, cx + rad + 1)):
			var d2 = (c - cx) * (c - cx) + (r - cy) * (r - cy) * 3
			if d2 <= rad * rad:
				g[r][c] = Color(0.18, 0.14, 0.11) if d2 <= (rad - 1) * (rad - 1) else Color(0.4, 0.32, 0.22)

static func _wire(g: Array, cols: int, rows: int) -> void:
	var r = rows - 1
	for c in range(cols):
		if g[r][c] == null:
			g[r][c] = Color(0.2, 0.2, 0.22) if c % 3 != 1 else Color(0.5, 0.5, 0.52)
	if rows > 2:
		for c in range(0, cols, 3):
			if g[rows - 2][c] == null:
				g[rows - 2][c] = Color(0.2, 0.2, 0.22) # posts

static func _poppies(g: Array, cols: int, rows: int, density: float, rng: RandomNumberGenerator) -> void:
	for c in range(cols):
		for k in range(3):
			var r = rows - 1 - k
			if r >= 0 and g[r][c] == null and rng.randf() < density:
				g[r][c] = Color(0.85, 0.12, 0.1)
				if r + 1 < rows and g[r + 1][c] == null:
					g[r + 1][c] = Color(0.2, 0.4, 0.15) # stalk

static func _merge(g: Array, cols: int, rows: int) -> Array:
	# horizontal runs of one colour, then stack identical runs on consecutive rows
	var open: Dictionary = {} # "c0:c1:colorhex" -> [r_start, color]
	var out: Array = []
	for r in range(rows + 1):
		var runs: Dictionary = {}
		if r < rows:
			var c = 0
			while c < cols:
				var col = g[r][c]
				if col == null:
					c += 1
					continue
				var c1 = c + 1
				while c1 < cols and g[r][c1] != null and g[r][c1] == col:
					c1 += 1
				runs["%d:%d:%s" % [c, c1, col.to_html()]] = [c, c1, col]
				c = c1
		for key in open.keys():
			if not runs.has(key):
				var o = open[key]
				out.append([Rect2(o[1] * PIX, o[0] * PIX, (o[2] - o[1]) * PIX, (r - o[0]) * PIX), o[3]])
				open.erase(key)
		for key in runs:
			if not open.has(key):
				open[key] = [r, runs[key][0], runs[key][1], runs[key][2]]
	return out
