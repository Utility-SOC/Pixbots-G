extends Node

# Rust geometry builder vs the GDScript atlas path, quad by quad: the GDScript path logs every _dq() call
# (cell, pos, rot, sx, sy, colour); the Rust builder's vertices / uvs / colours must match what those calls imply
# (same count, same order, same corners, same atlas rects, same tints). Needs only a node tree (headless is fine).

const PoolScript = preload("res://scripts/entities/ProjectileBatchPool.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	if not ClassDB.class_exists("ProjectileGeometry"):
		print("SKIP: ProjectileGeometry is not in the loaded extension")
		get_tree().quit(2)
		return
	var world = Node2D.new()
	add_child(world)
	var pool = PoolScript.new()
	world.add_child(pool)
	var src = Node2D.new()
	world.add_child(src)
	seed(5)
	var mixes = [
		{1: 1.0}, {2: 1.0}, {4: 1.0}, {7: 1.0}, {8: 1.0}, {1: 0.6, 2: 0.4}, {3: 0.5, 7: 0.5}, {8: 0.5, 9: 0.5},
		{4: 0.6, 1: 0.2, 2: 0.2}, {1: 0.3, 2: 0.25, 3: 0.25, 4: 0.2}, {1: 0.2, 2: 0.2, 3: 0.2, 4: 0.2, 5: 0.2},
		{2: 0.3, 4: 0.2, 6: 0.2, 8: 0.15, 9: 0.15}, {7: 0.5, 8: 0.5},
	]
	var idx = 0
	for m in mixes:
		var dom = 0
		var best = -1.0
		for k in m:
			if m[k] > best:
				best = m[k]
				dom = k
		var col = EnergyPacket.get_color_for_synergy(dom) * 1.5
		col.a = 1.0
		var ang = randf() * TAU
		pool.spawn(Vector2(randf_range(0, 600), randf_range(0, 400)), Vector2(cos(ang), sin(ang)), 0.01, 10.0, 10.0, 100.0, col, randf_range(1.0, 4.5), true, src, dom, m.duplicate())
		idx += 1
	for b in range(4):
		var ang = randf() * TAU
		var col = EnergyPacket.get_color_for_synergy(3) * 1.5
		col.a = 1.0
		pool.spawn(Vector2(randf_range(0, 600), randf_range(0, 400)), Vector2(cos(ang), sin(ang)), 100.0 + 300.0 * b, 10.0, 10.0, 100.0, col, 2.0, true, src, 3, {3: 1.0}, {}, 0.0, {}, 1.0, true)
	for f in range(5):
		await get_tree().process_frame
	pool.set_process(false)
	await get_tree().process_frame

	# 1) Record what the GDScript path draws.
	PoolScript.use_rust_geometry = false
	pool._record_quads = true
	pool._quad_log.clear()
	pool.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	var log: Array = pool._quad_log.duplicate()
	pool._record_quads = false
	_check("the GDScript path logged its quads (%d)" % log.size(), log.size() > 100)

	# 2) Ask the Rust builder for the same frame's geometry.
	PoolScript.use_rust_geometry = true
	_check("the Rust builder is available", pool._ensure_geometry())
	var g = pool._geom
	g.set_count(pool._highest_active + 1)
	g.load_a(pool._alive, pool._dominant_synergy, pool._direction, pool._position, pool._visual_offset, pool._scale, pool._color_pk)
	var quads: int = g.build(pool._elapsed, pool._lifetime, pool._is_beam, pool._speed, pool._secondary_synergy_1, pool._secondary_synergy_2, pool._extra_mask, pool._spark_hash)
	_check("same number of quads (GDScript %d, Rust %d)" % [log.size(), quads], quads == log.size())

	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var inds := PackedInt32Array()
	for k in range(g.chunk_count()):
		var base = pts.size()
		pts.append_array(g.chunk_points(k))
		cols.append_array(g.chunk_colors(k))
		uvs.append_array(g.chunk_uvs(k))
		for ix in g.chunk_indices(k):
			inds.append(ix) # indices are chunk-local: fine to compare per chunk below
	_check("4 vertices per quad", pts.size() == quads * 4 and cols.size() == pts.size() and uvs.size() == pts.size())
	_check("6 indices per quad", inds.size() == quads * 6)

	var tex_w: float = PoolScript._atlas_tex.get_width()
	var tex_h: float = PoolScript._atlas_tex.get_height()
	var worst_pos := 0.0
	var worst_uv := 0.0
	var worst_col := 0.0
	var n = min(log.size(), quads)
	for q in range(n):
		var e = log[q]
		var cell: int = e[0]
		var pos: Vector2 = e[1]
		var rot: float = e[2]
		var sx: float = e[3]
		var sy: float = e[4]
		var col: Color = e[5]
		var u: Rect2 = PoolScript._atlas_units[cell]
		var p: Rect2 = PoolScript._atlas_px[cell]
		var xf := Transform2D(rot, Vector2(sx, sy), 0.0, pos) # what draw_set_transform builds in Godot 4
		var corners = [
			[u.position, p.position],
			[Vector2(u.end.x, u.position.y), Vector2(p.end.x, p.position.y)],
			[u.end, p.end],
			[Vector2(u.position.x, u.end.y), Vector2(p.position.x, p.end.y)],
		]
		for c in range(4):
			var want_pos: Vector2 = xf * (corners[c][0] as Vector2)
			var want_uv: Vector2 = (corners[c][1] as Vector2) / Vector2(tex_w, tex_h)
			worst_pos = max(worst_pos, want_pos.distance_to(pts[q * 4 + c]))
			worst_uv = max(worst_uv, want_uv.distance_to(uvs[q * 4 + c]))
			var gc: Color = cols[q * 4 + c]
			worst_col = max(worst_col, max(max(abs(gc.r - col.r), abs(gc.g - col.g)), max(abs(gc.b - col.b), abs(gc.a - col.a))))
	_check("vertex positions match the GDScript transforms (worst %.5f px)" % worst_pos, worst_pos < 0.01)
	_check("atlas uvs match the source rects (worst %.7f)" % worst_uv, worst_uv < 0.00001)
	_check("vertex colours match the tints (worst %.5f)" % worst_col, worst_col < 0.002)
	print("ProjectileGeometryParityCheck: %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)
