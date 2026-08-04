extends Node

# Regression harness for Phase 1 of the AI-tactics Rust-cutover plan (see
# C:\Users\Utility\.claude\plans\effervescent-drifting-kazoo.md) -
# SolidGridRs.batch_line_of_sight / SolidGridBatcher._line_of_sight_fallback.
# Hand-built cases against a small synthetic obstacle wall, mirroring
# ProjectileBroadphaseParityCheck.gd's structure: assert both the Rust and
# GDScript-fallback implementations agree with each other AND with the
# hand-verified expected result for each case (not just agree with each
# other, which could hide a shared bug).
#
# Deliberately does NOT test against a real PhysicsRayQueryParameters2D
# raycast - this module is an intentional behavior change (real obstacle
# occlusion, where none existed in the old mask=1-only raycasts), not a
# byte-identical port, so there's no "ground truth" physics raycast to match
# against. Correctness here means: matches hand-verified grid geometry.

const MapGeneratorScript = preload("res://scripts/core/MapGenerator.gd")
const SolidGridBatcherScript = preload("res://scripts/core/SolidGridBatcher.gd")

const TILE = 32.0
const W = 20
const H = 20

func _cell_center(cx: int, cy: int) -> Vector2:
	return Vector2((cx + 0.5) * TILE, (cy + 0.5) * TILE)

func _ready():
	var failures = 0

	# Bare MapGenerator, never added to the tree - _ready()/_generate_map()
	# never runs (Godot only calls _ready on tree entry), so this stays a
	# cheap synthetic map instead of a full procedural generation.
	var map = MapGeneratorScript.new()
	map.width = W
	map.height = H
	map.tile_size = int(TILE)
	map.obstacles = {}
	# Vertical wall: x=10, y=5..14 inclusive (10 cells tall).
	for y in range(5, 15):
		map.obstacles[Vector2i(10, y)] = "Boulder"

	var batcher = SolidGridBatcherScript.new()
	batcher._ensure_rust()
	var have_rust = batcher._rasterizer != null
	if have_rust:
		batcher._rebuild_grid(map)
	else:
		print("NOTE: SolidGridRs not built (DLL missing) - only the GDScript fallback is being tested.")

	# [from_cell, to_cell, expected_visible, label]
	var cases = [
		[Vector2i(2, 2), Vector2i(2, 18), true, "vertical line entirely left of the wall (x<10 throughout)"],
		[Vector2i(2, 9), Vector2i(18, 9), false, "horizontal line straight through the wall (y=9 is within the wall's 5..14 span)"],
		[Vector2i(2, 16), Vector2i(18, 16), true, "horizontal line below the wall (y=16, outside 5..14)"],
		[Vector2i(9, 9), Vector2i(11, 9), false, "short hop whose path crosses the solid cell (10,9) as an intermediate cell"],
		[Vector2i(2, 9), Vector2i(10, 9), true, "destination cell (10,9) is itself solid - endpoints are never tested"],
		[Vector2i(10, 9), Vector2i(2, 9), true, "start cell (10,9) is itself solid - endpoints are never tested"],
		[Vector2i(5, 5), Vector2i(5, 5), true, "degenerate same-cell query"],
	]

	for c in cases:
		var from_pos = _cell_center(c[0].x, c[0].y)
		var to_pos = _cell_center(c[1].x, c[1].y)
		var expected: bool = c[2]
		var label: String = c[3]

		var fallback_result = batcher._line_of_sight_fallback(map, from_pos, to_pos)
		if fallback_result != expected:
			push_error("FAIL [fallback] %s: got %s, want %s" % [label, fallback_result, expected])
			failures += 1

		var rust_result = expected # default so the final PASS check below is a no-op when Rust isn't built
		if have_rust:
			var rust_results = batcher._rasterizer.batch_line_of_sight([{"from": from_pos, "to": to_pos}])
			rust_result = rust_results[0]
			if rust_result != expected:
				push_error("FAIL [rust] %s: got %s, want %s" % [label, rust_result, expected])
				failures += 1
			if rust_result != fallback_result:
				push_error("FAIL [parity] %s: rust=%s fallback=%s disagree" % [label, rust_result, fallback_result])
				failures += 1

		if fallback_result == expected and rust_result == expected:
			print("PASS: %s" % label)

	# Batched multi-query call, same cases in one shot - confirms ordering is preserved.
	if have_rust:
		var batch_queries = []
		var batch_expected = []
		for c in cases:
			batch_queries.append({"from": _cell_center(c[0].x, c[0].y), "to": _cell_center(c[1].x, c[1].y)})
			batch_expected.append(c[2])
		var batch_results = batcher._rasterizer.batch_line_of_sight(batch_queries)
		if batch_results.size() != batch_expected.size():
			push_error("FAIL: batched call returned %d results, expected %d" % [batch_results.size(), batch_expected.size()])
			failures += 1
		else:
			for i in range(batch_results.size()):
				if batch_results[i] != batch_expected[i]:
					push_error("FAIL: batched call result[%d] = %s, want %s (%s)" % [i, batch_results[i], batch_expected[i], cases[i][3]])
					failures += 1
			if failures == 0:
				print("PASS: batched multi-query call preserves per-query ordering")

	# --- batch_probe_clearance (Phase 4: BossBrain._pick_retreat_dir) ---
	# [from_cell, to_cell, expected_clearance_world_units, label]. Same
	# synthetic wall (x=10, y=5..14) - hand-computed against the DDA's own
	# documented contract (distance to the world-space boundary where the
	# ray first enters a solid cell, or the full segment length if clear;
	# endpoints never tested).
	var clearance_cases = [
		[Vector2i(2, 9), Vector2i(18, 9), 240.0, "horizontal probe through the wall - clearance stops at cell x=10's left edge"],
		[Vector2i(9, 9), Vector2i(11, 9), 16.0, "short probe crossing the solid cell as an intermediate - clearance stops at cell x=10's left edge"],
		[Vector2i(2, 16), Vector2i(18, 16), 512.0, "clear probe below the wall - full segment length"],
		[Vector2i(2, 9), Vector2i(10, 9), 256.0, "probe whose destination cell is itself solid - endpoints aren't tested, full segment length"],
	]
	for c in clearance_cases:
		var from_pos = _cell_center(c[0].x, c[0].y)
		var to_pos = _cell_center(c[1].x, c[1].y)
		var expected: float = c[2]
		var label: String = c[3]

		var fallback_clearance = batcher._probe_clearance_fallback(map, from_pos, to_pos)
		if absf(fallback_clearance - expected) > 0.01:
			push_error("FAIL [fallback] %s: got %.3f, want %.3f" % [label, fallback_clearance, expected])
			failures += 1

		var rust_clearance = expected
		if have_rust:
			var rust_results = batcher._rasterizer.batch_probe_clearance([{"from": from_pos, "to": to_pos}])
			rust_clearance = rust_results[0]
			if absf(rust_clearance - expected) > 0.01:
				push_error("FAIL [rust] %s: got %.3f, want %.3f" % [label, rust_clearance, expected])
				failures += 1
			if absf(rust_clearance - fallback_clearance) > 0.01:
				push_error("FAIL [parity] %s: rust=%.3f fallback=%.3f disagree" % [label, rust_clearance, fallback_clearance])
				failures += 1

		if absf(fallback_clearance - expected) <= 0.01 and absf(rust_clearance - expected) <= 0.01:
			print("PASS: %s" % label)

	if failures == 0:
		print("PASS: SolidGridLosCheck - all cases correct%s" % (" (rust + fallback agree)" if have_rust else " (fallback only)"))
	get_tree().quit(0 if failures == 0 else 1)
