class_name HexGridComponent
extends Node

# Maps Vector2i(q, r) -> HexTile
var grid: Dictionary = {}

# Emitted after any add_tile/remove_tile. Mech listens (player only) to queue
# a coalesced visual redraw.
signal changed

# Per-tile energy flow from the last full energy-routing pass (Mech.
# _simulate_energy_flow): Vector2i(anchor q, r) -> {"visits", "energy", "dom"}.
# Tiles missing from it never received any energy ("unpowered").
var flow: Dictionary = {}
# Anchors of tiles where energy recirculates (same face entered on many
# different steps) - e.g. an Infuser in a ring that re-adds to its own stream.
var flow_loops: Dictionary = {}
# True when packets were still alive at the sim step cap.
var sim_saturated: bool = false
# Set once a full pass has completed since the last reset (distinguishes "nothing
# powered" from "never simulated").
var flow_ready: bool = false

func reset_flow() -> void:
	flow.clear()
	flow_loops.clear()
	sim_saturated = false
	flow_ready = false

func record_flow(key: Vector2i, visits: float, energy: float, dom: int, looped: bool) -> void:
	var f = flow.get(key)
	if f == null:
		flow[key] = {"visits": visits, "energy": energy, "dom": dom}
	else:
		f["visits"] += visits
		f["energy"] += energy
		if dom >= 0:
			f["dom"] = dom
	if looped:
		flow_loops[key] = true

func is_powered(key: Vector2i) -> bool:
	return flow.has(key)

# NOTE: process_durability() is defined on the HexTile base class itself
# (scripts/core/HexTile.gd), so every tile in `grid` has it - the old code
# called tile.has_method("process_durability") here on every tile, every
# frame, for every mech on the field. has_method() is a reflective lookup
# and was pure overhead since the check could never be false; call directly.
func _process(delta: float):
	for key in grid:
		grid[key].process_durability(delta)

func has_tile(coord) -> bool:
	if typeof(coord) == TYPE_OBJECT and coord is HexCoord:
		return grid.has(Vector2i(coord.q, coord.r))
	elif typeof(coord) == TYPE_VECTOR2I:
		return grid.has(coord)
	return false

func get_tile(arg1, arg2 = null) -> HexTile:
	if typeof(arg1) == TYPE_OBJECT and arg1 is HexCoord:
		var key = Vector2i(arg1.q, arg1.r)
		if grid.has(key): return grid[key]
	elif typeof(arg1) == TYPE_VECTOR2I:
		if grid.has(arg1): return grid[arg1]
	elif arg2 != null:
		var key = Vector2i(int(arg1), int(arg2))
		if grid.has(key): return grid[key]
	return null

# Multi-cell tiles (HexTile.footprint_offsets - see LanceMountTile.gd, the
# only tile that currently sets it) are stored by writing the SAME tile
# object reference into `grid` at the anchor coord AND every
# `anchor + offset` key - empty for every other tile, so this is a no-op
# for the single-cell case that's been true all along.
func add_tile(coord: HexCoord, tile: HexTile):
	tile.grid_position = coord
	var anchor = Vector2i(coord.q, coord.r)
	grid[anchor] = tile
	for off in tile.footprint_offsets:
		grid[anchor + off] = tile
	changed.emit()

# Footprint-aware regardless of WHICH of a multi-cell tile's keys gets
# passed in - resolves to the tile's own anchor (grid_position) and erases
# every key it occupies, so every existing call site (right-click removal,
# scrap/sell, move-tile logic) stays correct without having to know or care
# that multi-cell tiles exist at all.
func remove_tile(coord: HexCoord) -> HexTile:
	var key = Vector2i(coord.q, coord.r)
	if not grid.has(key):
		return null
	var tile = grid[key]
	grid.erase(key)
	if tile.footprint_offsets.size() > 0 and tile.grid_position:
		var anchor = Vector2i(tile.grid_position.q, tile.grid_position.r)
		# The anchor itself, not just the offset cells - removal via a
		# NON-anchor footprint cell (e.g. right-clicking the far end of a
		# Lance) would otherwise erase every key except the anchor.
		if grid.has(anchor) and grid[anchor] == tile:
			grid.erase(anchor)
		for off in tile.footprint_offsets:
			var k2 = anchor + off
			if grid.has(k2) and grid[k2] == tile:
				grid.erase(k2)
	changed.emit()
	return tile

# Deduped by object identity - a multi-cell tile occupies several `grid`
# keys but is still exactly ONE logical tile, and every caller here (visual
# drawing, save/serialize, body-slot assignment, loot/starter-pool
# enumeration...) wants "list every tile once," not "list every occupied
# hex."
func get_all_tiles() -> Array[HexTile]:
	var seen: Dictionary = {} # instance id -> true
	var tiles: Array[HexTile] = []
	for key in grid:
		var t = grid[key]
		var id = t.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		tiles.append(t)
	return tiles

