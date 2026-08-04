extends Node

# Instrumentation for the "MechRenderer's Geometry2D.merge_polygons
# silhouette union" Rust-port candidate flagged in Status.md's Phase 4
# backlog - measures the REAL cache-miss cost of
# MechRenderer._get_component_polygon() across realistic hex-cluster sizes
# before committing to a Rust port, same "gate on the real number"
# discipline used throughout the AI-tactics-cutover plan. The function is a
# pure computation of comp.valid_hexes + scale_mult (no Node dependency -
# same precedent MechRendererPolygonCacheCheck.gd already established),
# called directly here on a bare, un-added MechRenderer instance.
#
# Two shapes tested at each size: a compact "blob" (BFS ring expansion from
# origin - the common case) and a "line" (worst-case candidate: many
# hexes that only ever touch one neighbor, which could force more merge
# passes before the union stabilizes) - the design notes call out "long
# limbed" torsos as a real, common shape family, not just an edge case.

const MechRendererScript = preload("res://scripts/visuals/MechRenderer.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const HexCoordScript = preload("res://scripts/core/HexCoord.gd")

const SIZES = [6, 12, 20, 30, 45]
const TRIALS = 5

# Standard axial hex neighbor offsets.
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

func _ready():
	var renderer = MechRendererScript.new()

	for shape_name in ["blob", "line"]:
		print("--- %s shape ---" % shape_name)
		for n in SIZES:
			var hexes = _blob_hexes(n) if shape_name == "blob" else _line_hexes(n)
			var comp = ComponentEquipmentScript.new()
			comp.valid_hexes = hexes

			var samples: Array = []
			for t in range(TRIALS):
				MechRendererScript._component_polygon_cache.clear() # force a fresh cache miss every trial
				var t0 = Time.get_ticks_usec()
				renderer._get_component_polygon(comp, 1.0)
				samples.append((Time.get_ticks_usec() - t0) / 1000.0) # ms

			var steady = samples.slice(1) # discard trial 1 as warmup, same convention as every other benchmark this session
			var mean = 0.0
			for s in steady:
				mean += s
			mean /= steady.size()
			print("    %d hexes: %s ms  (mean steady-state: %.4f ms)" % [n, samples, mean])

	MechRendererScript._component_polygon_cache.clear()
	get_tree().quit(0)
