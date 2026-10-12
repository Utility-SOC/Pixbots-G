class_name SetPieceArt
extends RefCounted

# Procedural pixel art for the set-piece library (SetPieces). Every style returns a list of [Rect2, Color] in the
# footprint's top-left coordinates, built from PIX-sized cells, deterministic for a given seed. Returning rects (not
# drawing directly) keeps the art testable headless; RuinObstacle just paints them.

const PIX = 4.0

const STONE = Color(0.58, 0.58, 0.63)
const STONE_D = Color(0.42, 0.42, 0.48)
const STONE_L = Color(0.72, 0.72, 0.76)
const SLATE = Color(0.26, 0.28, 0.34)
const SHADOW = Color(0.14, 0.14, 0.18)
const GLASS = Color(0.35, 0.5, 0.62)
const GOLD = Color(0.85, 0.68, 0.25)
const DECO = Color(0.2, 0.3, 0.36)
const DECO_L = Color(0.34, 0.46, 0.52)
const CONCRETE = Color(0.5, 0.5, 0.46)
const CONCRETE_D = Color(0.36, 0.36, 0.33)
const OLIVE = Color(0.32, 0.38, 0.24)
const OLIVE_D = Color(0.22, 0.27, 0.17)
const TIN = Color(0.62, 0.64, 0.66)
const RUST = Color(0.55, 0.28, 0.16)
const STRAW = Color(0.82, 0.68, 0.3)
const STRAW_D = Color(0.66, 0.52, 0.2)
const BRICK = Color(0.55, 0.3, 0.24)
const WOOD = Color(0.45, 0.32, 0.2)

static func styles() -> Array:
	return ["gothic_chapel", "gothic_spire", "gothic_cathedral", "deco_tower", "deco_hall", "silo", "granary", "haystack",
		"bunker", "watchtower", "hangar", "barracks", "smokestack_works", "fuel_tanks", "container_stack"]

static func has_style(style: String) -> bool:
	return style in styles() or style in SetPieceArtB.styles()

static func all_styles() -> Array:
	return styles() + SetPieceArtB.styles()

static func _f(out: Array, c0: int, r0: int, c1: int, r1: int, col: Color, cols: int, rows: int) -> void:
	c0 = clampi(c0, 0, cols)
	c1 = clampi(c1, 0, cols)
	r0 = clampi(r0, 0, rows)
	r1 = clampi(r1, 0, rows)
	if c1 <= c0 or r1 <= r0:
		return
	out.append([Rect2(c0 * PIX, r0 * PIX, (c1 - c0) * PIX, (r1 - r0) * PIX), col])

# A pointed-arch window of width 2: slit with a one-cell cap.
static func _arch(out: Array, c: int, r: int, h: int, col: Color, cols: int, rows: int) -> void:
	_f(out, c, r + 1, c + 2, r + h, col, cols, rows)
	_f(out, c, r, c + 2, r + 1, col, cols, rows)

static func rects(style: String, footprint: Vector2, seed_v: int) -> Array:
	if style in SetPieceArtB.styles():
		return SetPieceArtB.rects(style, footprint, seed_v)
	var cols = int(footprint.x / PIX)
	var rows = int(footprint.y / PIX)
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_v
	var out: Array = []
	match style:
		"gothic_chapel": _chapel(out, cols, rows, rng)
		"gothic_spire": _spire(out, cols, rows, rng)
		"gothic_cathedral": _cathedral(out, cols, rows, rng)
		"deco_tower": _deco_tower(out, cols, rows, rng)
		"deco_hall": _deco_hall(out, cols, rows, rng)
		"silo": _silo(out, cols, rows, rng)
		"granary": _granary(out, cols, rows, rng)
		"haystack": _haystack(out, cols, rows, rng)
		"bunker": _bunker(out, cols, rows, rng)
		"watchtower": _watchtower(out, cols, rows, rng)
		"hangar": _hangar(out, cols, rows, rng)
		"barracks": _barracks(out, cols, rows, rng)
		"smokestack_works": _works(out, cols, rows, rng)
		"fuel_tanks": _tanks(out, cols, rows, rng)
		"container_stack": _containers(out, cols, rows, rng)
	return out

