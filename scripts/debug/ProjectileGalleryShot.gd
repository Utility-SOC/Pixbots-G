extends Node

# Deterministic visual A/B of the batch pool renderers: a fixed grid of stationary
# shots with set element mixes (1 to 5 elements), saved as a PNG.
#   godot --path . res://scripts/debug/ProjectileGalleryShot.tscn -- --render=0..4 [--poly] --out=/path.png

const PoolScript = preload("res://scripts/entities/ProjectileBatchPool.gd")

func _ready():
	var rmode = 0
	var poly = false
	var out = "/tmp/gallery.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--render="): rmode = int(a.split("=")[1])
		elif a == "--poly": poly = true
		elif a.begins_with("--out="): out = a.split("=")[1]
	var world = Node2D.new()
	add_child(world)
	var cam = Camera2D.new()
	cam.position = Vector2(300, 150)
	cam.zoom = Vector2(2.0, 2.0)
	world.add_child(cam)
	var pool = PoolScript.new()
	world.add_child(pool)
	pool.render_mode = rmode
	pool.use_atlas = not poly
	var src = Node2D.new()
	world.add_child(src)
	# [ratio dict], rows of mixes
	var mixes = [
		{1: 1.0}, {2: 1.0}, {3: 1.0}, {4: 1.0}, {5: 1.0}, {6: 1.0}, {7: 1.0}, {8: 1.0},
		{1: 0.6, 2: 0.4}, {3: 0.5, 7: 0.5}, {5: 0.7, 6: 0.3}, {8: 0.5, 9: 0.5}, {4: 0.6, 1: 0.2, 2: 0.2}, {7: 0.5, 3: 0.25, 8: 0.25}, {9: 0.4, 5: 0.3, 6: 0.3}, {1: 0.34, 2: 0.33, 3: 0.33},
		{1: 0.3, 2: 0.25, 3: 0.25, 4: 0.2}, {5: 0.3, 6: 0.25, 7: 0.25, 8: 0.2}, {1: 0.25, 3: 0.25, 5: 0.25, 7: 0.25}, {1: 0.2, 2: 0.2, 3: 0.2, 4: 0.2, 5: 0.2}, {2: 0.3, 4: 0.2, 6: 0.2, 8: 0.15, 9: 0.15},
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
		var pos = Vector2(60 + (idx % 8) * 62, 60 + (idx / 8) * 70)
		pool.spawn(pos, Vector2(1, 0), 0.01, 10.0, 10.0, 100.0, col, 3.0, true, src, dom, ratios)
		idx += 1
	for f in range(3):
		await get_tree().process_frame
	# freeze: step simulation off so elapsed-driven orbit/sparks stay put
	pool.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
