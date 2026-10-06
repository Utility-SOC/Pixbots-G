extends RefCounted

# Procedural emblems for the seven sponsor brands (replaces the one-letter placeholder marks). Each is a bold,
# simple glyph that stays readable at tile size (about 16 px) and still looks like a logo on the sponsor banner
# (about 80 px): built from lines, circles and a few polygons, drawn on any CanvasItem in the brand's accent.
#   sniper     crosshair             defensive  heater shield
#   cloak      hooded eye            mobility   double chevron
#   sensors    eye with rays         efficiency microchip with a P trace
#   power      lightning bolt in a hexagon

static func has_emblem(brand_id: String) -> bool:
	return brand_id in ["sniper", "defensive", "cloak", "mobility", "sensors", "efficiency", "power"]

# `r` is the emblem's half-size in pixels; `w` the stroke width.
static func draw(ci: CanvasItem, brand_id: String, c: Vector2, r: float, col: Color, w: float = -1.0) -> void:
	if w < 0.0:
		w = maxf(1.0, r * 0.14)
	match brand_id:
		"sniper":
			ci.draw_arc(c, r * 0.7, 0.0, TAU, 28, col, w, true)
			for a in range(4):
				var d = Vector2.from_angle(a * PI * 0.5)
				ci.draw_line(c + d * r * 0.35, c + d * r, col, w)
			ci.draw_circle(c, r * 0.12, col)
		"defensive":
			var top = r * 0.95
			var pts = PackedVector2Array([c + Vector2(-r * 0.8, -top * 0.8), c + Vector2(r * 0.8, -top * 0.8), c + Vector2(r * 0.8, r * 0.1), c + Vector2(0, r), c + Vector2(-r * 0.8, r * 0.1)])
			ci.draw_polyline(pts + PackedVector2Array([pts[0]]), col, w, true)
			ci.draw_line(c + Vector2(0, -top * 0.8), c + Vector2(0, r * 0.95), Color(col.r, col.g, col.b, 0.7), w * 0.8)
			ci.draw_line(c + Vector2(-r * 0.8, -top * 0.15), c + Vector2(r * 0.8, -top * 0.15), Color(col.r, col.g, col.b, 0.7), w * 0.8)
		"cloak":
			# hooded cowl: round hood over a tattered hem, with two narrow glowing eyes
			var cowl = PackedVector2Array()
			for i in range(13):
				var ang = PI + PI * float(i) / 12.0
				cowl.append(c + Vector2(cos(ang) * r * 0.8, sin(ang) * r * 0.8 - r * 0.1))
			cowl.append(c + Vector2(r * 0.9, r * 0.95))
			cowl.append(c + Vector2(r * 0.45, r * 0.7))
			cowl.append(c + Vector2(0, r * 0.98))
			cowl.append(c + Vector2(-r * 0.45, r * 0.7))
			cowl.append(c + Vector2(-r * 0.9, r * 0.95))
			ci.draw_polyline(cowl + PackedVector2Array([cowl[0]]), col, w, true)
			ci.draw_line(c + Vector2(-r * 0.5, -r * 0.05), c + Vector2(-r * 0.12, r * 0.12), col, w * 1.5)
			ci.draw_line(c + Vector2(r * 0.5, -r * 0.05), c + Vector2(r * 0.12, r * 0.12), col, w * 1.5)
		"mobility":
			for k in range(2):
				var y = (-0.45 + k * 0.55) * r
				var pts = PackedVector2Array([c + Vector2(-r * 0.9, y + r * 0.1), c + Vector2(0, y - r * 0.4), c + Vector2(r * 0.9, y + r * 0.1)])
				ci.draw_polyline(pts, col, w * 1.4, true)
		"sensors":
			var top_pts = PackedVector2Array()
			var bot_pts = PackedVector2Array()
			for i in range(9):
				var t = float(i) / 8.0
				var x = lerpf(-r, r, t)
				var yy = sin(t * PI) * r * 0.5
				top_pts.append(c + Vector2(x, -yy))
				bot_pts.append(c + Vector2(x, yy))
			ci.draw_polyline(top_pts, col, w, true)
			ci.draw_polyline(bot_pts, col, w, true)
			ci.draw_circle(c, r * 0.24, col)
			for a in [-0.9, 0.0, 0.9]:
				var d = Vector2(sin(a), -cos(a))
				ci.draw_line(c + d * r * 0.7, c + d * r * 1.0, Color(col.r, col.g, col.b, 0.8), w * 0.8)
		"efficiency":
			var sq = Rect2(c - Vector2(r, r) * 0.62, Vector2(r, r) * 1.24)
			ci.draw_rect(sq, col, false, w)
			for k in range(3):
				var o = (-0.35 + k * 0.35) * r
				ci.draw_line(c + Vector2(o, -r * 0.62), c + Vector2(o, -r), col, w * 0.8)
				ci.draw_line(c + Vector2(o, r * 0.62), c + Vector2(o, r), col, w * 0.8)
				ci.draw_line(c + Vector2(-r * 0.62, o), c + Vector2(-r, o), col, w * 0.8)
				ci.draw_line(c + Vector2(r * 0.62, o), c + Vector2(r, o), col, w * 0.8)
			var trace = PackedVector2Array([c + Vector2(-r * 0.25, r * 0.32), c + Vector2(-r * 0.25, -r * 0.3), c + Vector2(r * 0.15, -r * 0.3), c + Vector2(r * 0.15, 0), c + Vector2(-r * 0.25, 0)])
			ci.draw_polyline(trace, col, w, true)
		"power":
			var hex = PackedVector2Array()
			for i in range(6):
				hex.append(c + Vector2.from_angle(PI / 6.0 + i * PI / 3.0) * r)
			ci.draw_polyline(hex + PackedVector2Array([hex[0]]), col, w, true)
			var bolt = PackedVector2Array([c + Vector2(r * 0.15, -r * 0.62), c + Vector2(-r * 0.3, r * 0.08), c + Vector2(0, r * 0.08), c + Vector2(-r * 0.15, r * 0.62), c + Vector2(r * 0.32, -r * 0.1), c + Vector2(0.02 * r, -r * 0.1)])
			ci.draw_colored_polygon(bolt, col)
		_:
			ci.draw_circle(c, r * 0.5, col)
