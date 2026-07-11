class_name MechPartRenderer
extends Node2D

# Genuine pixel art, not faked pixel art. The previous version drew smooth
# vector polygons and relied on a downscaled-then-upscaled SubViewport to
# make everything LOOK chunky - but that only ever hides the blur, it can't
# remove it, because there's real anti-aliased geometry underneath at every
# stage. This bakes each part into a small Image directly, one hard-edged
# cell at a time (point-in-polygon / point-to-segment tests against the
# same shape data the old renderer used), and displays it via a Sprite2D
# with nearest-neighbor filtering. There is no smooth geometry to blur,
# at any zoom or resolution, on any display, CRT or not.
#
# Public API (add_fill / add_line / add_loop / finish) is UNCHANGED from
# the vector-draw version on purpose - MechRenderer.gd's calls don't need
# to know or care that painting is now rasterized instead of vector-drawn.

# World-units per pixel "cell". Bigger = chunkier/more legible, smaller =
# more detail but softer-reading at a glance. 4.5 keeps a ~36-unit-wide
# torso to roughly 8 cells across - deliberately chunkier than the original
# 3.0/~12-cells (Natalia: "MUCH lower resolution would be fine, I just want
# a wider variety of mech appearance and for them to look good doing it") -
# genuinely small icon-sprite territory rather than Mario-sprite territory,
# which also means the per-shape shading gradient below (see
# _rasterize_polygon) reads as bold color bands instead of getting lost in
# noise, the opposite problem a HIGHER resolution would have here.
const CELL_SIZE = 4.5
# How many cells the bake canvas extends from center in each direction.
# Must comfortably cover the largest part shape (arms/legs reach furthest).
const GRID_RADIUS = 16
const GRID_DIM = GRID_RADIUS * 2

var _fill_regions: Array = []  # [{polygon: PackedVector2Array, color: Color}], painted in order
var _line_regions: Array = []  # [{a: Vector2, b: Vector2, color: Color, width: float}]
var _sprite: Sprite2D = null

# Optional native accelerator (rust_ext GDExtension, see ../../rust_ext/) for
# the pixel loops below - measured ~60x faster in-engine (1690us -> 28us per
# part; see rust_ext/README.md for the full benchmark writeup) since spawning
# a squad of enemies bakes 6 parts x N mechs synchronously and was the actual
# cause of the enemy-spawn stutter. Falls back to the pure-GDScript rasterizer
# below if the extension DLL isn't present/loaded (e.g. a fresh checkout
# before anyone's run `cargo build` in rust_ext/) - _rasterize_polygon/
# _rasterize_line/_add_outline are kept as the reference implementation and
# fallback, not dead code.
var _rasterizer = null
var _rasterizer_checked: bool = false
const OUTLINE_COLOR = Color(0.05, 0.05, 0.08, 1.0)

func add_fill(polygon: PackedVector2Array, color: Color):
	if polygon.size() < 3:
		return
	_fill_regions.append({"polygon": polygon, "color": color})

func add_line(a: Vector2, b: Vector2, color: Color, width: float = 1.5):
	_line_regions.append({"a": a, "b": b, "color": color, "width": width})

func add_loop(points: PackedVector2Array, color: Color, width: float = 1.5):
	for i in range(points.size() - 1):
		_line_regions.append({"a": points[i], "b": points[i + 1], "color": color, "width": width})

func clear_layers():
	_fill_regions.clear()
	_line_regions.clear()

# Bakes everything queued so far into the sprite. Named finish() (not
# bake()) to match the old API - MechRenderer.gd calls this once per part
# after queuing all its fills/lines/accents.
func finish():
	if not _rasterizer_checked:
		_rasterizer_checked = true
		if ClassDB.class_exists("PartRasterizer"):
			_rasterizer = ClassDB.instantiate("PartRasterizer")

	var img: Image
	if _rasterizer:
		var bytes = _rasterizer.rasterize(_fill_regions, _line_regions, OUTLINE_COLOR)
		img = Image.create_from_data(GRID_DIM, GRID_DIM, false, Image.FORMAT_RGBA8, bytes)
	else:
		img = Image.create(GRID_DIM, GRID_DIM, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		for region in _fill_regions:
			_rasterize_polygon(img, region.polygon, region.color)
		for line in _line_regions:
			_rasterize_line(img, line.a, line.b, line.color, line.width)
		_add_outline(img)

	if not _sprite:
		_sprite = Sprite2D.new()
		_sprite.centered = true
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_sprite)

	_sprite.texture = ImageTexture.create_from_image(img)
	_sprite.scale = Vector2.ONE * CELL_SIZE

