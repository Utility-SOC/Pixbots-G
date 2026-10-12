class_name ShopBackdrop
extends RefCounted

# The game shop as three pixel-art backdrops (384x216, drawn once, nearest-filtered): the front counter near the register (slatwall of boxed
# games, glass cases, fluorescent light), the view over the tables (terrain on the felt, miniatures in lit cabinets), and the back
# wall of the card-table area (binders, boxes, a screen, a window; the tables themselves out of frame). Used behind shop cutscenes
# ({"scene": "shop"} = register, "shop_tables", "shop_back") and as the framing behind shop menus (ShopBackdrop.frame).

const W = 384
const H = 216
const KINDS = ["register", "tables", "back"]

const BOX_COLORS = [Color(0.78, 0.2, 0.22), Color(0.2, 0.4, 0.8), Color(0.2, 0.62, 0.3), Color(0.9, 0.72, 0.18), Color(0.55, 0.3, 0.75), Color(0.9, 0.5, 0.15), Color(0.2, 0.7, 0.75), Color(0.85, 0.85, 0.88), Color(0.15, 0.15, 0.2)]
const GLYPHS = {
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"], "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
	"C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"], "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
	"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"], "G": ["01111", "10000", "10000", "10011", "10001", "10001", "01111"],
	"I": ["111", "010", "010", "010", "010", "010", "111"], "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"], "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
	"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"], "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"], "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
	"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"], "W": ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
	"X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"], " ": ["00", "00", "00", "00", "00", "00", "00"],
}

static func make(kind: String) -> ImageTexture:
	var img = Image.create(W, H, false, Image.FORMAT_RGBA8)
	var rng = RandomNumberGenerator.new()
	rng.seed = 2026 + KINDS.find(kind)
	match kind:
		"tables": _tables(img, rng)
		"back": _back(img, rng)
		_: _register(img, rng)
	return ImageTexture.create_from_image(img)

# A TextureRect-based full-screen frame for a menu: the backdrop dimmed behind the content. Returns the node (add it first).
static func frame(kind: String, dim: float = 0.55) -> Control:
	var root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tr = TextureRect.new()
	tr.texture = make(kind)
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tr)
	var shade = ColorRect.new()
	shade.color = Color(0.03, 0.03, 0.06, dim)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	return root

