extends Node

# The ground texture is uploaded at 1/4 size and drawn scaled up with nearest filtering. That is only a
# faithful (and 16x cheaper) reproduction if the full-resolution paint really is made of blocks of at least
# 4x4 identical pixels. Measure that on a real chunk of every map type.
const MapGen = preload("res://scripts/core/MapGenerator.gd")
const TYPES = ["Normal", "Open Field", "Desert", "Forest", "Tundra", "Volcano", "Dungeon", "Water", "Tabletop", "FightShovel"]

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	var worst = 0.0
	for t in TYPES:
		var m = MapGen.new()
		m.map_type = t
		add_child(m)
		await get_tree().process_frame
		var full: Image = m._render_chunk_image(0, 0, 20, Color(0.1, 0.4, 0.9))
		var factor = m.texture_downscale()
		var small: Image = MapGen.downscale_chunk(full, factor)
		var up = Image.new()
		up.copy_from(small)
		up.resize(small.get_width() * factor, small.get_height() * factor, Image.INTERPOLATE_NEAREST)
		var diff = 0
		var n = 0
		for y in range(0, mini(full.get_height(), up.get_height()), 3):
			for x in range(0, mini(full.get_width(), up.get_width()), 3):
				n += 1
				if full.get_pixel(x, y) != up.get_pixel(x, y):
					diff += 1
		var frac = float(diff) / float(max(n, 1))
		worst = maxf(worst, frac)
		_check("%s: downscale x%d reproduces the ground (%.2f%% of sampled pixels differ; %dx%d -> %dx%d)" % [t, factor, frac * 100.0, full.get_width(), full.get_height(), small.get_width(), small.get_height()], frac < 0.03)
		m.queue_free()
		await get_tree().process_frame
	print("chunk downscale check done, worst=%.2f%%, failures=%d" % [worst * 100.0, failures])
	get_tree().quit(0 if failures == 0 else 1)