static func _chapel(o: Array, cols: int, rows: int, rng: RandomNumberGenerator) -> void:
	var roof_rows = maxi(2, rows / 3)
	_f(o, 0, roof_rows, cols, rows, STONE, cols, rows)
	for c in range(0, cols, 4):
		_f(o, c, roof_rows, c + 1, rows, STONE_D, cols, rows) # buttresses
	for r in range(roof_rows):
		var inset = r / 2 if r < roof_rows else 0
		_f(o, roof_rows - r - 1 + 0, r, cols - (roof_rows - r - 1), r + 1, SLATE if r % 2 == 0 else SLATE.lightened(0.08), cols, rows)
	for c in range(2, cols - 3, 5):
		_arch(o, c, roof_rows + 1, maxi(3, rows - roof_rows - 3), SHADOW, cols, rows)
	_f(o, cols / 2 - 1, rows - 3, cols / 2 + 1, rows, SHADOW, cols, rows) # door

static func _spire(o: Array, cols: int, rows: int, rng: RandomNumberGenerator) -> void:
	var body_c0 = cols / 4
	var body_c1 = cols - cols / 4
	var spire_rows = rows / 2
	_f(o, body_c0, spire_rows, body_c1, rows, STONE, cols, rows)
	_f(o, body_c0, spire_rows, body_c0 + 1, rows, STONE_D, cols, rows)
	for r in range(spire_rows):
		var half = int((1.0 - float(r) / float(spire_rows)) * float(body_c1 - body_c0) / 2.0)
		_f(o, cols / 2 - half - 1, spire_rows - r - 1, cols / 2 + half + 1, spire_rows - r, SLATE, cols, rows)
	_f(o, cols / 2, 0, cols / 2 + 1, 2, GOLD, cols, rows)
	_arch(o, cols / 2 - 1, spire_rows + 2, maxi(3, rows - spire_rows - 5), SHADOW, cols, rows)

static func _cathedral(o: Array, cols: int, rows: int, rng: RandomNumberGenerator) -> void:
	var tw = maxi(4, cols / 6)
	var nave_top = rows / 3
	_f(o, tw, nave_top, cols - tw, rows, STONE, cols, rows)
	for r in range(nave_top):
		_f(o, tw + r, nave_top - r - 1, cols - tw - r, nave_top - r, SLATE, cols, rows)
	for side in [0, cols - tw]:
		_f(o, side, 4, side + tw, rows, STONE_D, cols, rows)
		for r in range(4):
			_f(o, side + (3 - r), r, side + tw - (3 - r), r + 1, SLATE, cols, rows) # spire roof
		_f(o, side + tw / 2 - 1, 0, side + tw / 2 + 1, 1, GOLD, cols, rows)
		_arch(o, side + tw / 2 - 1, rows / 3, maxi(3, rows / 3), SHADOW, cols, rows)
	_f(o, cols / 2 - 3, nave_top + 2, cols / 2 + 3, nave_top + 6, STONE_L, cols, rows) # rose window
	_f(o, cols / 2 - 2, nave_top + 3, cols / 2 + 2, nave_top + 5, GLASS, cols, rows)
	for c in range(tw + 3, cols - tw - 3, 6):
		_arch(o, c, nave_top + 3, maxi(3, rows - nave_top - 6), SHADOW, cols, rows)
	_f(o, cols / 2 - 2, rows - 4, cols / 2 + 2, rows, SHADOW, cols, rows)

static func _deco_tower(o: Array, cols: int, rows: int, rng: RandomNumberGenerator) -> void:
	var tiers = 3
	for t in range(tiers):
		var inset = t * maxi(1, cols / 8)
		var r0 = rows * t / (tiers + 1) + 2
		var r1 = rows if t == 0 else rows * (tiers - t + 1) / (tiers + 1) + (rows - rows * (tiers - t + 1) / (tiers + 1)) / 1
		_f(o, inset, r0, cols - inset, rows, DECO if t % 2 == 0 else DECO_L, cols, rows)
	for c in range(2, cols - 2, 3):
		_f(o, c, 4, c + 1, rows, GOLD.darkened(0.3), cols, rows) # vertical fins
	_f(o, cols / 2 - 1, 0, cols / 2 + 1, 4, GOLD, cols, rows)
	_f(o, cols / 2 - 1, rows - 3, cols / 2 + 1, rows, SHADOW, cols, rows)

static func _deco_hall(o: Array, cols: int, rows: int, rng: RandomNumberGenerator) -> void:
	_f(o, 0, rows / 3, cols, rows, DECO, cols, rows) # wings
	var mid0 = cols / 3
	var mid1 = cols - cols / 3
	_f(o, mid0, 2, mid1, rows, DECO_L, cols, rows) # tall centre
	_f(o, mid0 - 1, 1, mid1 + 1, 2, GOLD, cols, rows)
	for i in range(1, 6): # sunburst over the door
		_f(o, cols / 2 - i, rows / 2 - i / 2, cols / 2 + i, rows / 2 - i / 2 + 1, GOLD.darkened(0.15 * (i % 2)), cols, rows)
	_f(o, cols / 2 - 2, rows - 5, cols / 2 + 2, rows, SHADOW, cols, rows)
	for c in range(2, mid0 - 1, 3):
		_f(o, c, rows / 3 + 2, c + 1, rows - 2, GLASS, cols, rows)
	for c in range(mid1 + 2, cols - 2, 3):
		_f(o, c, rows / 3 + 2, c + 1, rows - 2, GLASS, cols, rows)
	_f(o, 0, rows / 3, cols, rows / 3 + 1, GOLD, cols, rows)

