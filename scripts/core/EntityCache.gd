extends Node

# Autoload: per-frame cached snapshots of node groups that hot paths scan
# repeatedly (enemies, loot, projectiles, jammer fields...). Godot's
# get_nodes_in_group() builds a fresh array on every call; with 80 enemies
# and half a dozen systems scanning per frame (magnet pull, drone targeting,
# sight checks, minimap, heal pulses) that's the same walk + allocation done
# over and over. This trades all of that for at most ONE walk per group per
# frame.
#
# CALLER CONTRACT: entries can be freed after the snapshot is taken (e.g. an
# enemy that died earlier this same frame), so every loop over get_group()'s
# result MUST skip !is_instance_valid(node) entries - same guard most call
# sites already had.

var _cache: Dictionary = {} # group (StringName) -> Array of nodes
var _stamp: int = -1

func get_group(group: StringName) -> Array:
	# _process and _physics_process interleave arbitrarily; fold both frame
	# counters into one stamp so the cache invalidates whenever either side
	# advances, and a physics tick never reuses last render-frame's snapshot.
	var stamp = (int(Engine.get_physics_frames()) << 20) | (int(Engine.get_process_frames()) & 0xFFFFF)
	if stamp != _stamp:
		_stamp = stamp
		_cache.clear()
	if not _cache.has(group):
		_cache[group] = get_tree().get_nodes_in_group(group)
	return _cache[group]
