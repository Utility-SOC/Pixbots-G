class_name SetPieceArtC
extends RefCounted

# Third art file for the set-piece library: sci-fi terrain, dungeon furniture ("indoor", D&D vibes) and surreal pieces.
# Same contract as SetPieceArt: [Rect2, Color] in footprint top-left coordinates, deterministic per seed.

static func styles() -> Array:
	return ["hab_dome", "reactor_tower", "landing_pad", "comms_spire", "cryo_tanks", "gantry_bay", "force_pylon", "data_monolith", "bio_dome",
		"altar", "sarcophagus", "throne", "pillar_cluster", "brazier", "treasure_hoard", "bookshelves", "torture_rack", "summoning_circle",
		"stone_well", "hearth", "banquet_table", "iron_cage", "gargoyle",
		"floating_arch", "stair_to_nowhere", "eye_pillar", "melting_clock", "lone_door", "chess_tower", "balloon_house", "cloud_pedestal"]

const CYAN = Color(0.35, 0.85, 0.9)
const PLAS = Color(0.82, 0.84, 0.88)
const PLAS_D = Color(0.6, 0.63, 0.7)
const HULL = Color(0.28, 0.3, 0.38)
const NEON = Color(0.9, 0.3, 0.75)
const TORCH = Color(0.95, 0.6, 0.2)
const MARBLE = Color(0.82, 0.8, 0.78)
const FLESH = Color(0.8, 0.7, 0.62)

static func _f(o: Array, c0: int, r0: int, c1: int, r1: int, col: Color, cols: int, rows: int) -> void:
	SetPieceArt._f(o, c0, r0, c1, r1, col, cols, rows)

# Filled disc (as stacked rows) centred at (cx, cy).
static func _disc(o: Array, cx: int, cy: int, rad: int, col: Color, cols: int, rows: int, top_only: bool = false) -> void:
	for dy in range(-rad, 1 if top_only else rad + 1):
		var half = int(sqrt(maxf(0.0, float(rad * rad - dy * dy))))
		_f(o, cx - half, cy + dy, cx + half + 1, cy + dy + 1, col, cols, rows)

