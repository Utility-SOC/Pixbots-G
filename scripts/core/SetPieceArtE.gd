class_name SetPieceArtE
extends RefCounted

# Fifth art file: hypertech terrain for the "Hyper" map variants (Coruscant-style ecumenopolis, arcologies, maglev, hardlight,
# orbital hardware) and sci-fi interiors. Same contract as SetPieceArt: [Rect2, Color] in footprint top-left coordinates,
# deterministic per seed.

static func styles() -> Array:
	return ["sky_spire", "arcology", "maglev_station", "holo_billboard", "shield_projector", "orbital_lift_base", "vertical_farm",
		"hover_pylon", "data_spire", "fusion_plant", "skybridge", "cyber_torii", "drone_hive", "cargo_lift", "plasma_turbines",
		"bio_lab", "mech_foundry", "hardlight_barrier", "orbital_gun", "neon_market", "crystal_spire", "void_gate",
		"console_bank", "server_rack", "hologram_table", "cryo_pod", "reactor_core", "airlock"]

const CYAN = Color(0.3, 0.9, 1.0)
const MAGENTA = Color(0.95, 0.3, 0.8)
const LIME = Color(0.6, 1.0, 0.4)
const AMBER = Color(1.0, 0.7, 0.2)
const CHROME = Color(0.78, 0.82, 0.88)
const CHROME_D = Color(0.5, 0.55, 0.64)
const HULL = Color(0.2, 0.23, 0.3)
const HULL_D = Color(0.1, 0.12, 0.17)
const GLASS = Color(0.25, 0.45, 0.6)

static func _f(o: Array, c0: int, r0: int, c1: int, r1: int, col: Color, cols: int, rows: int) -> void:
	SetPieceArt._f(o, c0, r0, c1, r1, col, cols, rows)

static func _disc(o: Array, cx: int, cy: int, rad: int, col: Color, cols: int, rows: int, top_only: bool = false) -> void:
	SetPieceArtC._disc(o, cx, cy, rad, col, cols, rows, top_only)

# rows of lit windows
static func _lit(o: Array, c0: int, r0: int, c1: int, r1: int, cols: int, rows: int, rng: RandomNumberGenerator, col: Color = Color(1.0, 0.9, 0.55)) -> void:
	var r = r0
	while r + 2 <= r1:
		var c = c0
		while c + 1 <= c1:
			if rng.randf() < 0.55:
				_f(o, c, r, c + 1, r + 1, col if rng.randf() < 0.8 else CYAN, cols, rows)
			c += 2
		r += 3

