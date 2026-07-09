extends Node

# One-time validation that the rust_ext GDExtension actually loads and
# computes correctly from inside the real running game, not just `cargo
# build` succeeding in isolation. Two checks:
#  1. HexMathBench.run_benchmark() matches RustBenchComparison.gd's checksum
#     (6666667 for 5,000,000 iterations) - proves the ported math is
#     bit-for-bit faithful, not just "compiles."
#  2. PartRasterizer.run_benchmark() gives a real in-engine timing number for
#     the actual hot path (MechPartRenderer's rasterization), for a
#     real GDScript-vs-Rust comparison on the function that matters.
#
# HOW TO RUN: same pattern as RustBenchComparison.gd - attach to a Node in
# an empty scene (or use RustExtValidation.tscn if present) and run it, or
# `godot --headless scripts/debug/RustExtValidation.tscn`. Safe to delete
# once validated.

func _ready():
	if not ClassDB.class_exists("HexMathBench"):
		push_error("HexMathBench not found - rust_ext GDExtension did not load. Check rust_ext.gdextension paths and that target/debug/rust_ext.dll exists.")
		get_tree().quit(1)
		return

	var hexmath = ClassDB.instantiate("HexMathBench")
	var result = hexmath.run_benchmark(5000000)
	var checksum = result["checksum"]
	var expected_checksum = 6666667
	print("Rust (via GDExtension): %d neighbor+distance ops in %.4fs (%.2f ns/op) [checksum %d]" % [
		result["iterations"], result["elapsed_sec"], result["ns_per_op"], checksum
	])
	if checksum == expected_checksum:
		print("CHECKSUM MATCH - ported math is faithful to RustBenchComparison.gd/hexgrid.rs")
	else:
		push_error("CHECKSUM MISMATCH - expected %d, got %d. Ported logic has a bug." % [expected_checksum, checksum])

	if not ClassDB.class_exists("PartRasterizer"):
		push_error("PartRasterizer not found - rust_ext GDExtension did not load.")
		get_tree().quit(1)
		return

	var rasterizer = ClassDB.instantiate("PartRasterizer")
	var part_result = rasterizer.run_benchmark(10000)
	print("Rust (via GDExtension): %d part rasterizations in %.4fs (%.2f us/part)" % [
		part_result["iterations"], part_result["elapsed_sec"], part_result["us_per_part"]
	])

	get_tree().quit()