static func rects(style: String, footprint: Vector2, seed_v: int) -> Array:
	var cols = int(footprint.x / SetPieceArt.PIX)
	var rows = int(footprint.y / SetPieceArt.PIX)
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_v
	var o: Array = []
	match style:
		"hab_dome":
			_disc(o, cols / 2, rows - 2, mini(cols / 2 - 1, rows - 3), PLAS, cols, rows, true)
			_f(o, 1, rows - 3, cols - 1, rows, PLAS_D, cols, rows)
			_f(o, cols / 2 - 2, rows - 5, cols / 2 + 2, rows, HULL, cols, rows)
			for c in range(4, cols - 4, 5):
				_f(o, c, rows / 2, c + 2, rows / 2 + 3, CYAN, cols, rows)
		"reactor_tower":
			_f(o, cols / 4, rows / 5, cols - cols / 4, rows, HULL, cols, rows)
			_f(o, cols / 4 - 1, rows / 5 - 1, cols - cols / 4 + 1, rows / 5 + 1, PLAS_D, cols, rows)
			for r in range(rows / 4, rows - 3, 4):
				_f(o, cols / 4, r, cols - cols / 4, r + 1, CYAN.darkened(0.4), cols, rows)
			_f(o, cols / 2 - 1, rows / 5 - 4, cols / 2 + 1, rows / 5, CYAN, cols, rows) # core glow
			_f(o, 0, rows - 3, cols, rows, PLAS_D, cols, rows)
		"landing_pad":
			_f(o, 0, 0, cols, rows, HULL, cols, rows)
			_f(o, 1, 1, cols - 1, rows - 1, PLAS_D.darkened(0.3), cols, rows)
			_disc(o, cols / 2, rows / 2, mini(cols, rows) / 2 - 2, PLAS_D, cols, rows)
			_f(o, cols / 2 - 1, rows / 2 - 4, cols / 2 + 1, rows / 2 + 4, Color(0.9, 0.8, 0.2), cols, rows) # H marking
			_f(o, cols / 2 - 3, rows / 2 - 1, cols / 2 + 3, rows / 2 + 1, Color(0.9, 0.8, 0.2), cols, rows)
			for c in [1, cols - 2]:
				_f(o, c, 1, c + 1, 3, NEON, cols, rows)
				_f(o, c, rows - 3, c + 1, rows - 1, NEON, cols, rows)
		"comms_spire":
			_f(o, cols / 2 - 1, 3, cols / 2 + 1, rows, PLAS_D, cols, rows)
			for r in range(8, rows - 4, 7):
				_f(o, cols / 2 - 5 + r / 7, r, cols / 2 + 5 - r / 7, r + 1, PLAS, cols, rows)
				_f(o, cols / 2 - 5 + r / 7, r - 1, cols / 2 - 4 + r / 7, r + 2, CYAN, cols, rows)
				_f(o, cols / 2 + 4 - r / 7, r - 1, cols / 2 + 5 - r / 7, r + 2, CYAN, cols, rows)
			_f(o, cols / 2 - 1, 0, cols / 2 + 1, 3, NEON, cols, rows)
			_f(o, cols / 2 - 4, rows - 4, cols / 2 + 4, rows, HULL, cols, rows)
		"cryo_tanks":
			var n = maxi(2, cols / 7)
			for i in range(n):
				var c0 = 1 + i * (cols - 2) / n
				var w = (cols - 2) / n - 2
				_f(o, c0, rows / 4, c0 + w, rows - 2, Color(0.5, 0.8, 0.9, 1.0), cols, rows)
				_f(o, c0 + 1, rows / 4 + 2, c0 + w - 1, rows - 4, Color(0.2, 0.45, 0.6), cols, rows)
				_f(o, c0, rows / 4 - 2, c0 + w, rows / 4, PLAS_D, cols, rows)
				_f(o, c0 + w / 2, rows / 4 + 4, c0 + w / 2 + 1, rows / 2 + 2, Color(0.85, 0.95, 1.0), cols, rows) # frozen figure
			_f(o, 0, rows - 2, cols, rows, HULL, cols, rows)
		"gantry_bay":
			_f(o, 0, rows / 3, cols, rows, HULL, cols, rows)
			_f(o, 0, rows / 3, cols, rows / 3 + 2, PLAS_D, cols, rows)
			_f(o, cols / 4, rows / 2, cols - cols / 4, rows, Color(0.1, 0.12, 0.16), cols, rows) # bay opening
			for c in range(2, cols - 2, 6):
				_f(o, c, 2, c + 1, rows / 3, PLAS_D, cols, rows) # gantry masts
				_f(o, c, 2, c + 6, 3, PLAS_D, cols, rows)
			_f(o, cols / 2 - 1, rows / 2 + 2, cols / 2 + 1, rows - 3, CYAN.darkened(0.3), cols, rows)
		"force_pylon":
			_f(o, cols / 2 - 2, rows - 4, cols / 2 + 2, rows, HULL, cols, rows)
			_f(o, cols / 2 - 1, rows / 3, cols / 2 + 1, rows - 4, PLAS_D, cols, rows)
			_disc(o, cols / 2, rows / 3, 3, CYAN, cols, rows)
			_f(o, 1, rows / 3 - 1, cols - 1, rows / 3 + 1, CYAN.darkened(0.3), cols, rows) # field arc
		"data_monolith":
			_f(o, cols / 2 - 3, 1, cols / 2 + 3, rows - 2, Color(0.08, 0.09, 0.12), cols, rows)
			for r in range(4, rows - 5, 3):
				_f(o, cols / 2 - 2, r, cols / 2 + 2, r + 1, NEON if r % 6 == 4 else CYAN, cols, rows)
			_f(o, cols / 2 - 4, rows - 2, cols / 2 + 4, rows, HULL, cols, rows)
		"bio_dome":
			_disc(o, cols / 2, rows - 2, mini(cols / 2 - 1, rows - 3), Color(0.55, 0.85, 0.7), cols, rows, true)
			for c in range(2, cols - 2, 5):
				_f(o, c, rows / 3, c + 1, rows - 2, PLAS_D, cols, rows)
			_f(o, 1, rows - 4, cols - 1, rows, Color(0.2, 0.45, 0.2), cols, rows)
			for c in range(3, cols - 4, 6):
				_f(o, c, rows - 7, c + 3, rows - 4, Color(0.3, 0.6, 0.25), cols, rows)
		# ---- dungeon furniture -------------------------------------------------------------------------------
		"altar":
			_f(o, 1, rows / 2, cols - 1, rows, Color(0.38, 0.36, 0.42), cols, rows)
			_f(o, 0, rows / 2 - 2, cols, rows / 2, Color(0.5, 0.48, 0.55), cols, rows)
			_f(o, cols / 2 - 1, rows / 4, cols / 2 + 1, rows / 2 - 2, Color(0.8, 0.15, 0.12), cols, rows) # candle-red offering
			_f(o, 2, rows / 2 - 5, 3, rows / 2 - 2, TORCH, cols, rows)
			_f(o, cols - 3, rows / 2 - 5, cols - 2, rows / 2 - 2, TORCH, cols, rows)
		"sarcophagus":
			_f(o, 0, rows / 3, cols, rows, Color(0.5, 0.48, 0.44), cols, rows)
			_f(o, 1, rows / 3 - 2, cols - 1, rows / 3, Color(0.62, 0.6, 0.55), cols, rows)
			_f(o, cols / 2 - 2, rows / 3 + 1, cols / 2 + 2, rows - 2, Color(0.4, 0.38, 0.35), cols, rows)
			_f(o, cols / 2 - 1, rows / 3, cols / 2 + 1, rows / 3 + 2, GOLD(), cols, rows)
		"throne":
			_f(o, cols / 2 - 4, 0, cols / 2 + 4, rows - 3, Color(0.35, 0.1, 0.12), cols, rows)
			_f(o, cols / 2 - 5, rows / 3, cols / 2 + 5, rows / 3 + 2, GOLD(), cols, rows)
			_f(o, cols / 2 - 3, rows / 2, cols / 2 + 3, rows - 3, Color(0.5, 0.15, 0.15), cols, rows)
			_f(o, cols / 2 - 6, rows - 3, cols / 2 + 6, rows, Color(0.4, 0.38, 0.42), cols, rows)
			_f(o, cols / 2 - 1, 0, cols / 2 + 1, 2, GOLD(), cols, rows)
		"pillar_cluster":
			for c in range(2, cols - 3, maxi(5, cols / 3)):
				_f(o, c, 2, c + 4, rows - 2, MARBLE, cols, rows)
				_f(o, c, 2, c + 1, rows - 2, MARBLE.darkened(0.2), cols, rows)
				_f(o, c - 1, 1, c + 5, 3, MARBLE.lightened(0.1), cols, rows)
				_f(o, c - 1, rows - 3, c + 5, rows - 1, MARBLE.darkened(0.15), cols, rows)
		"brazier":
			_f(o, cols / 2 - 1, rows / 2, cols / 2 + 1, rows, Color(0.3, 0.28, 0.3), cols, rows)
			_f(o, cols / 2 - 4, rows / 2 - 2, cols / 2 + 4, rows / 2, Color(0.4, 0.36, 0.34), cols, rows)
			_disc(o, cols / 2, rows / 2 - 3, 3, TORCH, cols, rows, true)
			_f(o, cols / 2 - 1, 1, cols / 2 + 1, rows / 2 - 4, Color(1.0, 0.85, 0.3), cols, rows)
		"treasure_hoard":
			for k in range(rows * 2):
				var c = rng.randi() % maxi(1, cols - 2)
				var r = rows / 3 + int(rng.randf() * float(rows * 2 / 3 - 1))
				_f(o, c, r, c + 2, r + 1, GOLD() if k % 3 else Color(0.9, 0.9, 0.95), cols, rows)
			_f(o, cols / 2 - 3, rows / 2, cols / 2 + 3, rows - 2, Color(0.5, 0.3, 0.15), cols, rows) # chest
			_f(o, cols / 2 - 3, rows / 2, cols / 2 + 3, rows / 2 + 1, GOLD(), cols, rows)
		"bookshelves":
			_f(o, 0, 0, cols, rows, Color(0.35, 0.22, 0.14), cols, rows)
			for r in range(2, rows - 2, 4):
				_f(o, 1, r + 3, cols - 1, r + 4, Color(0.25, 0.15, 0.1), cols, rows)
				var c = 1
				while c < cols - 2:
					var w = rng.randi_range(1, 2)
					var cc = [Color(0.6, 0.15, 0.15), Color(0.15, 0.35, 0.5), Color(0.2, 0.45, 0.25), Color(0.7, 0.55, 0.2)][rng.randi() % 4]
					_f(o, c, r, c + w, r + 3, cc, cols, rows)
					c += w
		"torture_rack":
			_f(o, 1, rows / 2, cols - 1, rows / 2 + 3, Color(0.4, 0.28, 0.18), cols, rows)
			_f(o, 0, rows / 2 - 2, 2, rows, Color(0.3, 0.22, 0.15), cols, rows)
			_f(o, cols - 2, rows / 2 - 2, cols, rows, Color(0.3, 0.22, 0.15), cols, rows)
			_f(o, 3, rows / 2 + 3, cols - 3, rows / 2 + 4, Color(0.4, 0.4, 0.42), cols, rows) # chains
			for c in range(4, cols - 4, 3):
				_f(o, c, rows / 2 + 4, c + 1, rows / 2 + 7, Color(0.4, 0.4, 0.42), cols, rows)
		"summoning_circle":
			var rad = mini(cols, rows) / 2 - 1
			_disc(o, cols / 2, rows / 2, rad, Color(0.12, 0.08, 0.14), cols, rows)
			_disc(o, cols / 2, rows / 2, rad - 1, Color(0.2, 0.1, 0.25), cols, rows)
			_disc(o, cols / 2, rows / 2, rad - 3, Color(0.12, 0.08, 0.14), cols, rows)
			for k in range(5):
				var a = TAU * float(k) / 5.0
				_f(o, cols / 2 + int(cos(a) * (rad - 2)), rows / 2 + int(sin(a) * (rad - 2)), cols / 2 + int(cos(a) * (rad - 2)) + 2, rows / 2 + int(sin(a) * (rad - 2)) + 2, NEON, cols, rows)
			_disc(o, cols / 2, rows / 2, 2, Color(0.7, 0.2, 0.9), cols, rows)
		"stone_well":
			_disc(o, cols / 2, rows / 2, mini(cols, rows) / 2 - 1, Color(0.45, 0.43, 0.46), cols, rows)
			_disc(o, cols / 2, rows / 2, mini(cols, rows) / 2 - 3, Color(0.04, 0.05, 0.1), cols, rows)
			_f(o, 1, 0, 2, rows / 2, Color(0.4, 0.28, 0.18), cols, rows)
			_f(o, cols - 2, 0, cols - 1, rows / 2, Color(0.4, 0.28, 0.18), cols, rows)
			_f(o, 1, 0, cols - 1, 2, Color(0.4, 0.28, 0.18), cols, rows)
		"hearth":
			_f(o, 0, 0, cols, rows, Color(0.42, 0.4, 0.4), cols, rows)
			_f(o, 3, rows / 3, cols - 3, rows, Color(0.08, 0.07, 0.08), cols, rows)
			_f(o, 5, rows / 2, cols - 5, rows - 1, TORCH, cols, rows)
			_f(o, cols / 2 - 2, rows / 2 + 2, cols / 2 + 2, rows - 1, Color(1.0, 0.85, 0.3), cols, rows)
			_f(o, 2, rows / 3 - 2, cols - 2, rows / 3, Color(0.55, 0.53, 0.52), cols, rows)
		"banquet_table":
			_f(o, 2, rows / 3, cols - 2, rows / 3 + 5, Color(0.5, 0.33, 0.2), cols, rows)
			_f(o, 2, rows / 3 + 5, cols - 2, rows / 3 + 6, Color(0.35, 0.22, 0.14), cols, rows)
			for c in range(4, cols - 6, 6):
				_f(o, c, rows / 3 - 2, c + 3, rows / 3, Color(0.85, 0.82, 0.7), cols, rows) # platters
				_f(o, c + 3, rows / 3 - 3, c + 4, rows / 3, Color(0.7, 0.15, 0.15), cols, rows)
			for c in range(1, cols - 1, 5):
				_f(o, c, rows - 4, c + 3, rows - 1, Color(0.4, 0.28, 0.18), cols, rows) # benches
		"iron_cage":
			_f(o, 0, 0, cols, 2, Color(0.25, 0.25, 0.28), cols, rows)
			_f(o, 0, rows - 2, cols, rows, Color(0.25, 0.25, 0.28), cols, rows)
			for c in range(0, cols, 3):
				_f(o, c, 0, c + 1, rows, Color(0.3, 0.3, 0.34), cols, rows)
			_f(o, cols / 2 - 1, rows / 2, cols / 2 + 2, rows - 3, Color(0.75, 0.7, 0.6), cols, rows) # bones
			_f(o, cols / 2, rows / 2 - 2, cols / 2 + 2, rows / 2, Color(0.9, 0.88, 0.8), cols, rows)
		"gargoyle":
			_f(o, 2, rows - 4, cols - 2, rows, Color(0.38, 0.38, 0.42), cols, rows)
			_f(o, cols / 2 - 3, rows / 3, cols / 2 + 3, rows - 4, Color(0.48, 0.48, 0.52), cols, rows)
			_f(o, cols / 2 - 2, rows / 4, cols / 2 + 2, rows / 3, Color(0.52, 0.52, 0.56), cols, rows)
			_f(o, 0, rows / 3, cols / 2 - 3, rows / 3 + 3, Color(0.42, 0.42, 0.46), cols, rows) # wings
			_f(o, cols / 2 + 3, rows / 3, cols, rows / 3 + 3, Color(0.42, 0.42, 0.46), cols, rows)
			_f(o, cols / 2 - 2, rows / 4 + 1, cols / 2 - 1, rows / 4 + 2, Color(0.9, 0.2, 0.2), cols, rows)
			_f(o, cols / 2 + 1, rows / 4 + 1, cols / 2 + 2, rows / 4 + 2, Color(0.9, 0.2, 0.2), cols, rows)
		# ---- surreal --------------------------------------------------------------------------------------------
		"floating_arch":
			var w = maxi(3, cols / 5)
			_f(o, cols / 2 - 3, rows - 2, cols / 2 + 3, rows, Color(0.15, 0.12, 0.2), cols, rows) # its shadow, far below
			_f(o, 1, rows / 4, w, rows * 3 / 4, Color(0.78, 0.7, 0.85), cols, rows)
			_f(o, cols - w, rows / 4, cols - 1, rows * 3 / 4, Color(0.78, 0.7, 0.85), cols, rows)
			for i in range(cols - 2 * w):
				var lift = int(sin(PI * float(i) / float(maxi(1, cols - 2 * w - 1))) * float(rows) / 6.0)
				_f(o, w + i, rows / 4 - lift, w + i + 1, rows / 4 - lift + 3, Color(0.88, 0.8, 0.95), cols, rows)
		"stair_to_nowhere":
			var steps = mini(cols - 2, rows - 2)
			for i in range(steps):
				_f(o, 1 + i, rows - 2 - i, cols - 1, rows - 1 - i, Color(0.7, 0.66, 0.6).darkened(0.03 * float(i % 3)), cols, rows)
			_f(o, 1, rows - 2, cols - 1, rows, Color(0.5, 0.46, 0.42), cols, rows)
			_f(o, cols - 4, 0, cols - 1, 2, Color(0.9, 0.9, 1.0), cols, rows) # a cloud where it ends
		"eye_pillar":
			_f(o, cols / 2 - 4, rows / 3, cols / 2 + 4, rows, Color(0.5, 0.46, 0.52), cols, rows)
			_disc(o, cols / 2, rows / 3, 5, Color(0.95, 0.95, 0.95), cols, rows)
			_disc(o, cols / 2, rows / 3, 3, Color(0.2, 0.5, 0.7), cols, rows)
			_f(o, cols / 2 - 1, rows / 3 - 1, cols / 2 + 1, rows / 3 + 1, Color(0.02, 0.02, 0.05), cols, rows)
			_f(o, cols / 2 - 6, rows / 3 - 7, cols / 2 + 6, rows / 3 - 6, Color(0.2, 0.15, 0.25), cols, rows) # lashes
		"melting_clock":
			_f(o, cols / 2 - 1, rows / 4, cols / 2 + 1, rows, Color(0.4, 0.3, 0.22), cols, rows)
			_disc(o, cols / 2, rows / 3, mini(cols / 2 - 1, rows / 4), Color(0.95, 0.92, 0.8), cols, rows)
			_f(o, cols / 2, rows / 3 - 4, cols / 2 + 1, rows / 3 + 1, Color(0.1, 0.1, 0.12), cols, rows)
			_f(o, cols / 2, rows / 3, cols / 2 + 4, rows / 3 + 1, Color(0.1, 0.1, 0.12), cols, rows)
			for k in range(4): # drips
				var c = cols / 2 - 4 + k * 3
				_f(o, c, rows / 3 + 4, c + 2, rows / 3 + 8 + k * 2, Color(0.95, 0.92, 0.8), cols, rows)
		"lone_door":
			_f(o, cols / 2 - 4, 1, cols / 2 + 4, rows - 1, Color(0.35, 0.2, 0.12), cols, rows)
			_f(o, cols / 2 - 5, 0, cols / 2 + 5, 2, Color(0.5, 0.35, 0.22), cols, rows)
			_f(o, cols / 2 - 3, 3, cols / 2 + 3, rows - 2, Color(0.55, 0.32, 0.18), cols, rows)
			_f(o, cols / 2 + 1, rows / 2, cols / 2 + 2, rows / 2 + 1, GOLD(), cols, rows)
			_f(o, cols / 2 - 3, rows - 2, cols / 2 + 3, rows, Color(0.3, 0.55, 0.9), cols, rows) # the light under it
		"chess_tower":
			for r in range(rows / 4, rows):
				_f(o, cols / 4, r, cols - cols / 4, r + 1, Color(0.92, 0.92, 0.9) if (r / 3) % 2 == 0 else Color(0.12, 0.12, 0.14), cols, rows)
			for c in range(cols / 4, cols - cols / 4, 3):
				_f(o, c, rows / 4 - 2, c + 2, rows / 4, Color(0.92, 0.92, 0.9), cols, rows) # battlements
		"balloon_house":
			_disc(o, cols / 2, rows / 4, mini(cols / 3, rows / 4), Color(0.85, 0.25, 0.3), cols, rows)
			for c in range(cols / 2 - 6, cols / 2 + 6, 4):
				_f(o, c, 1, c + 2, rows / 3, Color(0.95, 0.85, 0.3), cols, rows)
			_f(o, cols / 2 - 3, rows / 2, cols / 2 - 2, rows * 2 / 3, Color(0.4, 0.3, 0.2), cols, rows)
			_f(o, cols / 2 + 2, rows / 2, cols / 2 + 3, rows * 2 / 3, Color(0.4, 0.3, 0.2), cols, rows)
			_f(o, cols / 2 - 6, rows * 2 / 3, cols / 2 + 6, rows - 2, Color(0.85, 0.8, 0.65), cols, rows)
			_f(o, cols / 2 - 7, rows * 2 / 3 - 2, cols / 2 + 7, rows * 2 / 3, Color(0.4, 0.28, 0.25), cols, rows)
			_f(o, cols / 2 - 1, rows - 5, cols / 2 + 1, rows - 2, Color(0.3, 0.2, 0.15), cols, rows)
		"cloud_pedestal":
			for k in range(4):
				_disc(o, cols / 4 + k * cols / 6, rows / 2, rows / 5 + (k % 2), Color(0.96, 0.96, 1.0), cols, rows)
			_f(o, cols / 2 - 3, rows / 2, cols / 2 + 3, rows - 2, Color(0.8, 0.78, 0.85), cols, rows)
			_f(o, cols / 2 - 2, 1, cols / 2 + 2, rows / 3, Color(0.9, 0.8, 0.3), cols, rows) # something golden
	return o

static func GOLD() -> Color:
	return SetPieceArt.GOLD
