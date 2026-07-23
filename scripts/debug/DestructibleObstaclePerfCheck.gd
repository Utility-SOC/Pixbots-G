extends Node

# Perf sanity check for task #17: routing Boulder/Cactus/IceBoulder/LavaRock/
# StoneWall through per-tile DestructibleObstacle nodes gives up the row-
# merged flat-collision optimization for those tags specifically (see
# MapGenerator._build_collisions_and_obstacles's header comment: dense
# biomes can have thousands of these tiles - that's exactly what the merge
# was built to avoid). Volcano is the densest non-Forest obstacle biome
# (_should_spawn_obstacle: 0.35 in-tendril chance, all mapped to LavaRock),
# so a full default-size Volcano generation is the worst case for this
# change. No prior baseline number exists to diff against, so this asserts
# a generous wall-clock ceiling rather than a tight regression bound - it's
# a "didn't fall off a cliff" check, not a tight perf budget.

const MapGeneratorScript = preload("res://scripts/core/MapGenerator.gd")
const DestructibleObstacleScript = preload("res://scripts/core/DestructibleObstacle.gd")

# Generous: real generation on this dev machine typically lands well under
# this. Meant to catch an order-of-magnitude regression, not to be a tight
# perf gate that flakes on a loaded CI runner.
const MAX_GENERATE_MSEC = 8000

func _ready():
	var failures = 0
	var start = Time.get_ticks_msec()

	var map = MapGeneratorScript.new()
	map.map_type = "Volcano"
	add_child(map) # _ready() runs full generation synchronously

	var elapsed = Time.get_ticks_msec() - start

	var lava_count = 0
	for child in map.get_children():
		if child.get_script() == DestructibleObstacleScript and child.obstacle_name == "LavaRock":
			lava_count += 1

	if lava_count == 0:
		push_error("FAIL: Volcano map generated zero LavaRock DestructibleObstacle nodes (test is vacuous)")
		failures += 1
	else:
		print("1) Volcano map generated %d LavaRock DestructibleObstacle nodes" % lava_count)

	if elapsed > MAX_GENERATE_MSEC:
		push_error("FAIL: full Volcano generation took %dms, expected under %dms" % [elapsed, MAX_GENERATE_MSEC])
		failures += 1
	else:
		print("2) full Volcano generation (%d LavaRock nodes) took %dms (ceiling %dms)" % [lava_count, elapsed, MAX_GENERATE_MSEC])

	map.queue_free()

	if failures == 0:
		print("PASS: dense per-tile destructible obstacles don't blow up generation time")
	get_tree().quit(0 if failures == 0 else 1)
