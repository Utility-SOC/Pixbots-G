extends Node

# Saves full-resolution closeups of the rasterized terrain around the first
# Wall-rich spot (a fort/village/dungeon room) to ~/pixbots_map_overviews.

const MapGen = preload("res://scripts/core/MapGenerator.gd")

func _ready():
	var t = OS.get_environment("MAPTYPE")
	if t == "":
		t = "Desert"
	var m = MapGen.new()
	m.map_type = t
	var t0 = Time.get_ticks_msec()
	add_child(m)
	print("%s generated+rasterized in %d ms" % [t, Time.get_ticks_msec() - t0])
	await get_tree().process_frame
	# Find the densest 40x26 window of Wall tiles.
	var best = Vector2i(m.width / 2, m.height / 2)
	var best_n = -1
	for y in range(10, m.height - 36, 8):
		for x in range(10, m.width - 50, 8):
			var n = 0
			for yy in range(y, y + 26, 2):
				for xx in range(x, x + 40, 2):
					if m.obstacles.get(Vector2i(xx, yy), "") == "Wall":
						n += 1
			if n > best_n:
				best_n = n
				best = Vector2i(x, y)
	var ts = m.tile_size
	var out = Image.create(40 * ts, 26 * ts, false, Image.FORMAT_RGBA8)
	for k in m._chunk_sprites:
		var spr: Sprite2D = m._chunk_sprites[k]
		var img: Image = spr.texture.get_image()
		var src = Rect2i(Vector2i(best.x * ts, best.y * ts) - Vector2i(spr.position), Vector2i(40 * ts, 26 * ts))
		var chunk_rect = Rect2i(Vector2i.ZERO, img.get_size())
		var inter = src.intersection(chunk_rect)
		if inter.size.x > 0 and inter.size.y > 0:
			out.blit_rect(img, inter, Vector2i(inter.position) - src.position)
	var dir = OS.get_environment("HOME") + "/pixbots_map_overviews"
	out.save_png("%s/closeup_%s.png" % [dir, t])
	print("closeup at tile ", best, " wall-samples ", best_n)
	get_tree().quit()