static func rects(style: String, footprint: Vector2, seed_v: int) -> Array:
	var cols = int(footprint.x / SetPieceArt.PIX)
	var rows = int(footprint.y / SetPieceArt.PIX)
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_v
	var o: Array = []
	match style:
		"sky_spire":
			for t in range(4):
				var inset = t * maxi(1, cols / 9)
				var r0 = 6 + t * rows / 6
				_f(o, inset, r0, cols - inset, rows, HULL if t % 2 == 0 else Color(0.16, 0.2, 0.28), cols, rows)
				_f(o, inset, r0, cols - inset, r0 + 1, CYAN, cols, rows)
				_lit(o, inset + 1, r0 + 2, cols - inset - 2, rows - 4, cols, rows, rng)
			_f(o, cols / 2 - 1, 0, cols / 2 + 1, 8, CHROME, cols, rows)
			_f(o, cols / 2, 0, cols / 2 + 1, 2, MAGENTA, cols, rows)
			_f(o, cols / 2 - 3, rows - 3, cols / 2 + 3, rows, CYAN.darkened(0.4), cols, rows)
		"arcology":
			var tiers = 5
			for t in range(tiers):
				var inset = t * cols / (2 * tiers + 2)
				var r0 = rows * t / tiers
				var r1 = rows * (t + 1) / tiers
				_f(o, inset, r0 + 1, cols - inset, rows, CHROME_D.darkened(0.15 * float(t % 2)), cols, rows)
				_f(o, inset, r0, cols - inset, r0 + 2, Color(0.25, 0.55, 0.28), cols, rows) # roof gardens
				_lit(o, inset + 1, r0 + 3, cols - inset - 2, r1, cols, rows, rng)
			_f(o, cols / 2 - 3, rows - 5, cols / 2 + 3, rows, HULL_D, cols, rows)
		"maglev_station":
			_f(o, 0, rows / 2, cols, rows / 2 + 3, CHROME_D, cols, rows) # elevated rail bed
			_f(o, 0, rows / 2 + 3, cols, rows / 2 + 4, CYAN, cols, rows)
			for c in range(2, cols - 2, 8):
				_f(o, c, rows / 2 + 4, c + 2, rows, HULL, cols, rows) # pylons
			_f(o, cols / 4, rows / 4, cols - cols / 4, rows / 2, GLASS, cols, rows) # canopy
			for k in range(cols / 4):
				_f(o, cols / 4 + k, rows / 4 - k / 6, cols / 4 + k + 1, rows / 4, CHROME, cols, rows)
			_f(o, 2, rows / 2 - 4, cols / 3, rows / 2, MAGENTA.darkened(0.2), cols, rows) # a train
			_f(o, 3, rows / 2 - 3, cols / 3 - 1, rows / 2 - 2, CYAN, cols, rows)
		"holo_billboard":
			_f(o, cols / 2 - 1, rows / 2, cols / 2 + 1, rows, CHROME_D, cols, rows)
			_f(o, 1, 1, cols - 1, rows / 2, Color(0.05, 0.1, 0.18), cols, rows)
			for k in range(4):
				_f(o, 3, 3 + k * 3, 3 + cols / 2 + (k * 5) % (cols / 3), 4 + k * 3, [MAGENTA, CYAN, AMBER, LIME][k], cols, rows)
			_f(o, cols / 2 - 5, rows - 2, cols / 2 + 5, rows, HULL, cols, rows)
		"shield_projector":
			_f(o, cols / 2 - 3, rows - 6, cols / 2 + 3, rows, HULL, cols, rows)
			_f(o, cols / 2 - 1, rows / 3, cols / 2 + 1, rows - 6, CHROME, cols, rows)
			_disc(o, cols / 2, rows / 3, mini(cols / 2 - 1, rows / 3), Color(0.3, 0.85, 1.0, 1.0), cols, rows, true)
			_disc(o, cols / 2, rows / 3, mini(cols / 2 - 3, rows / 3 - 2), Color(0.15, 0.4, 0.6), cols, rows, true)
			_f(o, cols / 2 - 1, rows / 3 - 3, cols / 2 + 1, rows / 3, Color(0.9, 1.0, 1.0), cols, rows)
		"orbital_lift_base":
			_f(o, 1, rows * 2 / 3, cols - 1, rows, HULL, cols, rows)
			_f(o, 3, rows / 2, cols - 3, rows * 2 / 3, CHROME_D, cols, rows)
			_f(o, cols / 2 - 2, 0, cols / 2 + 2, rows / 2, CHROME, cols, rows) # the tether, up and out of sight
			_f(o, cols / 2 - 1, 0, cols / 2, rows / 2, CYAN, cols, rows)
			for c in range(3, cols - 3, 6):
				_f(o, c, rows * 2 / 3 + 2, c + 2, rows - 2, CYAN.darkened(0.3), cols, rows)
		"vertical_farm":
			_f(o, 0, 2, cols, rows, GLASS.darkened(0.2), cols, rows)
			for r in range(4, rows - 2, 4):
				_f(o, 1, r, cols - 1, r + 2, Color(0.25, 0.6, 0.3), cols, rows) # growing racks
				_f(o, 1, r + 2, cols - 1, r + 3, MAGENTA.darkened(0.2), cols, rows) # grow-lights
			_f(o, 0, 0, cols, 2, CHROME, cols, rows)
			_f(o, cols / 2 - 2, rows - 4, cols / 2 + 2, rows, HULL_D, cols, rows)
		"hover_pylon":
			_f(o, cols / 2 - 2, rows / 2, cols / 2 + 2, rows, CHROME_D, cols, rows)
			_disc(o, cols / 2, rows / 3, mini(cols / 2 - 1, rows / 3), HULL, cols, rows)
			_disc(o, cols / 2, rows / 3, mini(cols / 2 - 3, rows / 3 - 2), Color(0.1, 0.35, 0.5), cols, rows)
			_f(o, cols / 2 - 6, rows / 3 - 1, cols / 2 + 6, rows / 3 + 1, CYAN, cols, rows)
			_f(o, cols / 2 - 1, 0, cols / 2 + 1, 3, AMBER, cols, rows)
		"data_spire":
			_f(o, cols / 4, 2, cols - cols / 4, rows, Color(0.07, 0.08, 0.12), cols, rows)
			for r in range(4, rows - 3, 3):
				_f(o, cols / 4 + 1, r, cols - cols / 4 - 1, r + 1, CYAN if (r / 3) % 2 == 0 else MAGENTA, cols, rows)
			for k in range(3):
				_f(o, cols / 4 - 2 - k, rows - 6 - k * 4, cols / 4, rows - 5 - k * 4, CHROME_D, cols, rows) # cooling fins
				_f(o, cols - cols / 4, rows - 6 - k * 4, cols - cols / 4 + 2 + k, rows - 5 - k * 4, CHROME_D, cols, rows)
			_f(o, cols / 2 - 1, 0, cols / 2 + 1, 3, LIME, cols, rows)
		"fusion_plant":
			var rad = mini(cols, rows) / 2 - 1
			_disc(o, cols / 2, rows / 2, rad, HULL, cols, rows)
			_disc(o, cols / 2, rows / 2, rad - 2, Color(0.1, 0.18, 0.26), cols, rows)
			_disc(o, cols / 2, rows / 2, rad - 4, HULL, cols, rows)
			_disc(o, cols / 2, rows / 2, maxi(2, rad - 6), Color(0.9, 0.95, 1.0), cols, rows)
			for k in range(8):
				var a = TAU * float(k) / 8.0
				_f(o, cols / 2 + int(cos(a) * (rad - 3)), rows / 2 + int(sin(a) * (rad - 3)), cols / 2 + int(cos(a) * (rad - 3)) + 2, rows / 2 + int(sin(a) * (rad - 3)) + 2, CYAN, cols, rows)
		"skybridge":
			var w = maxi(3, cols / 6)
			_f(o, 0, 0, w, rows, HULL, cols, rows)
			_f(o, cols - w, 0, cols, rows, HULL, cols, rows)
			_f(o, w, rows / 3, cols - w, rows / 3 + 4, CHROME, cols, rows)
			_f(o, w, rows / 3 + 4, cols - w, rows / 3 + 5, CYAN, cols, rows)
			_lit(o, 1, 2, w - 1, rows - 2, cols, rows, rng)
			_lit(o, cols - w + 1, 2, cols - 1, rows - 2, cols, rows, rng)
		"cyber_torii":
			_f(o, 2, rows / 4, 5, rows, Color(0.7, 0.1, 0.25), cols, rows)
			_f(o, cols - 5, rows / 4, cols - 2, rows, Color(0.7, 0.1, 0.25), cols, rows)
			_f(o, 0, rows / 4 - 3, cols, rows / 4, Color(0.85, 0.15, 0.3), cols, rows)
			_f(o, 4, rows / 4 + 3, cols - 4, rows / 4 + 5, Color(0.6, 0.1, 0.22), cols, rows)
			_f(o, 2, rows / 4 - 1, cols - 2, rows / 4, MAGENTA, cols, rows) # neon edge
			_f(o, cols / 2 - 2, rows / 4 + 6, cols / 2 + 2, rows / 4 + 9, CYAN, cols, rows)
		"drone_hive":
			for r in range(1, rows - 3, 4):
				for c in range(1 + (r / 4) % 2 * 3, cols - 4, 6):
					_disc(o, c + 2, r + 2, 2, HULL if (r + c) % 3 else Color(0.18, 0.3, 0.4), cols, rows)
					_f(o, c + 2, r + 2, c + 3, r + 3, AMBER, cols, rows)
			_f(o, 0, rows - 2, cols, rows, HULL_D, cols, rows)
		"cargo_lift":
			_f(o, 1, 0, 4, rows, HULL, cols, rows)
			_f(o, cols - 4, 0, cols - 1, rows, HULL, cols, rows)
			_f(o, 4, 0, cols - 4, 2, CHROME_D, cols, rows)
			_f(o, 5, rows / 3, cols - 5, rows / 3 + 6, Color(0.7, 0.4, 0.15), cols, rows) # a container mid-lift
			_f(o, cols / 2, 2, cols / 2 + 1, rows / 3, CHROME, cols, rows)
			_f(o, 0, rows - 2, cols, rows, HULL_D, cols, rows)
		"plasma_turbines":
			for i in range(maxi(2, cols / 8)):
				var cx = cols * (2 * i + 1) / (2 * maxi(2, cols / 8))
				_f(o, cx - 1, rows / 3, cx + 1, rows, CHROME, cols, rows)
				for k in range(rows / 3):
					_f(o, cx - k, rows / 3 - k, cx - k + 1, rows / 3 - k + 1, CYAN, cols, rows)
					_f(o, cx + k, rows / 3 - k, cx + k + 1, rows / 3 - k + 1, CYAN, cols, rows)
				_disc(o, cx, rows / 3, 2, MAGENTA, cols, rows)
		"bio_lab":
			_disc(o, cols / 3, rows - 2, mini(cols / 3, rows - 4), Color(0.5, 0.85, 0.7), cols, rows, true)
			_f(o, cols / 3 + 2, rows * 2 / 3, cols - 2, rows - 1, CHROME_D, cols, rows)
			for c in range(cols / 3 + 4, cols - 4, 5):
				_f(o, c, rows * 2 / 3 + 1, c + 3, rows - 2, Color(0.3, 0.85, 0.45), cols, rows) # sample tanks
			_f(o, cols / 3, rows * 2 / 3 - 4, cols / 3 + 1, rows * 2 / 3, CHROME, cols, rows)
		"mech_foundry":
			_f(o, 0, rows / 3, cols, rows, HULL, cols, rows)
			_f(o, 0, rows / 3 - 2, cols, rows / 3, CHROME_D, cols, rows)
			for c in range(2, cols - 6, 10):
				_f(o, c, 2, c + 2, rows / 3, CHROME, cols, rows) # gantry masts
				_f(o, c, 2, c + 8, 4, CHROME_D, cols, rows)
				_f(o, c + 4, 4, c + 5, rows / 3 + 6, AMBER, cols, rows) # welding arm spark
			_f(o, cols / 4, rows / 2, cols - cols / 4, rows - 2, Color(0.5, 0.18, 0.1), cols, rows) # molten channel
			_f(o, cols / 4 + 2, rows / 2 + 1, cols - cols / 4 - 2, rows / 2 + 3, AMBER, cols, rows)
		"hardlight_barrier":
			_f(o, 0, rows / 2 - 2, 3, rows, HULL, cols, rows)
			_f(o, cols - 3, rows / 2 - 2, cols, rows, HULL, cols, rows)
			_f(o, 3, rows / 3, cols - 3, rows - 2, Color(0.2, 0.7, 0.95), cols, rows)
			for r in range(rows / 3, rows - 2, 2):
				_f(o, 3, r, cols - 3, r + 1, Color(0.6, 0.95, 1.0), cols, rows)
		"orbital_gun":
			_f(o, 2, rows * 2 / 3, cols - 2, rows, HULL, cols, rows)
			_f(o, cols / 3, rows / 2, cols - cols / 3, rows * 2 / 3, CHROME_D, cols, rows)
			for k in range(cols - 8): # the long barrel, raised
				_f(o, 6 + k, rows / 2 - 2 - k / 6, 7 + k, rows / 2 - k / 6, CHROME if k % 6 else CYAN, cols, rows)
			_f(o, 1, rows * 2 / 3, 3, rows * 2 / 3 + 3, MAGENTA, cols, rows)
		"neon_market":
			var n = maxi(3, cols / 6)
			for i in range(n):
				var c0 = i * cols / n
				var col = [MAGENTA, CYAN, AMBER, LIME][i % 4]
				_f(o, c0 + 1, rows / 2, c0 + cols / n - 1, rows, HULL, cols, rows)
				_f(o, c0 + 1, rows / 2 - 3, c0 + cols / n - 1, rows / 2, col, cols, rows) # sign
				_f(o, c0 + 2, rows / 2 + 2, c0 + cols / n - 2, rows - 2, col.darkened(0.5), cols, rows)
		"crystal_spire":
			for k in range(rows):
				var half = 1 + (k * (cols / 3)) / rows
				_f(o, cols / 2 - half, k, cols / 2 + half, k + 1, Color(0.5, 0.8, 1.0).lerp(Color(0.7, 0.4, 1.0), float(k) / float(rows)), cols, rows)
			for c in range(2, cols - 2, 5):
				_f(o, c, rows * 2 / 3, c + 2, rows, Color(0.6, 0.45, 1.0), cols, rows)
		"void_gate":
			var rad = mini(cols, rows) / 2 - 1
			_disc(o, cols / 2, rows / 2, rad, HULL, cols, rows)
			_disc(o, cols / 2, rows / 2, rad - 3, Color(0.04, 0.02, 0.1), cols, rows)
			_disc(o, cols / 2, rows / 2, rad - 6, Color(0.35, 0.1, 0.7), cols, rows)
			_disc(o, cols / 2, rows / 2, maxi(1, rad - 9), Color(0.05, 0.02, 0.1), cols, rows)
			_f(o, cols / 2 - rad, rows / 2 - 1, cols / 2 - rad + 2, rows / 2 + 1, CYAN, cols, rows)
			_f(o, cols / 2 + rad - 2, rows / 2 - 1, cols / 2 + rad, rows / 2 + 1, CYAN, cols, rows)
		# ---- sci-fi interior furniture ------------------------------------------------------------------------
		"console_bank":
			_f(o, 0, rows / 3, cols, rows, HULL, cols, rows)
			_f(o, 1, rows / 3 - 2, cols - 1, rows / 3, Color(0.05, 0.2, 0.3), cols, rows)
			for c in range(2, cols - 3, 4):
				_f(o, c, rows / 3 - 1, c + 2, rows / 3, CYAN, cols, rows)
				_f(o, c, rows / 2, c + 3, rows / 2 + 1, AMBER if (c / 4) % 2 else LIME, cols, rows)
		"server_rack":
			for c in range(1, cols - 3, 5):
				_f(o, c, 1, c + 4, rows - 1, Color(0.1, 0.11, 0.15), cols, rows)
				for r in range(3, rows - 3, 2):
					_f(o, c + 1, r, c + 3, r + 1, LIME if rng.randf() < 0.7 else AMBER, cols, rows)
		"hologram_table":
			_f(o, 2, rows * 2 / 3, cols - 2, rows - 1, HULL, cols, rows)
			_disc(o, cols / 2, rows / 3, mini(cols / 2 - 2, rows / 3), Color(0.2, 0.6, 0.85), cols, rows, true)
			_f(o, cols / 2 - 1, rows / 3 - 3, cols / 2 + 1, rows / 3, Color(0.8, 1.0, 1.0), cols, rows)
		"cryo_pod":
			for c in range(1, cols - 4, 5):
				_f(o, c, 1, c + 4, rows - 1, Color(0.5, 0.8, 0.9), cols, rows)
				_f(o, c + 1, 3, c + 3, rows - 3, Color(0.15, 0.35, 0.5), cols, rows)
				_f(o, c + 1, rows / 2 - 1, c + 3, rows / 2 + 2, Color(0.85, 0.95, 1.0), cols, rows)
		"reactor_core":
			_disc(o, cols / 2, rows / 2, mini(cols, rows) / 2 - 1, HULL, cols, rows)
			_disc(o, cols / 2, rows / 2, mini(cols, rows) / 2 - 3, Color(0.1, 0.4, 0.6), cols, rows)
			_disc(o, cols / 2, rows / 2, mini(cols, rows) / 2 - 5, Color(0.8, 1.0, 1.0), cols, rows)
		"airlock":
			_f(o, 0, 0, cols, rows, HULL, cols, rows)
			_f(o, cols / 4, 2, cols - cols / 4, rows - 2, Color(0.08, 0.1, 0.14), cols, rows)
			_f(o, cols / 2 - 1, 2, cols / 2 + 1, rows - 2, CHROME_D, cols, rows)
			for r in range(2, rows - 2, 3):
				_f(o, cols / 4 - 1, r, cols / 4, r + 1, AMBER, cols, rows)
				_f(o, cols - cols / 4, r, cols - cols / 4 + 1, r + 1, AMBER, cols, rows)
	return o
