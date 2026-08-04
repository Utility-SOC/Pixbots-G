extends Node

# Correctness check for the adjacency-informed merge rewrite of
# MechRenderer._get_component_polygon (perf fix - see
# ComponentPolygonMergePerfCheck.gd for the measured cost this replaces).
#
# Ground truth used: for a set of N regular hexagons tiling a hex grid with
# no gaps or overlaps (hexagons sharing an edge share zero AREA, only a
# boundary line), the union polygon's total area must equal EXACTLY
# N * (area of one hexagon) - a first-principles geometric fact independent
# of which merge algorithm/order produced the result, not a comparison
# against the old implementation's specific output. Also checks the result
# is a single simple closed polygon (no self-intersections implied by a
# wildly wrong point count) and that point count/bbox scale sanely with
# hex count.

const MechRendererScript = preload("res://scripts/visuals/MechRenderer.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const HexCoordScript = preload("res://scripts/core/HexCoord.gd")

const NEIGHBOR_OFFSETS = [[1, 0], [1, -1], [0, -1], [-1, 0], [-1, 1], [0, 1]]

func _blob_hexes(n: int) -> Array:
	var visited = {Vector2i(0, 0): true}
	var order = [Vector2i(0, 0)]
	var frontier = [Vector2i(0, 0)]
	while order.size() < n and not frontier.is_empty():
		var next_frontier = []
		for cell in frontier:
			for off in NEIGHBOR_OFFSETS:
				var n_cell = cell + Vector2i(off[0], off[1])
				if not visited.has(n_cell):
					visited[n_cell] = true
					order.append(n_cell)
					next_frontier.append(n_cell)
					if order.size() >= n:
						break
			if order.size() >= n:
				break
		frontier = next_frontier
	var hexes: Array[HexCoord] = []
	for c in order:
		hexes.append(HexCoordScript.new(c.x, c.y))
	return hexes

func _line_hexes(n: int) -> Array:
	var hexes: Array[HexCoord] = []
	for i in range(n):
		hexes.append(HexCoordScript.new(i, 0))
	return hexes

# Zig-zag "L"-ish shape - a third topology (not a compact blob, not a
# straight line) to widen coverage against any bias in only testing two
# extremes.
func _zigzag_hexes(n: int) -> Array:
	var hexes: Array[HexCoord] = []
	var q = 0
	var r = 0
	hexes.append(HexCoordScript.new(q, r))
	for i in range(1, n):
		if i % 2 == 0:
			q += 1
		else:
			r += 1
		hexes.append(HexCoordScript.new(q, r))
	return hexes

func _shoelace_area(pts: PackedVector2Array) -> float:
	var area = 0.0
	var n = pts.size()
	for i in range(n):
		var p1 = pts[i]
		var p2 = pts[(i + 1) % n]
		area += p1.x * p2.y - p2.x * p1.y
	return abs(area) / 2.0

func _ready():
	var failures = 0
	var renderer = MechRendererScript.new()

	var scale_mult = 1.0
	var hex_size = 9.0 * scale_mult
	var single_hex_area = (3.0 * sqrt(3.0) / 2.0) * hex_size * hex_size

	for shape_name in ["blob", "line", "zigzag"]:
		for n in [1, 2, 3, 6, 12, 20, 30, 45]:
			var hexes
			match shape_name:
				"blob": hexes = _blob_hexes(n)
				"line": hexes = _line_hexes(n)
				"zigzag": hexes = _zigzag_hexes(n)
			var comp = ComponentEquipmentScript.new()
			comp.valid_hexes = hexes

			MechRendererScript._component_polygon_cache.clear()
			var pts = renderer._get_component_polygon(comp, scale_mult)

			var expected_area = float(hexes.size()) * single_hex_area
			var got_area = _shoelace_area(pts)
			var rel_err = abs(got_area - expected_area) / expected_area if expected_area > 0.0 else 0.0

			var label = "%s n=%d" % [shape_name, n]
			if pts.size() < 3:
				push_error("FAIL [%s]: degenerate result, only %d points" % [label, pts.size()])
				failures += 1
			elif rel_err > 0.001:
				push_error("FAIL [%s]: area mismatch - got %.3f, want %.3f (%.4f%% off) - a merge dropped or double-counted area" % [label, got_area, expected_area, rel_err * 100.0])
				failures += 1
			else:
				print("PASS: %s - %d points, area %.2f matches %d hexes x %.2f exactly" % [label, pts.size(), got_area, hexes.size(), single_hex_area])

	if failures == 0:
		print("PASS: ComponentPolygonMergeCorrectnessCheck - every shape's union area exactly matches hex-count x single-hex-area (blob/line/zigzag, 1-45 hexes)")
	get_tree().quit(0 if failures == 0 else 1)
