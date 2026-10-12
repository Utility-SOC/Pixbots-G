class_name SetPieceArtD
extends RefCounted

# Fourth art file: coast, stadium, swamp, range, cave and Oz pieces that the new map types need. Same contract as
# SetPieceArt: [Rect2, Color] in footprint top-left coordinates, deterministic per seed.

static func styles() -> Array:
	return ["lighthouse", "grandstand", "scoreboard", "floodlight_tower", "beach_hut", "umbrella_cluster", "landing_craft", "stilt_house",
		"emerald_tower", "scarecrow", "hoodoo", "stalagmites", "crystal_cluster", "giant_skeleton", "cooling_tower", "missile_silo",
		"target_dummies", "observation_tower", "colonnade", "triumphal_arch", "gate_arch", "geyser_cone", "hangar_door_bunker"]

static func _f(o: Array, c0: int, r0: int, c1: int, r1: int, col: Color, cols: int, rows: int) -> void:
	SetPieceArt._f(o, c0, r0, c1, r1, col, cols, rows)

static func rects(style: String, footprint: Vector2, seed_v: int) -> Array:
	var cols = int(footprint.x / SetPieceArt.PIX)
	var rows = int(footprint.y / SetPieceArt.PIX)
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_v
	var o: Array = []
	var white = Color(0.94, 0.94, 0.92)
	var red = Color(0.8, 0.18, 0.15)
	var wood = Color(0.45, 0.32, 0.2)
	var steel = Color(0.55, 0.57, 0.62)
	match style:
		"lighthouse":
			for r in range(2, rows):
				var half = 2 + (r * (cols / 4)) / rows
				_f(o, cols / 2 - half, r, cols / 2 + half, r + 1, red if (r / 5) % 2 == 0 else white, cols, rows)
			_f(o, cols / 2 - 3, 0, cols / 2 + 3, 3, Color(0.95, 0.9, 0.5), cols, rows) # lamp
			_f(o, cols / 2 - 4, 3, cols / 2 + 4, 4, Color(0.2, 0.2, 0.25), cols, rows)
			_f(o, cols / 2 - 2, rows - 4, cols / 2 + 2, rows, Color(0.2, 0.15, 0.1), cols, rows)
		"grandstand":
			for r in range(rows):
				var c0 = r * 1
				_f(o, 0, r, cols, r + 1, Color(0.45, 0.45, 0.5) if r % 2 == 0 else Color(0.38, 0.38, 0.44), cols, rows) # tiered concrete
			for r in range(2, rows - 1, 2):
				for c in range(1, cols - 1, 2):
					_f(o, c, r, c + 1, r + 1, [Color(0.8, 0.2, 0.2), Color(0.2, 0.3, 0.7), Color(0.9, 0.8, 0.2)][(c + r) % 3], cols, rows) # seats
			_f(o, 0, 0, cols, 3, Color(0.3, 0.3, 0.34), cols, rows) # roof
			for c in range(0, cols, 8):
				_f(o, c, 0, c + 1, rows, Color(0.25, 0.25, 0.3), cols, rows)
		"scoreboard":
			_f(o, 2, 1, cols - 2, rows * 2 / 3, Color(0.08, 0.1, 0.12), cols, rows)
			for c in range(4, cols - 6, 5):
				_f(o, c, 3, c + 3, 5, Color(0.95, 0.6, 0.15), cols, rows)
				_f(o, c, 7, c + 3, 9, Color(0.95, 0.6, 0.15), cols, rows)
			_f(o, cols / 2 - 1, rows * 2 / 3, cols / 2 + 1, rows, steel, cols, rows)
			_f(o, cols / 2 - 4, rows - 2, cols / 2 + 4, rows, Color(0.35, 0.35, 0.38), cols, rows)
		"floodlight_tower":
			_f(o, cols / 2 - 1, 4, cols / 2 + 1, rows, steel, cols, rows)
			_f(o, cols / 2 - 6, 0, cols / 2 + 6, 5, Color(0.25, 0.25, 0.3), cols, rows)
			for c in range(cols / 2 - 5, cols / 2 + 5, 3):
				_f(o, c, 1, c + 2, 4, Color(1.0, 0.97, 0.75), cols, rows)
			_f(o, cols / 2 - 3, rows - 3, cols / 2 + 3, rows, Color(0.35, 0.35, 0.38), cols, rows)
		"beach_hut":
			_f(o, 1, rows / 3, cols - 1, rows, Color(0.95, 0.9, 0.8), cols, rows)
			for c in range(1, cols - 1, 4):
				_f(o, c, rows / 3, c + 2, rows, Color(0.85, 0.3, 0.3), cols, rows) # stripes
			for r in range(rows / 3):
				_f(o, 1 + (rows / 3 - r), r, cols - 1 - (rows / 3 - r), r + 1, Color(0.3, 0.45, 0.65), cols, rows)
			_f(o, cols / 2 - 2, rows - 5, cols / 2 + 2, rows, Color(0.35, 0.22, 0.15), cols, rows)
		"umbrella_cluster":
			var n = maxi(2, cols / 6)
			for i in range(n):
				var cx = cols * (2 * i + 1) / (2 * n)
				var col = [Color(0.9, 0.25, 0.25), Color(0.25, 0.5, 0.9), Color(0.95, 0.8, 0.2), Color(0.3, 0.7, 0.4)][i % 4]
				for k in range(4):
					_f(o, cx - 4 + k, rows / 2 - 4 + k, cx + 5 - k, rows / 2 - 3 + k, col if k % 2 == 0 else col.lightened(0.3), cols, rows)
				_f(o, cx, rows / 2, cx + 1, rows - 1, wood, cols, rows)
				_f(o, cx - 3, rows - 3, cx + 4, rows - 1, Color(0.85, 0.35, 0.5), cols, rows) # towel
		"landing_craft":
			_f(o, 0, rows / 3, cols, rows - 2, Color(0.35, 0.38, 0.3), cols, rows)
			_f(o, 0, rows / 3 - 2, cols / 3, rows / 3, Color(0.28, 0.3, 0.24), cols, rows) # bridge
			_f(o, cols - 3, rows / 3 + 2, cols, rows - 4, Color(0.28, 0.3, 0.24), cols, rows) # dropped ramp
			_f(o, 0, rows - 3, cols, rows - 2, Color(0.2, 0.22, 0.2), cols, rows)
			for c in range(2, cols - 6, 5):
				_f(o, c, rows / 3 + 2, c + 3, rows - 5, Color(0.22, 0.24, 0.2), cols, rows) # troop well
		"stilt_house":
			for c in [2, cols / 2, cols - 3]:
				_f(o, c, rows / 2, c + 1, rows, wood.darkened(0.2), cols, rows)
			_f(o, 0, rows / 2 - 1, cols, rows / 2 + 1, wood, cols, rows)
			_f(o, 2, rows / 4, cols - 2, rows / 2 - 1, Color(0.5, 0.42, 0.3), cols, rows)
			for r in range(rows / 4):
				_f(o, 1 + (rows / 4 - r), r, cols - 1 - (rows / 4 - r), r + 1, Color(0.4, 0.35, 0.22), cols, rows)
			_f(o, cols / 2 - 1, rows / 4 + 2, cols / 2 + 2, rows / 2 - 1, Color(0.1, 0.12, 0.1), cols, rows)
		"emerald_tower":
			var g = Color(0.15, 0.65, 0.4)
			for t in range(3):
				var inset = t * (cols / 7)
				_f(o, inset, rows * t / 4 + 3, cols - inset, rows, g.lightened(0.1 * t) if t % 2 == 0 else g.darkened(0.1), cols, rows)
			for c in range(2, cols - 2, 3):
				_f(o, c, 6, c + 1, rows - 2, Color(0.7, 0.95, 0.8), cols, rows)
			_f(o, cols / 2 - 1, 0, cols / 2 + 1, 5, Color(0.5, 0.95, 0.65), cols, rows)
			_f(o, cols / 2 - 2, rows - 4, cols / 2 + 2, rows, Color(0.05, 0.25, 0.15), cols, rows)
		"scarecrow":
			_f(o, cols / 2 - 1, 4, cols / 2 + 1, rows, wood, cols, rows)
			_f(o, 1, rows / 3, cols - 1, rows / 3 + 2, wood, cols, rows)
			_f(o, cols / 2 - 3, 0, cols / 2 + 3, 5, Color(0.8, 0.7, 0.3), cols, rows) # straw head
			_f(o, cols / 2 - 3, rows / 3 + 2, cols / 2 + 3, rows / 2 + 3, Color(0.3, 0.4, 0.6), cols, rows)
			_f(o, cols / 2 - 4, 0, cols / 2 + 4, 2, Color(0.25, 0.2, 0.15), cols, rows) # hat
		"hoodoo":
			for i in range(2):
				var c0 = 2 + i * (cols / 2)
				var w = maxi(4, cols / 2 - 4)
				for r in range(rows / 5 * (i + 1) % rows, rows):
					var neck = 2 if r < rows / 2 else 0
					_f(o, c0 + neck, r, c0 + w - neck, r + 1, Color(0.72, 0.45, 0.3).darkened(0.05 * ((r / 4) % 3)), cols, rows)
				_f(o, c0 - 1, rows / 5 * (i + 1) % rows, c0 + w + 1, rows / 5 * (i + 1) % rows + 3, Color(0.62, 0.38, 0.26), cols, rows) # cap rock
		"stalagmites":
			for i in range(maxi(3, cols / 4)):
				var c = 1 + rng.randi() % maxi(1, cols - 4)
				var h = rows / 3 + rng.randi() % maxi(1, rows * 2 / 3)
				for r in range(h):
					var half = (h - r) / 4
					_f(o, c - half, rows - 1 - r, c + half + 1, rows - r, Color(0.4, 0.38, 0.42).lightened(0.04 * float(r % 3)), cols, rows)
		"crystal_cluster":
			for i in range(maxi(3, cols / 3)):
				var c = 1 + rng.randi() % maxi(1, cols - 3)
				var h = rows / 2 + rng.randi() % maxi(1, rows / 2)
				var col = [Color(0.5, 0.35, 0.95), Color(0.3, 0.8, 0.95), Color(0.9, 0.4, 0.8)][i % 3]
				for r in range(h):
					var half = 1 if r < h - 2 else 0
					_f(o, c - half, rows - 1 - r, c + half + 1, rows - r, col.lightened(0.05 * float(r % 4)), cols, rows)
		"giant_skeleton":
			var bone = Color(0.88, 0.85, 0.75)
			_f(o, 0, rows / 2, cols - 4, rows / 2 + 2, bone, cols, rows) # spine
			for c in range(4, cols - 8, 4):
				for k in range(rows / 3):
					_f(o, c + k / 3, rows / 2 + 2 + k, c + k / 3 + 1, rows / 2 + 3 + k, bone.darkened(0.1), cols, rows) # ribs
					_f(o, c - k / 3, rows / 2 - 1 - k, c - k / 3 + 1, rows / 2 - k, bone.darkened(0.1), cols, rows)
			_f(o, cols - 6, rows / 3, cols, rows * 2 / 3, bone, cols, rows) # skull
			_f(o, cols - 4, rows / 2 - 2, cols - 2, rows / 2 + 1, Color(0.1, 0.08, 0.08), cols, rows)
		"cooling_tower":
			for r in range(rows):
				var t = float(r) / float(rows)
				var half = int(cols / 2.0 * (0.62 + 0.38 * absf(t - 0.55) * 2.0 * 0.9))
				_f(o, cols / 2 - half, r, cols / 2 + half, r + 1, Color(0.6, 0.6, 0.62).darkened(0.04 * float(r % 3)), cols, rows)
			_f(o, cols / 2 - 3, 0, cols / 2 + 3, 3, Color(0.85, 0.87, 0.9), cols, rows) # steam
			_f(o, cols / 2 - 2, rows - 3, cols / 2 + 2, rows, Color(0.15, 0.15, 0.18), cols, rows)
		"missile_silo":
			_f(o, 0, rows / 2, cols, rows, Color(0.4, 0.42, 0.38), cols, rows)
			_f(o, 1, rows / 2 + 1, cols - 1, rows - 1, Color(0.3, 0.32, 0.3), cols, rows)
			_f(o, cols / 4, rows / 2 + 2, cols - cols / 4, rows - 2, Color(0.08, 0.08, 0.1), cols, rows) # open hatch
			_f(o, cols / 2 - 2, 1, cols / 2 + 2, rows / 2 + 2, Color(0.82, 0.82, 0.85), cols, rows) # missile
			_f(o, cols / 2 - 2, 1, cols / 2 + 2, 4, red, cols, rows)
			_f(o, cols / 2 - 4, rows / 2 - 4, cols / 2 + 4, rows / 2 - 2, Color(0.35, 0.35, 0.4), cols, rows) # fins
			for c in range(0, cols, 4):
				_f(o, c, rows / 2, c + 2, rows / 2 + 1, Color(0.9, 0.8, 0.2), cols, rows) # hazard stripes
		"target_dummies":
			for c in range(2, cols - 4, maxi(5, cols / 4)):
				_f(o, c + 1, 0, c + 3, rows / 2, wood, cols, rows)
				_f(o, c, rows / 4, c + 4, rows * 3 / 4, Color(0.9, 0.9, 0.85), cols, rows)
				_f(o, c + 1, rows / 4 + 1, c + 3, rows * 3 / 4 - 1, red, cols, rows) # bullseye
				_f(o, c + 1, rows - 3, c + 3, rows, wood.darkened(0.2), cols, rows)
		"observation_tower":
			for c in [2, cols - 3]:
				_f(o, c, rows / 3, c + 1, rows, wood, cols, rows)
			_f(o, 2, rows / 2, cols - 2, rows / 2 + 1, wood.darkened(0.2), cols, rows)
			_f(o, 0, 2, cols, rows / 3, Color(0.5, 0.45, 0.35), cols, rows)
			_f(o, 1, 4, cols - 1, rows / 3 - 2, Color(0.12, 0.14, 0.12), cols, rows) # slit windows
			_f(o, 0, 0, cols, 2, Color(0.35, 0.33, 0.28), cols, rows)
		"colonnade":
			var sand = Color(0.82, 0.76, 0.62)
			_f(o, 0, 0, cols, 3, sand, cols, rows)
			for c in range(1, cols - 2, 4):
				_f(o, c, 3, c + 2, rows - 2, sand.lightened(0.08), cols, rows)
				_f(o, c, 3, c + 1, rows - 2, sand.darkened(0.15), cols, rows)
			_f(o, 0, rows - 2, cols, rows, sand.darkened(0.2), cols, rows)
		"triumphal_arch":
			var sand = Color(0.84, 0.78, 0.64)
			_f(o, 0, rows / 5, cols, rows, sand, cols, rows)
			_f(o, 0, rows / 5 - 2, cols, rows / 5, sand.lightened(0.12), cols, rows)
			_f(o, cols / 2 - 1, 0, cols / 2 + 1, rows / 5 - 2, Color(0.85, 0.7, 0.25), cols, rows)
			_f(o, cols / 4, rows * 2 / 5, cols - cols / 4, rows, Color(0.08, 0.08, 0.1), cols, rows)
			for r in range(rows * 2 / 5 - 3, rows * 2 / 5):
				_f(o, cols / 4 + (rows * 2 / 5 - r), r, cols - cols / 4 - (rows * 2 / 5 - r), r + 1, Color(0.08, 0.08, 0.1), cols, rows)
		"gate_arch":
			var stone = Color(0.5, 0.48, 0.5)
			_f(o, 0, rows / 4, cols / 4, rows, stone, cols, rows)
			_f(o, cols - cols / 4, rows / 4, cols, rows, stone, cols, rows)
			_f(o, 0, rows / 4 - 3, cols, rows / 4 + 2, stone.lightened(0.1), cols, rows)
			for c in range(0, cols, 2):
				_f(o, c, rows / 4 - 5, c + 1, rows / 4 - 3, stone.lightened(0.15), cols, rows)
			_f(o, cols / 2 - 1, 0, cols / 2 + 1, rows / 4 - 4, Color(0.7, 0.2, 0.2), cols, rows) # banner
		"geyser_cone":
			var crust = Color(0.78, 0.72, 0.6)
			for r in range(rows / 2, rows):
				var half = (r - rows / 2) * (cols / 2) / (rows - rows / 2)
				_f(o, cols / 2 - half - 1, r, cols / 2 + half + 2, r + 1, crust.darkened(0.06 * float(r % 3)), cols, rows)
			_f(o, cols / 2 - 2, rows / 2 - 1, cols / 2 + 2, rows / 2 + 2, Color(0.25, 0.25, 0.28), cols, rows)
			_f(o, cols / 2 - 1, 0, cols / 2 + 1, rows / 2 - 1, Color(0.9, 0.93, 0.97), cols, rows) # steam plume
			_f(o, cols / 2 - 3, 2, cols / 2 + 3, 5, Color(0.92, 0.95, 1.0), cols, rows)
		"hangar_door_bunker":
			var c = Color(0.46, 0.46, 0.42)
			_f(o, 0, rows / 4, cols, rows, c, cols, rows)
			_f(o, 0, rows / 4 - 2, cols, rows / 4, c.lightened(0.12), cols, rows)
			_f(o, cols / 4, rows / 2, cols - cols / 4, rows, Color(0.12, 0.13, 0.12), cols, rows)
			for k in range(0, cols / 2, 3):
				_f(o, cols / 4 + k, rows / 2, cols / 4 + k + 1, rows, Color(0.22, 0.24, 0.22), cols, rows)
			_f(o, 2, rows - 3, cols - 2, rows, Color(0.55, 0.5, 0.35), cols, rows)
	return o
