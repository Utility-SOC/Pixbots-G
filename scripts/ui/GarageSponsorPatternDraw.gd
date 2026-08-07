extends Control

# Tiny procedural backdrop for a Sponsor banner (GarageSponsorPopup.gd) -
# real logo art is deferred (see BrandRegistry.gd's header comment on the
# locked "procedural visuals are the default" ruling), so each brand gets a
# simple geometric motif instead, drawn at low alpha behind the name/logo
# text so the banner reads as "this brand's own thing" at a glance even
# before real art exists.

var pattern_id: String = "dots"
var pattern_color: Color = Color(1, 1, 1, 0.18)

func _draw():
	match pattern_id:
		"dots":
			_draw_dots()
		"diagonal_stripes":
			_draw_diagonal_stripes()
		"chevron":
			_draw_chevron()
		"hex_grid":
			_draw_hex_grid()
		"concentric_rings":
			_draw_concentric_rings()
		"circuit_lines":
			_draw_circuit_lines()
		"cross_hatch":
			_draw_cross_hatch()
		_:
			_draw_dots()

func _draw_dots():
	var spacing = 18.0
	var y = spacing * 0.5
	while y < size.y:
		var x = spacing * 0.5
		while x < size.x:
			draw_circle(Vector2(x, y), 2.5, pattern_color)
			x += spacing
		y += spacing

func _draw_diagonal_stripes():
	var spacing = 16.0
	var offset = -size.y
	while offset < size.x:
		draw_line(Vector2(offset, size.y), Vector2(offset + size.y, 0.0), pattern_color, 3.0)
		offset += spacing

func _draw_chevron():
	var spacing = 20.0
	var x = -spacing
	while x < size.x + size.y * 0.5:
		var pts = PackedVector2Array([
			Vector2(x, size.y),
			Vector2(x + size.y * 0.5, 0.0),
			Vector2(x + size.y, size.y),
		])
		draw_polyline(pts, pattern_color, 3.0)
		x += spacing

func _draw_hex_grid():
	var r = 10.0
	var hstep = r * 1.8
	var vstep = r * 1.6
	var row = 0
	var y = r
	while y < size.y + r:
		var x_off = (r * 0.9) if row % 2 == 1 else 0.0
		var x = x_off
		while x < size.x + r:
			var pts = PackedVector2Array()
			for i in range(6):
				var ang = TAU / 6.0 * i
				pts.append(Vector2(x, y) + Vector2(cos(ang), sin(ang)) * r)
			pts.append(pts[0])
			draw_polyline(pts, pattern_color, 1.5)
			x += hstep
		y += vstep
		row += 1

func _draw_concentric_rings():
	var center = size * 0.5
	var max_r = max(size.x, size.y)
	var r = 10.0
	while r < max_r:
		draw_arc(center, r, 0, TAU, 48, pattern_color, 1.5)
		r += 16.0

func _draw_circuit_lines():
	var spacing = 22.0
	var y = spacing * 0.5
	var toggle = false
	while y < size.y:
		var x0 = 0.0
		var x1 = size.x * (0.4 if toggle else 0.7)
		draw_line(Vector2(x0, y), Vector2(x1, y), pattern_color, 2.0)
		draw_circle(Vector2(x1, y), 3.0, pattern_color)
		y += spacing
		toggle = not toggle

func _draw_cross_hatch():
	var spacing = 16.0
	var offset = -size.y
	while offset < size.x:
		draw_line(Vector2(offset, size.y), Vector2(offset + size.y, 0.0), pattern_color, 2.0)
		draw_line(Vector2(offset, 0.0), Vector2(offset + size.y, size.y), pattern_color, 2.0)
		offset += spacing
