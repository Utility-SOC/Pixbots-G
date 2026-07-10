extends Node

# Byte-for-byte comparison of the GDScript rasterizer (MechPartRenderer's
# _rasterize_polygon/_rasterize_line/_add_outline) against the Rust port
# (rust_ext's PartRasterizer.rasterize), on identical input - the benchmarks
# only prove speed and that it "doesn't crash", not that the reimplemented
# point-in-polygon/outline logic actually produces the same pixels. Safe to
# delete once validated.

const MechPartRenderer = preload("res://scripts/visuals/MechPartRenderer.gd")

func _ready():
	if not ClassDB.class_exists("PartRasterizer"):
		push_error("PartRasterizer not found - rust_ext not loaded.")
		get_tree().quit(1)
		return

	var base_poly = PackedVector2Array([
		Vector2(-15, -20), Vector2(15, -20), Vector2(18, 0),
		Vector2(12, 20), Vector2(-12, 20), Vector2(-18, 0)
	])

	var fill_regions: Array = []
	for cfg in [[0.0, 1.0], [2.0, 0.6], [-2.0, 0.8]]:
		var dx = cfg[0]
		var alpha = cfg[1]
		var shifted = PackedVector2Array()
		for p in base_poly:
			shifted.append(Vector2(p.x + dx, p.y))
		fill_regions.append({"polygon": shifted, "color": Color(0.6, 0.7, 0.9, alpha)})
	var line_regions: Array = [
		{"a": Vector2(-15, -20), "b": Vector2(15, 20), "color": Color(1.0, 1.0, 1.0, 1.0), "width": 1.5}
	]
	var outline_color = Color(0.05, 0.05, 0.08, 1.0)

	# --- GDScript path (force it by calling the private methods directly,
	# same as finish()'s fallback branch) ---
	var gd_renderer = MechPartRenderer.new()
	var gd_img = Image.create(MechPartRenderer.GRID_DIM, MechPartRenderer.GRID_DIM, false, Image.FORMAT_RGBA8)
	gd_img.fill(Color(0, 0, 0, 0))
	for region in fill_regions:
		gd_renderer._rasterize_polygon(gd_img, region.polygon, region.color)
	for line in line_regions:
		gd_renderer._rasterize_line(gd_img, line.a, line.b, line.color, line.width)
	gd_renderer._add_outline(gd_img)
	var gd_bytes = gd_img.get_data()
	gd_renderer.free()

	# --- Rust path ---
	var rasterizer = ClassDB.instantiate("PartRasterizer")
	var rust_bytes = rasterizer.rasterize(fill_regions, line_regions, outline_color)

	print("GDScript bytes: ", gd_bytes.size(), "  Rust bytes: ", rust_bytes.size())

	if gd_bytes.size() != rust_bytes.size():
		push_error("SIZE MISMATCH: %d vs %d" % [gd_bytes.size(), rust_bytes.size()])
		get_tree().quit(1)
		return

	var mismatches = 0
	var first_mismatch_idx = -1
	for i in range(gd_bytes.size()):
		if gd_bytes[i] != rust_bytes[i]:
			mismatches += 1
			if first_mismatch_idx == -1:
				first_mismatch_idx = i

	if mismatches == 0:
		print("PIXEL-PERFECT MATCH: all %d bytes identical between GDScript and Rust rasterizers." % gd_bytes.size())
	else:
		var pct = 100.0 * float(mismatches) / float(gd_bytes.size())
		push_error("MISMATCH: %d/%d bytes differ (%.2f%%), first at byte %d (cell %d,%d channel %d). GD=%d Rust=%d" % [
			mismatches, gd_bytes.size(), pct, first_mismatch_idx,
			(first_mismatch_idx / 4) % MechPartRenderer.GRID_DIM, (first_mismatch_idx / 4) / MechPartRenderer.GRID_DIM, first_mismatch_idx % 4,
			gd_bytes[first_mismatch_idx], rust_bytes[first_mismatch_idx]
		])

	get_tree().quit()
