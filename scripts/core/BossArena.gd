extends RefCounted

# Authored set piece for boss fights: a ring of hard-cover pillars (2x2 StoneWall blocks, which absorb
# everything but explosives, see DestructibleObstacle) raised around the boss's spawn point through the
# TerrainEditor. The ring is open between pillars so nothing is sealed in or out, keeps clear of water,
# existing obstacles and the player's position, and is taken down again when the boss dies.

const TerrainEditorScript = preload("res://scripts/core/TerrainEditor.gd")
const PILLAR_NAME = "StoneWall"
const RING_RADIUS_TILES = 8.0
const MEGA_RING_RADIUS_TILES = 11.0
const PILLARS = 8
const MEGA_PILLARS = 12
const PLAYER_CLEAR_TILES = 6.0

# Returns {"editor", "snapshot", "cells"} or an empty dictionary when nothing could be built.
static func build(map, center_world: Vector2, player_world: Vector2, is_mega: bool = false) -> Dictionary:
	if map == null or not ("terrain" in map):
		return {}
	var ts: float = map.tile_size
	var centre = Vector2(center_world.x / ts, center_world.y / ts)
	var player_t = Vector2(player_world.x / ts, player_world.y / ts)
	var radius = MEGA_RING_RADIUS_TILES if is_mega else RING_RADIUS_TILES
	var count = MEGA_PILLARS if is_mega else PILLARS
	var editor = TerrainEditorScript.new(map)
	var span = int(ceil(radius)) + 3
	var origin = Vector2i(int(centre.x) - span, int(centre.y) - span)
	var snap = editor.snapshot(Rect2i(origin, Vector2i(span * 2 + 1, span * 2 + 1)))
	var cells: Array = []
	var phase = randf() * TAU
	for i in range(count):
		var a = phase + TAU * float(i) / float(count)
		var p = centre + Vector2(cos(a), sin(a)) * radius
		var anchor = Vector2i(int(round(p.x)), int(round(p.y)))
		if Vector2(anchor).distance_to(player_t) < PLAYER_CLEAR_TILES:
			continue
		var block: Array = []
		var ok = not _mech_near(map, Vector2((anchor.x + 1) * ts, (anchor.y + 1) * ts), ts * 3.0)
		for dy in range(2):
			for dx in range(2):
				var c = anchor + Vector2i(dx, dy)
				if not editor.in_bounds(c) or int(map.terrain[c.y][c.x]) == map.BiomeType.WATER or map.obstacles.has(c):
					ok = false
				block.append(c)
		if not ok:
			continue
		for c in block:
			editor.place_obstacle(c, PILLAR_NAME)
			cells.append(c)
	editor.commit()
	if cells.is_empty():
		return {}
	return {"editor": editor, "snapshot": snap, "cells": cells}

# Never raise a pillar on top of a mech (it would spawn embedded in solid cover).
static func _mech_near(map, world_pos: Vector2, dist: float) -> bool:
	if not map.is_inside_tree():
		return false
	for group_name in ["player", "enemy"]:
		for m in map.get_tree().get_nodes_in_group(group_name):
			if m is Node2D and m.global_position.distance_to(world_pos) < dist:
				return true
	return false

static func dismantle(arena: Dictionary) -> int:
	if arena.is_empty() or arena.get("editor") == null:
		return 0
	var n = arena["editor"].restore(arena["snapshot"])
	arena["editor"].commit()
	return n
