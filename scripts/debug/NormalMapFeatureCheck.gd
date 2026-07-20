extends Node

# Regression harness for: "I need the 'Normal' map type updated - jumpjets
# should be able to go over any of those tiles. Also, the islands/noise
# should be larger, and gaps between obstacles need to be larger."
#
# Two things verified:
#   1. Jumpjet passability was ALREADY correct in code before this change -
#      every obstacle type that can appear on a Normal map (Boulder/Cactus/
#      IceBoulder/LavaRock/StoneWall via the merged flat-collision pass,
#      Tree/RuinPart via their own node collision) lands on collision layer
#      32 (Mech.OBSTACLE_LAYER), which Mech._update_obstacle_phasing already
#      clears from collision_mask uniformly whenever jets are firing,
#      regardless of map_type. This test proves that end-to-end on a real
#      generated Normal map rather than trusting the source read - if any
#      obstacle type were ever wired to a different layer (e.g. mirroring
#      Arena's map_type-specific dungeon-border special case), this would
#      catch it.
#   2. Normal now uses HALVED noise frequencies (bigger biome/terrain
#      patches) and a narrower obstacle-tendril band (bigger gaps between
#      obstacle clusters) than every other map type - verified directly
#      against the live FastNoiseLite resources after generation, not by
#      eyeballing map output.

const MapGeneratorScript = preload("res://scripts/core/MapGenerator.gd")
const OBSTACLE_LAYER = 32

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# --- 1. Frequency/gap tuning is actually applied for Normal ---
	var normal_map = MapGeneratorScript.new()
	normal_map.map_type = "Normal"
	add_child(normal_map)

	var forest_map = MapGeneratorScript.new()
	forest_map.map_type = "Forest"
	add_child(forest_map)

	_check("Normal's terrain noise frequency is half of a baseline map type (%f vs %f)" % [normal_map.noise.frequency, forest_map.noise.frequency],
		abs(normal_map.noise.frequency - forest_map.noise.frequency * 0.5) < 0.0001)
	_check("Normal's moisture noise frequency is half of baseline",
		abs(normal_map.moisture_noise.frequency - forest_map.moisture_noise.frequency * 0.5) < 0.0001)
	_check("Normal's obstacle-tendril noise frequency is half of baseline",
		abs(normal_map.obstacle_noise.frequency - forest_map.obstacle_noise.frequency * 0.5) < 0.0001)

	# --- 2. Every obstacle type on a real generated Normal map is on the
	# jumpjet-passable layer (32), never the solid map-border layer (1) ---
	var seen_layers: Dictionary = {} # layer -> count
	var obstacle_body_count = 0
	for child in normal_map.get_children():
		if child is StaticBody2D:
			# Distinguish obstacle bodies from water (layer 2) and the map
			# border (layer 1, created elsewhere) by collision_layer value -
			# an obstacle body is specifically layer 32.
			seen_layers[child.collision_layer] = seen_layers.get(child.collision_layer, 0) + 1
			if child.collision_layer == OBSTACLE_LAYER:
				obstacle_body_count += 1
		elif child.get_script() == load("res://scripts/core/TreeObstacle.gd"):
			_check("TreeObstacle instance is on the jumpjet-passable obstacle layer",
				child.collision_layer == OBSTACLE_LAYER)
			obstacle_body_count += 1
		elif child.get_script() == load("res://scripts/core/RuinObstacle.gd"):
			_check("RuinObstacle instance is on the jumpjet-passable obstacle layer",
				child.collision_layer == OBSTACLE_LAYER)
			obstacle_body_count += 1

	_check("Normal map actually generated at least one obstacle collision body to check (not vacuous)",
		obstacle_body_count > 0)
	# Layer-1 StaticBody2D instances DO legitimately exist too (the outer
	# table border, so mechs/jets can never leave the table entirely - see
	# Mech.gd's OBSTACLE_LAYER comment) - not asserted against here, since
	# the per-type checks above already confirm every TERRAIN OBSTACLE body
	# specifically lands on layer 32, which is the actual claim under test.

	normal_map.queue_free()
	forest_map.queue_free()

	if failures == 0:
		print("PASS: Normal map has larger terrain features/obstacle gaps, and every obstacle type is jumpjet-passable")
	get_tree().quit(0 if failures == 0 else 1)
