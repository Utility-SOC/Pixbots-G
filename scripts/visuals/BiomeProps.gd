extends Node2D

# Ambient ground props that give each biome its own texture of detail: tufts and flowers on grass, bones
# and pebbles on desert, mushrooms and twigs in forest, ice shards on tundra, ash piles and obsidian
# shards on volcano. Purely cosmetic and procedural: one tiny atlas (8 white-on-clear shapes) tinted per
# prop, drawn from ONE canvas item so the canvas batcher merges everything into a handful of draws.
# Placed from the terrain grid after generation; skips tiles with obstacles; capped.

const CELL = 16
const MAX_PROPS = 9000
const KIND_PEBBLE = 0
const KIND_TUFT = 1
const KIND_SHARD = 2
const KIND_BONE = 3
const KIND_ASH = 4
const KIND_MUSHROOM = 5
const KIND_FLOWER = 6
const KIND_TWIG = 7

# MapGenerator.BiomeType int -> [[kind, chance per tile, tint A, tint B], ...] (cumulative chance <= ~0.1)
const TABLE = {
	0: [[KIND_TUFT, 0.05, Color(0.28, 0.6, 0.28), Color(0.2, 0.5, 0.22)], [KIND_FLOWER, 0.012, Color(0.95, 0.85, 0.3), Color(0.9, 0.5, 0.65)], [KIND_PEBBLE, 0.01, Color(0.6, 0.6, 0.58), Color(0.5, 0.5, 0.5)]],
	2: [[KIND_PEBBLE, 0.03, Color(0.78, 0.68, 0.45), Color(0.65, 0.55, 0.38)], [KIND_BONE, 0.004, Color(0.93, 0.9, 0.8), Color(0.85, 0.82, 0.72)], [KIND_TUFT, 0.012, Color(0.7, 0.65, 0.35), Color(0.6, 0.55, 0.3)]],
	3: [[KIND_TUFT, 0.05, Color(0.3, 0.66, 0.22), Color(0.4, 0.72, 0.3)], [KIND_MUSHROOM, 0.012, Color(0.8, 0.3, 0.25), Color(0.85, 0.75, 0.55)], [KIND_TWIG, 0.025, Color(0.4, 0.28, 0.16), Color(0.32, 0.22, 0.13)]],
	4: [[KIND_SHARD, 0.012, Color(0.6, 0.82, 0.95), Color(0.75, 0.9, 1.0)], [KIND_PEBBLE, 0.025, Color(0.88, 0.94, 0.97), Color(0.78, 0.86, 0.92)]],
	5: [[KIND_ASH, 0.045, Color(0.2, 0.17, 0.17), Color(0.28, 0.23, 0.22)], [KIND_SHARD, 0.02, Color(0.1, 0.07, 0.1), Color(0.18, 0.1, 0.12)], [KIND_PEBBLE, 0.015, Color(0.35, 0.18, 0.12), Color(0.45, 0.2, 0.1)]],
}
# Map types that already carry their own scenery and should not get these.
const SKIP_MAP_TYPES = ["Tabletop", "FightShovel", "Dungeon", "Arena"]

var _atlas: Texture2D
var _pos := PackedVector2Array()
var _kind := PackedInt32Array()
var _size := PackedFloat32Array()
var _tint: Array = []

func _ready():
	z_index = -8 # above the baked ground (-100) and decals (-9), below every entity
	_atlas = make_atlas()

# Scatter props over `map` (a MapGenerator) using a seeded generator so a map seed gives the same props.
func build(map, rng_seed: int = 0) -> int:
	if _atlas == null:
		_atlas = make_atlas()
	if map.map_type in SKIP_MAP_TYPES:
		return 0
	var rng = RandomNumberGenerator.new()
	rng.seed = rng_seed if rng_seed != 0 else randi()
	var ts: float = map.tile_size
	for y in range(1, map.height - 1):
		for x in range(1, map.width - 1):
			var rows = TABLE.get(int(map.terrain[y][x]))
			if rows == null or map.obstacles.has(Vector2i(x, y)):
				continue
			var roll = rng.randf()
			for row in rows:
				if roll < float(row[1]):
					_pos.append(Vector2((x + rng.randf_range(0.15, 0.85)) * ts, (y + rng.randf_range(0.15, 0.85)) * ts))
					_kind.append(int(row[0]))
					_size.append(CELL * rng.randf_range(1.3, 2.1))
					_tint.append(Color(row[2]).lerp(Color(row[3]), rng.randf()))
					break
				roll -= float(row[1])
	# Over the cap: thin uniformly at random (never just stop early, which would leave the bottom of the
	# map bare because tiles are scanned row by row).
	while _pos.size() > MAX_PROPS:
		var drop = rng.randi() % _pos.size()
		var last = _pos.size() - 1
		_pos[drop] = _pos[last]; _kind[drop] = _kind[last]; _size[drop] = _size[last]; _tint[drop] = _tint[last]
		_pos.resize(last); _kind.resize(last); _size.resize(last); _tint.resize(last)
	queue_redraw()
	return _pos.size()

