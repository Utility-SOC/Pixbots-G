extends Node

# Real in-engine GDScript timing for MechPartRenderer.finish()'s actual
# rasterization work (_rasterize_polygon/_rasterize_line/_add_outline) -
# the function identified as the real enemy-spawn hot path, as opposed to
# RustBenchComparison.gd's generate_procedural_shape() (which turned out to
# only run for loot/Black Market, not enemy spawns - see rust_poc/README.md).
# Matches the exact synthetic region data PartRasterizer.run_benchmark()
# uses in rust_ext/src/part_rasterizer.rs, for a fair comparison.
#
# HOW TO RUN: same pattern as RustBenchComparison.gd.

const MechPartRenderer = preload("res://scripts/visuals/MechPartRenderer.gd")

func _ready():
	var base_poly = PackedVector2Array([
		Vector2(-15, -20), Vector2(15, -20), Vector2(18, 0),
		Vector2(12, 20), Vector2(-12, 20), Vector2(-18, 0)
	])

	var iterations = 10000
	var t0 = Time.get_ticks_usec()

	for i in range(iterations):
		var renderer = MechPartRenderer.new()
		for cfg in [[0.0, 1.0], [2.0, 0.6], [-2.0, 0.8]]:
			var dx = cfg[0]
			var alpha = cfg[1]
			var shifted = PackedVector2Array()
			for p in base_poly:
				shifted.append(Vector2(p.x + dx, p.y))
			renderer.add_fill(shifted, Color(0.6, 0.7, 0.9, alpha))
		renderer.add_line(Vector2(-15, -20), Vector2(15, 20), Color(1.0, 1.0, 1.0, 1.0), 1.5)
		renderer.finish()
		renderer.free()

	var elapsed = (Time.get_ticks_usec() - t0) / 1000000.0
	# finish() silently routes to the Rust PartRasterizer when the extension
	# is loaded - report which backend actually ran, or the number is
	# meaningless as a comparison.
	var backend = "Rust (via finish() auto-detect)" if ClassDB.class_exists("PartRasterizer") else "GDScript"
	print("%s: %d part rasterizations in %.4fs (%.2f us/part)" % [
		backend, iterations, elapsed, elapsed * 1000000.0 / iterations
	])

	get_tree().quit()
