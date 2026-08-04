extends Node

# Regression harness for Phase 3 of the AI-tactics Rust-cutover plan (see
# C:\Users\Utility\.claude\plans\effervescent-drifting-kazoo.md) -
# FlowFieldRs.rebuild() vs MapGenerator._rebuild_flow_field_fallback's
# GDScript BFS. Unlike Phase 1/2's soft-heuristic approximations, flow-field
# routing is navigation-affecting - this must be BYTE-IDENTICAL, not just
# "close enough," so this check asserts exact cell-set and exact-direction
# agreement, not a tolerance-based comparison.
#
# Runs both paths through the REAL _rebuild_flow_field() entrypoint (not a
# reimplementation of its dispatch logic) - toggling _flow_field_rasterizer
# to null/back forces the fallback vs. Rust branch, same production code
# either way.

const MapGeneratorScript = preload("res://scripts/core/MapGenerator.gd")

func _ready():
	var failures = 0
	for map_type in ["Forest", "Volcano", "Normal", "Tabletop"]:
		var map = MapGeneratorScript.new()
		map.map_type = map_type
		add_child(map) # _ready() generates synchronously
		failures += _check_map(map, map_type)
		map.queue_free()
		await get_tree().process_frame

	if failures == 0:
		print("PASS: FlowFieldParityCheck - Rust and GDScript BFS produce byte-identical flow fields")
	get_tree().quit(0 if failures == 0 else 1)

func _check_map(map: MapGenerator, label: String) -> int:
	map._ensure_flow_field_rust()
	if not map._flow_field_rasterizer:
		print("SKIPPED [%s]: FlowFieldRs not built (DLL missing)" % label)
		return 0
	var real_rasterizer = map._flow_field_rasterizer

	# A few representative target cells - map center plus two off-center
	# points - to exercise different neighborhoods/obstacle layouts, not
	# just one lucky spot.
	var candidates = [
		Vector2i(map.width / 2, map.height / 2),
		Vector2i(map.width / 4, map.height / 4),
		Vector2i(3 * map.width / 4, 3 * map.height / 4),
	]

	var local_failures = 0
	for target_cell in candidates:
		if map.astar_grid.is_point_solid(target_cell):
			print("    [%s @ %s]: solid target, both paths trivially produce an empty field - skipped" % [label, target_cell])
			continue

		map._flow_field_rasterizer = real_rasterizer
		map._flow_field_grid_obstacle_count = -1 # force a fresh solidity buffer build
		map._rebuild_flow_field(target_cell)
		var rust_field: Dictionary = map.flow_field.duplicate()

		map._flow_field_rasterizer = null # forces the fallback branch of the real dispatcher
		map._rebuild_flow_field(target_cell)
		var fallback_field: Dictionary = map.flow_field.duplicate()
		map._flow_field_rasterizer = real_rasterizer

		if rust_field.size() != fallback_field.size():
			push_error("FAIL [%s @ %s]: field size mismatch - rust=%d fallback=%d" % [label, target_cell, rust_field.size(), fallback_field.size()])
			local_failures += 1
			continue

		var mismatches = 0
		for cell in fallback_field.keys():
			if not rust_field.has(cell):
				mismatches += 1
				continue
			var rd: Vector2 = rust_field[cell]
			var fd: Vector2 = fallback_field[cell]
			if rd.distance_to(fd) > 0.0001:
				mismatches += 1
		if mismatches > 0:
			push_error("FAIL [%s @ %s]: %d cell(s) disagree between rust and fallback (of %d total)" % [label, target_cell, mismatches, fallback_field.size()])
			local_failures += 1
		else:
			print("PASS [%s @ %s]: %d cells, byte-identical" % [label, target_cell, fallback_field.size()])

	return local_failures