# ---- helpers ----------------------------------------------------------------------------------------------------------------------
static func _r(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	img.fill_rect(Rect2i(x, y, w, h), c)

static func _text(img: Image, s: String, x: int, y: int, c: Color, scale: int = 1) -> int:
	var cx = x
	for ch in s:
		var g: Array = GLYPHS.get(ch, GLYPHS[" "])
		for r in range(g.size()):
			for k in range(g[r].length()):
				if g[r][k] == "1":
					img.fill_rect(Rect2i(cx + k * scale, y + r * scale, scale, scale), c)
		cx += (g[0].length() + 1) * scale
	return cx - x

static func _neon(img: Image, s: String, x: int, y: int, c: Color, scale: int = 1) -> void:
	var w = (s.length() * 6) * scale
	_r(img, x - 3, y - 3, w + 5, 7 * scale + 6, Color(0.03, 0.03, 0.05)) # backing board
	_r(img, x - 3, y - 3, w + 5, 1, c.darkened(0.5))
	_text(img, s, x + 1, y + 1, c.darkened(0.55), scale) # glow
	_text(img, s, x, y, c, scale)

static func _boxes(img: Image, x: int, y: int, w: int, h: int, rng: RandomNumberGenerator, palette: Array = BOX_COLORS) -> void:
	var cx = x
	while cx < x + w - 3:
		var bw = rng.randi_range(4, 8)
		bw = mini(bw, x + w - cx)
		var c: Color = palette[rng.randi() % palette.size()]
		var bh = h - rng.randi_range(0, 3)
		_r(img, cx, y + h - bh, bw - 1, bh, c)
		_r(img, cx, y + h - bh, bw - 1, 2, c.lightened(0.35)) # the box's top edge
		_r(img, cx + 1, y + h - bh + 4, bw - 3, 3, c.darkened(0.3)) # a title band
		cx += bw
	_r(img, x, y + h, w, 2, Color(0.35, 0.22, 0.12)) # the shelf lip
	_r(img, x, y + h + 2, w, 1, Color(0.15, 0.1, 0.07))

static func _slatwall(img: Image, x: int, y: int, w: int, h: int) -> void:
	_r(img, x, y, w, h, Color(0.7, 0.5, 0.3))
	var yy = y
	while yy < y + h:
		_r(img, x, yy, w, 1, Color(0.4, 0.27, 0.15)) # the groove
		_r(img, x, yy + 1, w, 1, Color(0.8, 0.6, 0.38))
		yy += 6

static func _ceiling(img: Image, h: int, tint: Color) -> void:
	_r(img, 0, 0, W, h, tint)
	for x in range(0, W, 64):
		_r(img, x, 0, 1, h, tint.darkened(0.25))
	for y in range(0, h, 11):
		_r(img, 0, y, W, 1, tint.darkened(0.25))
	for x in range(26, W - 40, 110): # fluorescent panels
		_r(img, x, 3, 50, 7, Color(0.95, 0.97, 1.0))
		_r(img, x - 1, 2, 52, 1, Color(0.7, 0.72, 0.78))

static func _wood_floor(img: Image, y: int, base: Color) -> void:
	_r(img, 0, y, W, H - y, base)
	var yy = y
	var step = 5
	while yy < H:
		_r(img, 0, yy, W, 1, base.darkened(0.18))
		var off = (yy * 13) % 47
		var x = off
		while x < W:
			_r(img, x, yy, 1, step, base.darkened(0.14))
			x += 47
		yy += step
		step += 1
	for x in range(0, W, 3): # a soft sheen under the lights
		img.set_pixel(x, y + 3, base.lightened(0.2))

static func _glass_case(img: Image, x: int, y: int, w: int, h: int, rng: RandomNumberGenerator) -> void:
	_r(img, x, y, w, h, Color(0.08, 0.1, 0.14))
	_r(img, x + 2, y + 2, w - 4, h - 8, Color(0.55, 0.75, 0.85))
	for shelf in range(2):
		var sy = y + 4 + shelf * ((h - 14) / 2)
		_boxes(img, x + 3, sy, w - 6, (h - 14) / 2 - 4, rng)
	_r(img, x + 2, y + 2, w - 4, 1, Color(0.9, 0.97, 1.0)) # glass glint
	_r(img, x + 4, y + 3, 2, h - 10, Color(0.8, 0.92, 1.0, 1.0))
	_r(img, x, y + h - 6, w, 6, Color(0.15, 0.17, 0.22))

static func _miniatures(img: Image, x: int, y: int, w: int, rng: RandomNumberGenerator) -> void:
	var cx = x
	while cx < x + w - 3:
		var c: Color = BOX_COLORS[rng.randi() % 7]
		var hh = rng.randi_range(5, 10)
		_r(img, cx + 1, y - hh, 3, hh, c) # a painted figure
		_r(img, cx, y - hh + 1, 5, 2, c.lightened(0.3))
		_r(img, cx + 1, y - hh - 2, 3, 2, Color(0.9, 0.78, 0.65))
		cx += rng.randi_range(5, 8)

# ---- 1. the register -------------------------------------------------------------------------------------------------------------------
static func _register(img: Image, rng: RandomNumberGenerator) -> void:
	_r(img, 0, 0, W, H, Color(0.14, 0.3, 0.55)) # the blue band wall
	_ceiling(img, 22, Color(0.72, 0.74, 0.78))
	_slatwall(img, 0, 24, W, 98)
	for row in range(3): # shelves of boxed games
		for seg in range(0, W, 130):
			_boxes(img, seg + 2, 34 + row * 29, 124, 22, rng)
	_r(img, 0, 24, W, 5, Color(0.1, 0.1, 0.14)) # the top shelf: consoles
	for cx in range(8, W - 20, 24):
		var c = [Color(0.85, 0.85, 0.88), Color(0.2, 0.2, 0.25), Color(0.7, 0.1, 0.12)][rng.randi() % 3]
		_r(img, cx, 25, 18, 4, c)
	_neon(img, "NEW RELEASES", 14, 8, Color(0.4, 0.9, 1.0), 1)
	_neon(img, "OPEN", 330, 8, Color(1.0, 0.3, 0.3), 1)
	_wood_floor(img, 150, Color(0.72, 0.52, 0.32))
	_r(img, 0, 122, W, 28, Color(0.1, 0.12, 0.16)) # the dark base of the wall
	_glass_case(img, 4, 124, 104, 56, rng) # glass counters either side, centre left clear for the register
	_glass_case(img, 276, 124, 104, 56, rng)
	_r(img, 108, 124, 168, 3, Color(0.2, 0.22, 0.28)) # back-bar rail behind the counter
	for px in [150, 190, 230]: # posters
		_r(img, px, 126, 22, 24, BOX_COLORS[(px / 7) % 7].darkened(0.2))
		_r(img, px + 2, 128, 18, 14, BOX_COLORS[(px / 5) % 7])
	_r(img, 0, 178, W, 1, Color(0.2, 0.14, 0.08))

# ---- 2. over the tables ----------------------------------------------------------------------------------------------------------------
static func _tables(img: Image, rng: RandomNumberGenerator) -> void:
	_r(img, 0, 0, W, H, Color(0.16, 0.14, 0.18)) # dim wall
	_ceiling(img, 14, Color(0.28, 0.28, 0.34))
	for x in [60, 190, 320]: # hanging lamps over the tables
		_r(img, x, 14, 1, 14, Color(0.1, 0.1, 0.12))
		_r(img, x - 10, 28, 21, 5, Color(0.25, 0.22, 0.14))
		_r(img, x - 8, 33, 17, 2, Color(1.0, 0.9, 0.6))
	for cab in range(3): # lit display cabinets along the back wall
		var cx = 6 + cab * 126
		_r(img, cx, 38, 116, 62, Color(0.07, 0.06, 0.07))
		_r(img, cx + 3, 41, 110, 56, Color(0.28, 0.2, 0.12))
		for shelf in range(3):
			var sy = 41 + shelf * 18
			_r(img, cx + 3, sy + 16, 110, 2, Color(0.5, 0.36, 0.2))
			_r(img, cx + 3, sy, 110, 15, Color(0.38, 0.3, 0.18)) # warm shelf light
			_miniatures(img, cx + 6, sy + 15, 104, rng)
	_neon(img, "TABLES", 160, 4, Color(1.0, 0.75, 0.25), 1)
	_wood_floor(img, 104, Color(0.28, 0.22, 0.18))
	# the long table in perspective
	for y in range(112, H):
		var t = float(y - 112) / float(H - 112)
		var half = int(lerpf(96.0, 186.0, t))
		_r(img, W / 2 - half, y, half * 2, 1, Color(0.32, 0.5, 0.3).darkened(0.18 * (1.0 - t)))
		_r(img, W / 2 - half, y, 5, 1, Color(0.35, 0.2, 0.1))
		_r(img, W / 2 + half - 5, y, 5, 1, Color(0.35, 0.2, 0.1))
	_r(img, W / 2 - 96, 110, 192, 3, Color(0.45, 0.28, 0.14)) # the far edge
	for gy in range(124, H, 14): # the mat's grid lines
		var gt = float(gy - 112) / float(H - 112)
		var gh = int(lerpf(96.0, 186.0, gt))
		_r(img, W / 2 - gh + 5, gy, gh * 2 - 10, 1, Color(0.27, 0.43, 0.26))
	# terrain and armies on the felt
	for i in range(34):
		var t2 = rng.randf()
		var y2 = int(lerpf(118.0, 206.0, t2))
		var half2 = int(lerpf(86.0, 176.0, t2))
		var x2 = W / 2 + rng.randi_range(-half2, half2)
		var s = lerpf(0.7, 2.0, t2)
		match i % 4:
			0: # a ruined spire
				_r(img, x2, y2 - int(14.0 * s), int(5.0 * s), int(14.0 * s), Color(0.55, 0.55, 0.6))
				_r(img, x2 + int(5.0 * s), y2 - int(9.0 * s), int(4.0 * s), int(9.0 * s), Color(0.42, 0.42, 0.48))
			1: # a tree
				_r(img, x2 + int(2.0 * s), y2 - int(4.0 * s), int(2.0 * s), int(4.0 * s), Color(0.35, 0.22, 0.12))
				_r(img, x2, y2 - int(10.0 * s), int(6.0 * s), int(7.0 * s), Color(0.15, 0.4, 0.2))
			2: # a squad of miniatures
				for k in range(4):
					_r(img, x2 + int(float(k) * 3.0 * s), y2 - int(4.0 * s), int(2.0 * s), int(4.0 * s), BOX_COLORS[(i + k) % 7])
			3: # dice
				_r(img, x2, y2 - int(2.0 * s), int(2.0 * s), int(2.0 * s), Color(0.95, 0.95, 0.95))
				_r(img, x2 + int(s), y2 - int(s), int(s * 0.7) + 1, int(s * 0.7) + 1, Color(0.1, 0.1, 0.1))
	_r(img, 0, H - 4, W, 4, Color(0.12, 0.09, 0.07))

# ---- 3. the back wall of the card-table area -----------------------------------------------------------------------------------
static func _back(img: Image, rng: RandomNumberGenerator) -> void:
	_r(img, 0, 0, W, H, Color(0.2, 0.17, 0.2))
	_ceiling(img, 16, Color(0.4, 0.4, 0.46))
	for ux in [6, 262]: # tall shelving units of card boxes and binders
		_r(img, ux, 22, 116, 150, Color(0.12, 0.09, 0.07))
		for row in range(7):
			_boxes(img, ux + 3, 26 + row * 21, 110, 15, rng, [Color(0.2, 0.2, 0.28), Color(0.5, 0.18, 0.2), Color(0.18, 0.35, 0.55), Color(0.85, 0.85, 0.9), Color(0.3, 0.5, 0.3), Color(0.7, 0.55, 0.2)])
	_r(img, 138, 62, 108, 62, Color(0.04, 0.04, 0.06)) # the screen
	_r(img, 140, 64, 104, 58, Color(0.1, 0.12, 0.22))
	for k in range(30): # glowing game art
		var gx = 150 + rng.randi() % 84
		var gy = 70 + rng.randi() % 44
		_r(img, gx, gy, rng.randi_range(2, 8), rng.randi_range(2, 5), BOX_COLORS[rng.randi() % 7].lightened(0.1))
	_r(img, 180, 124, 24, 6, Color(0.1, 0.1, 0.12))
	for px in [136, 222]: # posters either side
		_r(img, px, 130, 24, 34, Color(0.45, 0.16, 0.18))
		_r(img, px + 2, 132, 20, 20, Color(0.9, 0.75, 0.3))
		_r(img, px + 2, 154, 20, 8, Color(0.15, 0.15, 0.2))
	_r(img, 132, 22, 118, 34, Color(0.78, 0.84, 0.9)) # a window with blinds
	for by in range(24, 54, 4):
		_r(img, 134, by, 114, 2, Color(0.6, 0.66, 0.74))
	_r(img, 132, 22, 118, 2, Color(0.3, 0.3, 0.34))
	_neon(img, "CARDS", 168, 5, Color(0.9, 0.35, 1.0), 1)
	_wood_floor(img, 172, Color(0.5, 0.36, 0.22))
	for cx in [150, 205]: # a couple of chair backs at the very front
		_r(img, cx, 184, 18, 26, Color(0.12, 0.12, 0.16))
		_r(img, cx + 2, 186, 14, 6, Color(0.2, 0.2, 0.26))