static func _silo(o: Array, cols: int, rows: int, rng: RandomNumberGenerator) -> void:
	var w = maxi(4, cols * 2 / 5)
	for i in range(2):
		var c0 = 1 + i * (cols - w - 2)
		_f(o, c0, rows / 4, c0 + w, rows, TIN if i == 0 else TIN.darkened(0.1), cols, rows)
		for r in range(rows / 4, rows, 3):
			_f(o, c0, r, c0 + w, r + 1, TIN.darkened(0.25), cols, rows)
		_f(o, c0 + 1, rows / 4 - 2, c0 + w - 1, rows / 4, RUST, cols, rows) # dome cap
		_f(o, c0 + w / 2 - 1, 0, c0 + w / 2 + 1, rows / 4 - 2, RUST.darkened(0.2), cols, rows)
	_f(o, 1 + w, rows / 2, cols - w - 1, rows / 2 + 2, CONCRETE_D, cols, rows) # connecting pipe

static func _granary(o: Array, cols: int, rows: int, rng: RandomNumberGenerator) -> void:
	var roof = maxi(2, rows / 3)
	_f(o, 0, roof, cols, rows, WOOD, cols, rows)
	for c in range(0, cols, 3):
		_f(o, c, roof, c + 1, rows, WOOD.darkened(0.2), cols, rows)
	for r in range(roof):
		_f(o, roof - 1 - r, r, cols - (roof - 1 - r), r + 1, STRAW if r % 2 == 0 else STRAW_D, cols, rows)
	_f(o, cols / 2 - 2, rows - 5, cols / 2 + 2, rows, SHADOW, cols, rows)
	_f(o, cols / 2 - 1, roof - 1, cols / 2 + 1, roof + 2, SHADOW, cols, rows) # loft hatch

static func _haystack(o: Array, cols: int, rows: int, rng: RandomNumberGenerator) -> void:
	for r in range(rows / 2, rows):
		var inset = (rows - r) / 2
		_f(o, inset, r, cols - inset, r + 1, STRAW if r % 2 == 0 else STRAW_D, cols, rows)
	for r in range(rows / 3, rows / 2):
		var inset = cols / 4 + (rows / 2 - r)
		_f(o, inset, r, cols - inset, r + 1, STRAW_D, cols, rows)

static func _bunker(o: Array, cols: int, rows: int, rng: RandomNumberGenerator) -> void:
	_f(o, 0, rows / 3, cols, rows, CONCRETE, cols, rows)
	_f(o, 0, rows / 3, cols, rows / 3 + 1, CONCRETE.lightened(0.15), cols, rows)
	_f(o, 0, rows - 2, cols, rows, CONCRETE_D, cols, rows)
	for c in range(2, cols - 4, 5):
		_f(o, c, rows / 2, c + 4, rows / 2 + 2, SHADOW, cols, rows) # firing slits
	for c in range(0, cols, 2):
		_f(o, c, rows / 3 - 2, c + 2, rows / 3, Color(0.6, 0.52, 0.34) if c % 4 == 0 else Color(0.5, 0.43, 0.28), cols, rows) # sandbags
	_f(o, cols - 4, 0, cols - 3, rows / 3, WOOD, cols, rows)
	_f(o, cols - 3, 0, cols - 1, 3, OLIVE, cols, rows) # flag

static func _watchtower(o: Array, cols: int, rows: int, rng: RandomNumberGenerator) -> void:
	var cab_rows = rows / 3
	for c in [1, cols - 2]:
		_f(o, c, cab_rows, c + 1, rows, WOOD, cols, rows) # legs
	for r in range(cab_rows + 2, rows - 2, 4):
		_f(o, 1, r, cols - 1, r + 1, WOOD.darkened(0.15), cols, rows) # cross braces
	_f(o, 0, cab_rows - 4, cols, cab_rows, OLIVE, cols, rows)
	_f(o, 1, cab_rows - 3, cols - 1, cab_rows - 1, SHADOW, cols, rows) # window
	_f(o, 0, cab_rows - 6, cols, cab_rows - 4, OLIVE_D, cols, rows) # roof
	_f(o, cols - 2, cab_rows - 8, cols - 1, cab_rows - 6, GOLD, cols, rows) # searchlight

