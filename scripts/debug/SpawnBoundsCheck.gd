extends Node

# Regression harness for the "enemies/extraction off map" playtest report.
# Root cause: Main._spawn_extraction_marker() computed player.global_position
# + a random 600-1500px offset with NO clamp to the map's bounds before
# calling MapGenerator.get_valid_spawn_position() - a player standing near
# any edge could get an extraction marker placed genuinely off the map, and
# the old spiral search (which started from an out-of-bounds tile origin)
# collapsed to a single clamped boundary column/row and could fail
# entirely, falling back to the unclamped input verbatim. "Follow
# indicator" then led the player off the map, with chasing enemies in tow.
#
# Fixed two ways: _spawn_extraction_marker now pre-clamps like
# _spawn_wave_async already did, AND get_valid_spawn_position itself now
# clamps its search origin and its last-resort fallback - so EVERY caller
# (extraction marker, Traveling Champion, boss/player teleports, ...) is
# protected regardless of whether it remembers to pre-clamp.

const MapGeneratorScript = preload("res://scripts/core/MapGenerator.gd")

func _in_bounds(pos: Vector2, map) -> bool:
	var map_w = map.width * map.tile_size
	var map_h = map.height * map.tile_size
	return pos.x >= 0.0 and pos.x <= map_w and pos.y >= 0.0 and pos.y <= map_h

func _ready():
	var failures = 0
	var world = Node2D.new()
	add_child(world)

	var map = MapGeneratorScript.new()
	map.map_type = "Open Field" # simple, fully-clear biome - isolates the bounds math from obstacle placement
	world.add_child(map)
	map._generate_map() # also populates main_continent_tiles (_has_spawn_clearance's data source)

	var map_w = map.width * map.tile_size
	var map_h = map.height * map.tile_size
	print("1) map generated: %dx%d tiles (%dx%d px)" % [map.width, map.height, map_w, map_h])

	# --- 1. Wildly out-of-bounds inputs never come back out-of-bounds ------
	var wild_inputs = [
		Vector2(-5000, -5000),
		Vector2(map_w + 5000, map_h + 5000),
		Vector2(-2000, map_h * 0.5),
		Vector2(map_w * 0.5, -2000),
		Vector2(map_w + 2000, map_h * 0.5),
	]
	var all_clamped = true
	for wi in wild_inputs:
		var result = map.get_valid_spawn_position(wi)
		if not _in_bounds(result, map):
			push_error("FAIL: get_valid_spawn_position(%s) returned out-of-bounds %s" % [wi, result])
			all_clamped = false
			failures += 1
	if all_clamped:
		print("2) get_valid_spawn_position never returns an out-of-bounds result, even for wildly off-map inputs")

	# --- 2. In-bounds, clear input is returned UNCHANGED (no regression to
	# the normal/common case) -------------------------------------------
	var normal_input = Vector2(map_w * 0.5, map_h * 0.5)
	var normal_result = map.get_valid_spawn_position(normal_input)
	if normal_result != normal_input:
		push_error("FAIL: a normal in-bounds+clear position got needlessly moved (%s -> %s)" % [normal_input, normal_result])
		failures += 1
	else:
		print("3) an already-valid in-bounds position is returned unchanged (no behavior change for the common case)")

	# --- 3. Extraction marker: player near an edge + a large offset must
	# still land in-bounds ---------------------------------------------
	var edge_positions = [
		Vector2(50, map_h * 0.5),          # hugging the left wall
		Vector2(map_w - 50, map_h * 0.5),  # hugging the right wall
		Vector2(map_w * 0.5, 50),          # hugging the top wall
		Vector2(map_w * 0.5, map_h - 50),  # hugging the bottom wall
	]
	var extraction_ok = true
	for player_pos in edge_positions:
		for trial in range(20): # many random offsets per edge, matching the real 600-1500px/4-quadrant roll
			var offset = Vector2(randf_range(600, 1500), randf_range(600, 1500))
			if randf() > 0.5: offset.x *= -1
			if randf() > 0.5: offset.y *= -1
			var target_pos = player_pos + offset
			var inset = 96.0
			target_pos.x = clamp(target_pos.x, inset, map_w - inset)
			target_pos.y = clamp(target_pos.y, inset, map_h - inset)
			var final_pos = map.get_valid_spawn_position(target_pos)
			if not _in_bounds(final_pos, map):
				push_error("FAIL: extraction marker from player@%s, offset %s landed out of bounds at %s" % [player_pos, offset, final_pos])
				extraction_ok = false
				failures += 1
	if extraction_ok:
		print("4) extraction marker placement stays in-bounds for a player hugging any of the 4 edges, across many random offsets")

	if failures == 0:
		print("PASS: spawn/extraction positions can never land off the map")
	get_tree().quit(0 if failures == 0 else 1)
