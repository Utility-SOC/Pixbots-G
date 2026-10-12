class_name MapDecor
extends RefCounted

# Ground decoration baked into the terrain chunk images (MapGenerator._render_chunk_image): poppies, craters, barbed wire,
# bones, tracks, hydrothermal pools, the yellow brick road. Painted once at load time on the CPU image, so it costs nothing
# at runtime. `decor` maps a tile (Vector2i) to a kind string; each kind draws inside its tile only.

const KINDS = ["poppy", "poppy_dense", "crater", "wire", "bones", "tracks", "debris", "yellow_road", "flowers", "pool_deep", "pool_blue",
	"pool_green", "pool_yellow", "pool_orange", "ripple", "moss", "cracks", "scorch", "sandbags", "blood_moon_glow", "grass_tuft", "ice_crack", "ash"]

static func _h(cell: Vector2i, salt: int) -> int:
	return posmod(cell.x * 73856093 ^ cell.y * 19349663 ^ salt * 83492791, 100003)

static func paint(img: Image, kind: String, ox: int, oy: int, t: int, cell: Vector2i) -> void:
	match kind:
		"poppy", "poppy_dense":
			var n = 7 if kind == "poppy_dense" else 3
			for i in range(n):
				var x = ox + 2 + _h(cell, i * 2 + 1) % (t - 6)
				var y = oy + 4 + _h(cell, i * 2 + 2) % (t - 8)
				img.fill_rect(Rect2i(x, y + 4, 2, 4), Color(0.2, 0.42, 0.16)) # stalk
				img.fill_rect(Rect2i(x - 1, y, 4, 4), Color(0.86, 0.1, 0.08))
				img.fill_rect(Rect2i(x, y + 1, 2, 2), Color(0.1, 0.05, 0.05))
		"flowers":
			for i in range(5):
				var x = ox + 2 + _h(cell, i * 2 + 1) % (t - 6)
				var y = oy + 2 + _h(cell, i * 2 + 2) % (t - 6)
				var c = [Color(0.95, 0.9, 0.3), Color(0.95, 0.5, 0.75), Color(0.6, 0.7, 1.0), Color(1.0, 1.0, 1.0)][_h(cell, i) % 4]
				img.fill_rect(Rect2i(x, y, 3, 3), c)
		"crater":
			var cx = ox + t / 2
			var cy = oy + t / 2
			var rad = t / 2 - 2
			for dy in range(-rad, rad + 1):
				for dx in range(-rad, rad + 1):
					var d2 = dx * dx + dy * dy
					if d2 <= rad * rad:
						var inner = d2 <= (rad - 4) * (rad - 4)
						img.set_pixel(cx + dx, cy + dy, Color(0.16, 0.12, 0.1) if inner else Color(0.38, 0.3, 0.22))
		"scorch":
			for i in range(14):
				var x = ox + _h(cell, i * 2 + 1) % (t - 4)
				var y = oy + _h(cell, i * 2 + 2) % (t - 4)
				img.fill_rect(Rect2i(x, y, 4, 4), Color(0.12, 0.1, 0.09))
		"wire":
			var y0 = oy + t / 2
			for x in range(t):
				var y = y0 + (3 if (x / 3) % 2 == 0 else -3)
				img.set_pixel(ox + x, clampi(y, oy, oy + t - 1), Color(0.18, 0.18, 0.2))
				if x % 8 == 0:
					img.fill_rect(Rect2i(ox + x, y0 - 6, 2, 12), Color(0.28, 0.22, 0.16))
		"bones":
			for i in range(3):
				var x = ox + 3 + _h(cell, i * 2 + 1) % (t - 10)
				var y = oy + 3 + _h(cell, i * 2 + 2) % (t - 8)
				img.fill_rect(Rect2i(x, y, 6, 2), Color(0.88, 0.85, 0.76))
				img.fill_rect(Rect2i(x - 1, y - 1, 2, 4), Color(0.88, 0.85, 0.76))
		"tracks":
			for k in [8, 22]:
				for x in range(0, t, 4):
					img.fill_rect(Rect2i(ox + x, oy + k, 3, 4), Color(0.2, 0.17, 0.13))
		"debris":
			for i in range(8):
				var x = ox + _h(cell, i * 2 + 1) % (t - 3)
				var y = oy + _h(cell, i * 2 + 2) % (t - 3)
				img.fill_rect(Rect2i(x, y, 3, 2), Color(0.42, 0.4, 0.42))
		"yellow_road":
			for by in range(0, t, 8):
				for bx in range(0, t, 8):
					var shift = 4 if (by / 8) % 2 == 1 else 0
					img.fill_rect(Rect2i(ox + (bx + shift) % t, oy + by, 8, 8), Color(0.95, 0.8, 0.2) if (bx / 8 + by / 8) % 2 == 0 else Color(0.85, 0.68, 0.12))
		"pool_deep", "pool_blue", "pool_green", "pool_yellow", "pool_orange":
			var col = {"pool_deep": Color(0.05, 0.2, 0.55), "pool_blue": Color(0.1, 0.5, 0.8), "pool_green": Color(0.2, 0.7, 0.55),
				"pool_yellow": Color(0.9, 0.85, 0.3), "pool_orange": Color(0.9, 0.45, 0.15)}[kind]
			for by in range(0, t, 8):
				for bx in range(0, t, 8):
					var c = col if (_h(cell, bx + by * 7) % 6) != 0 else col.lightened(0.15)
					img.fill_rect(Rect2i(ox + bx, oy + by, 8, 8), c)
		"ripple":
			for i in range(3):
				var y = oy + 4 + i * 10
				for x in range(0, t, 6):
					img.fill_rect(Rect2i(ox + x, y + (x / 6) % 2, 4, 1), Color(0.8, 0.72, 0.52))
		"moss":
			for i in range(10):
				var x = ox + _h(cell, i * 2 + 1) % (t - 4)
				var y = oy + _h(cell, i * 2 + 2) % (t - 4)
				img.fill_rect(Rect2i(x, y, 4, 4), Color(0.2, 0.4, 0.2, 1.0))
		"cracks":
			var x = ox + _h(cell, 1) % t
			var y = oy
			while y < oy + t:
				img.set_pixel(clampi(x, ox, ox + t - 1), y, Color(0.1, 0.09, 0.09))
				y += 1
				x += (_h(cell, y) % 3) - 1
		"sandbags":
			for i in range(3):
				img.fill_rect(Rect2i(ox + 3 + i * 9, oy + 12 + (i % 2) * 4, 8, 6), Color(0.64, 0.56, 0.38))
				img.fill_rect(Rect2i(ox + 3 + i * 9, oy + 12 + (i % 2) * 4, 8, 1), Color(0.78, 0.7, 0.5))
		"grass_tuft":
			for i in range(4):
				var x = ox + _h(cell, i * 2 + 1) % (t - 4)
				var y = oy + _h(cell, i * 2 + 2) % (t - 6)
				img.fill_rect(Rect2i(x, y, 1, 5), Color(0.18, 0.4, 0.15))
				img.fill_rect(Rect2i(x + 2, y + 1, 1, 4), Color(0.22, 0.46, 0.18))
		"ice_crack":
			var cx2 = ox + t / 2
			for i in range(6):
				var a = TAU * float(i) / 6.0 + float(_h(cell, i) % 10) * 0.1
				for k in range(t / 2 - 2):
					img.set_pixel(clampi(cx2 + int(cos(a) * k), ox, ox + t - 1), clampi(oy + t / 2 + int(sin(a) * k), oy, oy + t - 1), Color(0.55, 0.7, 0.8))
		"ash":
			for i in range(10):
				var x = ox + _h(cell, i * 2 + 1) % (t - 3)
				var y = oy + _h(cell, i * 2 + 2) % (t - 3)
				img.fill_rect(Rect2i(x, y, 3, 3), Color(0.3, 0.3, 0.32))
		"blood_moon_glow":
			for i in range(6):
				var x = ox + _h(cell, i * 2 + 1) % (t - 4)
				var y = oy + _h(cell, i * 2 + 2) % (t - 4)
				img.fill_rect(Rect2i(x, y, 4, 4), Color(0.7, 0.15, 0.3))