static func _hangar(o: Array, cols: int, rows: int, rng: RandomNumberGenerator) -> void:
	var arch_rows = rows / 2
	for r in range(arch_rows):
		var inset = int(float(arch_rows - r) * float(arch_rows - r) / float(arch_rows) / 2.0)
		_f(o, inset, r, cols - inset, r + 1, TIN if r % 2 == 0 else TIN.darkened(0.1), cols, rows)
	_f(o, 0, arch_rows, cols, rows, TIN.darkened(0.15), cols, rows)
	for c in range(0, cols, 4):
		_f(o, c, 2, c + 1, rows, TIN.darkened(0.3), cols, rows) # ribs
	_f(o, cols / 4, rows / 3, cols - cols / 4, rows, SHADOW, cols, rows) # open doors
	_f(o, cols / 2, rows / 3, cols / 2 + 1, rows, CONCRETE_D, cols, rows)

static func _barracks(o: Array, cols: int, rows: int, rng: RandomNumberGenerator) -> void:
	var roof = maxi(2, rows / 3)
	_f(o, 0, roof, cols, rows, OLIVE, cols, rows)
	for c in range(0, cols, 2):
		_f(o, c, 0, c + 1, roof, OLIVE_D if c % 4 == 0 else OLIVE.darkened(0.12), cols, rows) # corrugated roof
	for c in range(2, cols - 2, 4):
		_f(o, c, roof + 2, c + 2, roof + 4, GLASS.darkened(0.2), cols, rows)
	_f(o, 0, rows - 2, cols, rows, CONCRETE_D, cols, rows)
	_f(o, cols - 4, roof + 1, cols - 2, rows - 1, SHADOW, cols, rows)

static func _works(o: Array, cols: int, rows: int, rng: RandomNumberGenerator) -> void:
	_f(o, 0, rows / 2, cols * 2 / 3, rows, BRICK, cols, rows)
	for r in range(rows / 2, rows, 2):
		_f(o, 0, r, cols * 2 / 3, r + 1, BRICK.darkened(0.2), cols, rows)
	for c in range(2, cols * 2 / 3 - 3, 4):
		_f(o, c, rows / 2 + 2, c + 2, rows / 2 + 4, GLASS.darkened(0.3), cols, rows)
	var sc = cols - cols / 4 - 1
	_f(o, sc, 2, sc + cols / 4, rows, BRICK.lightened(0.05), cols, rows)
	for r in range(3, rows - 1, 4):
		_f(o, sc, r, sc + cols / 4, r + 1, STONE_L, cols, rows) # bands
	_f(o, sc - 1, 0, sc + cols / 4 + 1, 2, SHADOW, cols, rows) # smoke

static func _tanks(o: Array, cols: int, rows: int, rng: RandomNumberGenerator) -> void:
	var n = 2 if cols < 14 else 3
	var w = (cols - 2) / n
	for i in range(n):
		var c0 = 1 + i * w
		_f(o, c0, rows / 3, c0 + w - 1, rows, TIN.darkened(0.05 * i), cols, rows)
		_f(o, c0 + 1, rows / 3 - 1, c0 + w - 2, rows / 3, TIN.lightened(0.1), cols, rows)
		for r in range(rows / 3 + 2, rows, 4):
			_f(o, c0, r, c0 + w - 1, r + 1, RUST, cols, rows)
	_f(o, 0, rows / 3 - 3, cols, rows / 3 - 2, CONCRETE_D, cols, rows) # catwalk

static func _containers(o: Array, cols: int, rows: int, rng: RandomNumberGenerator) -> void:
	var palette = [Color(0.6, 0.2, 0.18), Color(0.2, 0.36, 0.55), Color(0.78, 0.55, 0.2), Color(0.25, 0.45, 0.3)]
	var cw = maxi(4, cols / 3)
	var ch = maxi(3, rows / 2)
	var y = rows - ch
	var c = 0
	while c < cols:
		var col: Color = palette[rng.randi() % palette.size()]
		_f(o, c, y, mini(cols, c + cw - 1), rows, col, cols, rows)
		for k in range(c + 1, mini(cols, c + cw - 1), 2):
			_f(o, k, y, k + 1, rows, col.darkened(0.2), cols, rows)
		if rng.randf() < 0.6 and y - ch >= 0:
			var col2: Color = palette[rng.randi() % palette.size()]
			_f(o, c, y - ch, mini(cols, c + cw - 1), y, col2, cols, rows)
		c += cw