func count() -> int:
	return _pos.size()

func _draw() -> void:
	if _atlas == null:
		return
	for i in range(_pos.size()):
		var s = _size[i]
		draw_texture_rect_region(_atlas, Rect2(_pos[i] - Vector2(s, s) * 0.5, Vector2(s, s)), Rect2(_kind[i] * CELL, 0, CELL, CELL), _tint[i])

static func make_atlas() -> Texture2D:
	var img = Image.create(CELL * 8, CELL, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var w = Color(1, 1, 1, 1)
	var shade = Color(0.78, 0.78, 0.78, 1)
	# pebble
	_ellipse(img, 0, 8, 9, 4.5, 3.2, w)
	_ellipse(img, 0, 7, 8, 2.0, 1.2, Color(1, 1, 1, 1).lightened(0.0))
	# tuft: blades fanning up from the base
	for tip in [Vector2(3, 3), Vector2(6, 1), Vector2(8, 0), Vector2(10, 2), Vector2(13, 4)]:
		_line(img, CELL * 1, Vector2(8, 14), tip, w)
	# shard: tall diamond
	for yy in range(0, 15):
		var half = (1.0 - absf(yy - 8.0) / 8.0) * 3.5
		for xx in range(int(8 - half), int(8 + half) + 1):
			img.set_pixel(CELL * 2 + xx, yy, w if xx >= 8 else shade)
	# bone: bar with knobbed ends
	_line(img, CELL * 3, Vector2(3, 8), Vector2(13, 8), w)
	_line(img, CELL * 3, Vector2(3, 9), Vector2(13, 9), w)
	for p in [Vector2(2, 7), Vector2(2, 10), Vector2(13, 7), Vector2(13, 10)]:
		_ellipse(img, CELL * 3, p.x, p.y, 1.5, 1.5, w)
	# ash pile: wide low mound
	_ellipse(img, CELL * 4, 8, 10, 6.5, 2.8, w)
	_ellipse(img, CELL * 4, 8, 8, 3.5, 1.8, shade)
	# mushroom: cap and stem
	for yy in range(4, 9):
		var half = sqrt(maxf(0.0, 1.0 - pow((yy - 8.0) / 4.0, 2.0))) * 5.0
		for xx in range(int(8 - half), int(8 + half) + 1):
			img.set_pixel(CELL * 5 + xx, yy, w)
	for yy in range(8, 13):
		for xx in range(7, 10):
			img.set_pixel(CELL * 5 + xx, yy, shade)
	# flower: centre plus four petals
	for p in [Vector2(8, 5), Vector2(8, 11), Vector2(5, 8), Vector2(11, 8)]:
		_ellipse(img, CELL * 6, p.x, p.y, 2.0, 2.0, w)
	_ellipse(img, CELL * 6, 8, 8, 1.5, 1.5, shade)
	# twig: slanted stick with a fork
	_line(img, CELL * 7, Vector2(3, 12), Vector2(13, 6), w)
	_line(img, CELL * 7, Vector2(3, 13), Vector2(13, 7), w)
	_line(img, CELL * 7, Vector2(8, 9), Vector2(11, 12), w)
	return ImageTexture.create_from_image(img)

static func _ellipse(img: Image, ox: int, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
		for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
			if x < 0 or y < 0 or x >= CELL or y >= CELL:
				continue
			var dx = (x - cx) / rx
			var dy = (y - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(ox + x, y, c)

static func _line(img: Image, ox: int, a: Vector2, b: Vector2, c: Color) -> void:
	var n = int(maxf(absf(b.x - a.x), absf(b.y - a.y))) + 1
	for i in range(n + 1):
		var p = a.lerp(b, float(i) / float(maxi(n, 1)))
		var x = int(round(p.x))
		var y = int(round(p.y))
		if x >= 0 and y >= 0 and x < CELL and y < CELL:
			img.set_pixel(ox + x, y, c)
