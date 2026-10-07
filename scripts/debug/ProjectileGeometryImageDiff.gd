extends Node

# Windowed visual parity: the SAME frozen batch-pool state is rendered through the GDScript atlas path and through the
# Rust geometry builder; the two images must match. Covers rotation, beams (non-uniform scale), vortex helix,
# 2-5 element mixes (echoes, extra dots), sizes and sparks. Saves geomA.png (GDScript), geomB.png (Rust) and
# geomDiff.png (amplified) next to --out=/dir.
#   godot --path . res://scripts/debug/ProjectileGeometryImageDiff.tscn -- --out=/tmp/dir

const PoolScript = preload("res://scripts/entities/ProjectileBatchPool.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	var out_dir = "/tmp"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out_dir = a.split("=")[1]
	if not ClassDB.class_exists("ProjectileGeometry"):
		print("SKIP: the ProjectileGeometry class is not in the loaded extension (rebuild rust_ext)")
		get_tree().quit(2)
		return
	var world = Node2D.new()
	add_child(world)
	var cam = Camera2D.new()
	cam.position = Vector2(330, 190)
	cam.zoom = Vector2(1.6, 1.6)
	world.add_child(cam)
	var pool = PoolScript.new()
	world.add_child(pool)
	var src = Node2D.new()
	world.add_child(src)
	var mixes = [
		{1: 1.0}, {2: 1.0}, {3: 1.0}, {4: 1.0}, {5: 1.0}, {6: 1.0}, {7: 1.0}, {8: 1.0}, {9: 1.0},
		{1: 0.6, 2: 0.4}, {3: 0.5, 7: 0.5}, {5: 0.7, 6: 0.3}, {8: 0.5, 9: 0.5}, {4: 0.6, 1: 0.2, 2: 0.2}, {7: 0.5, 3: 0.25, 8: 0.25}, {9: 0.4, 5: 0.3, 6: 0.3},
		{1: 0.34, 2: 0.33, 3: 0.33}, {1: 0.3, 2: 0.25, 3: 0.25, 4: 0.2}, {5: 0.3, 6: 0.25, 7: 0.25, 8: 0.2}, {1: 0.25, 3: 0.25, 5: 0.25, 7: 0.25},
		{1: 0.2, 2: 0.2, 3: 0.2, 4: 0.2, 5: 0.2}, {2: 0.3, 4: 0.2, 6: 0.2, 8: 0.15, 9: 0.15}, {7: 0.5, 8: 0.5}, {1: 0.5, 8: 0.5},
	]
	var idx = 0
	for m in mixes:
		var dom = 0
		var best = -1.0
		for k in m:
			if m[k] > best:
				best = m[k]
				dom = k
		var ratios = {}
		for k in m:
			ratios[k] = m[k]
		var col = EnergyPacket.get_color_for_synergy(dom) * 1.5
		col.a = 1.0
		var ang = idx * 0.61
		var pos = Vector2(40 + (idx % 8) * 80, 40 + (idx / 8) * 80)
		var scale_mult = 1.5 + float(idx % 4) * 0.9
		pool.spawn(pos, Vector2(cos(ang), sin(ang)), 0.01, 10.0, 10.0, 100.0, col, scale_mult, true, src, dom, ratios)
		idx += 1
	# Beams at assorted angles and speeds (non-uniform scale: the quirk that must match).
	for b in range(6):
		var ang = b * 0.5
		var col = EnergyPacket.get_color_for_synergy(3) * 1.5
		col.a = 1.0
		pool.spawn(Vector2(60 + b * 90, 300), Vector2(cos(ang), sin(ang)), 0.01 + 400.0 * b, 10.0, 10.0, 100.0, col, 2.0, true, src, 3, {3: 1.0}, {}, 0.0, {}, 1.0, true)
	for f in range(4):
		await get_tree().process_frame
	pool.set_process(false) # freeze elapsed so orbits/sparks stay put
	await get_tree().process_frame

	PoolScript.use_rust_geometry = false
	pool.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	var img_a: Image = get_viewport().get_texture().get_image()
	PoolScript.use_rust_geometry = true
	pool.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	var img_b: Image = get_viewport().get_texture().get_image()
	_check("the Rust path was actually used for image B", pool._geom != null)
	img_a.save_png(out_dir + "/geomA.png")
	img_b.save_png(out_dir + "/geomB.png")

	img_a.convert(Image.FORMAT_RGBA8)
	img_b.convert(Image.FORMAT_RGBA8)
	var da = img_a.get_data()
	var db = img_b.get_data()
	var w = img_a.get_width()
	var h = img_a.get_height()
	var diff = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var lit = 0
	var bad = 0
	var max_d = 0
	var sum_d = 0
	for p in range(w * h):
		var o = p * 4
		var d = 0
		for ch in range(3):
			d = max(d, abs(da[o + ch] - db[o + ch]))
		if da[o] + da[o + 1] + da[o + 2] > 24 or db[o] + db[o + 1] + db[o + 2] > 24:
			lit += 1
		if d > 6:
			bad += 1
			diff.set_pixel(p % w, p / w, Color(1, 0, 0, 1))
		max_d = max(max_d, d)
		sum_d += d
	diff.save_png(out_dir + "/geomDiff.png")
	print("GEOMDIFF size=%dx%d lit_pixels=%d differing(>6)=%d max_diff=%d mean_diff=%.4f" % [w, h, lit, bad, max_d, float(sum_d) / float(w * h)])
	_check("images are not blank (%d lit pixels)" % lit, lit > 2000)
	_check("Rust and GDScript renders match: %d of %d lit pixels differ by more than 6/255 (max %d)" % [bad, lit, max_d], bad <= lit * 0.002)
	print("ProjectileGeometryImageDiff: %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)