func _cell_to_local(gx: int, gy: int) -> Vector2:
	return Vector2((gx - GRID_RADIUS) + 0.5, (gy - GRID_RADIUS) + 0.5) * CELL_SIZE

# Classic top-left directional pixel-art light, as a smooth gradient across
# each fill region's OWN bounding box - not per-pixel edge detection. An
# earlier per-edge highlight/shadow bevel pass was tried and abandoned (see
# _add_outline's comment below): at this few pixels, classifying pixels as
# "edge" vs "not edge" produces a scattered, noisy result. A continuous
# gradient spanning the whole shape instead reads as one lit surface with
# real volume, and gets bolder (not noisier) as resolution drops, since
# fewer, larger color bands are exactly what a low pixel count wants.
const LIGHT_DIR = Vector2(-0.55, -0.85)
const SHADE_STRENGTH = 0.3 # max lighten/darken at the gradient's extremes

func _rasterize_polygon(img: Image, polygon: PackedVector2Array, color: Color):
	var light := LIGHT_DIR.normalized()
	var min_p := Vector2.INF
	var max_p := -Vector2.INF
	for p in polygon:
		min_p = min_p.min(p)
		max_p = max_p.max(p)
	var center := (min_p + max_p) * 0.5
	var half_extent: float = max((max_p - min_p).length() * 0.5, 1.0)

	for gy in range(GRID_DIM):
		for gx in range(GRID_DIM):
			var p := _cell_to_local(gx, gy)
			if Geometry2D.is_point_in_polygon(p, polygon):
				var t: float = clamp((p - center).dot(light) / half_extent, -1.0, 1.0)
				# Quantize the gradient to 3 flat tone bands (lit / base /
				# shadow) - pixel-art materials read as toon-shaded plastic,
				# not airbrushed metal. Thresholds at +/-0.33 keep the base
				# band dominant. Mirrored EXACTLY in part_rasterizer.rs.
				if t > 0.33:
					t = 1.0
				elif t < -0.33:
					t = -1.0
				else:
					t = 0.0
				var shaded := color.lightened(SHADE_STRENGTH * t) if t > 0.0 else color.darkened(SHADE_STRENGTH * -t)
				img.set_pixel(gx, gy, shaded)

func _rasterize_line(img: Image, a: Vector2, b: Vector2, color: Color, width: float):
	var half_w = max(CELL_SIZE * 0.5, width * 0.5)
	for gy in range(GRID_DIM):
		for gx in range(GRID_DIM):
			var p = _cell_to_local(gx, gy)
			if _distance_to_segment(p, a, b) <= half_w:
				img.set_pixel(gx, gy, color)

func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab = b - a
	var len_sq = ab.length_squared()
	if len_sq <= 0.0001:
		return p.distance_to(a)
	var t = clamp((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)

# Single-cell dark outline around the painted silhouette - this is what
# actually makes a pixel-art sprite read clearly against the background and
# against other overlapping parts, standing in for the old vector version's
# per-edge highlight/shadow bevel treatment (which doesn't translate well
# to this few pixels - it just looks like noise).
func _add_outline(img: Image):
	var outline_color = OUTLINE_COLOR
	var edge_cells = []
	for gy in range(GRID_DIM):
		for gx in range(GRID_DIM):
			if img.get_pixel(gx, gy).a > 0.0:
				continue
			var touches_fill = false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx = gx + d.x
				var ny = gy + d.y
				if nx < 0 or ny < 0 or nx >= GRID_DIM or ny >= GRID_DIM:
					continue
				if img.get_pixel(nx, ny).a > 0.0:
					touches_fill = true
					break
			if touches_fill:
				edge_cells.append(Vector2i(gx, gy))
	for c in edge_cells:
		img.set_pixel(c.x, c.y, outline_color)
