extends Node

# Perf fix for the 2 FPS enemy-wave-spawn hitch investigated in
# MechPhysicsCostDiagnostic.gd: MechRenderer._get_component_polygon() ran an
# expensive iterative Geometry2D.merge_polygons union loop (up to
# O(n^2-3) merge attempts, not O(n)) 4x per mech, every single spawn, even
# though the result depends ONLY on comp.valid_hexes + scale_mult and is
# identical across every mech sharing the same component archetype (the
# common case - a whole wave of the same enemy template). Now cached,
# keyed by the hex layout's own content (not an assumed "same rarity = same
# shape", since higher-rarity components can have procedurally-varied
# shapes) so it's correct even when two components of the same slot/rarity
# happen to differ.

const MechRendererScript = preload("res://scripts/visuals/MechRenderer.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")
const HexCoordScript = preload("res://scripts/core/HexCoord.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# NOT add_child()'d - MechRenderer._ready() unconditionally calls
	# _rebuild_visuals(), which expects a real Mech parent (weapon mounts,
	# hitbox wiring, etc.). _get_component_polygon() itself is a pure
	# function of comp.valid_hexes/scale_mult with no dependency on the
	# node being in the tree, so calling it directly on an unattached
	# instance is safe and avoids dragging in the whole render pipeline.
	var renderer = MechRendererScript.new()

	# --- Cache correctness: same layout -> identical result, cache hit ---
	MechRendererScript._component_polygon_cache.clear()

	var comp_a = ComponentEquipmentScript.new()
	var hexes_a: Array[HexCoord] = [HexCoordScript.new(0, 0), HexCoordScript.new(1, 0), HexCoordScript.new(0, 1)]
	comp_a.valid_hexes = hexes_a

	var pts1 = renderer._get_component_polygon(comp_a, 1.0)
	_check("first call actually computes a real polygon", pts1.size() > 0)
	_check("first call populates the cache", MechRendererScript._component_polygon_cache.size() == 1)

	var pts2 = renderer._get_component_polygon(comp_a, 1.0)
	_check("second call with the identical layout still returns %d points" % pts1.size(), pts2.size() == pts1.size())
	var all_equal = true
	for i in range(pts1.size()):
		if pts1[i] != pts2[i]:
			all_equal = false
	_check("cached result is point-for-point identical to the freshly computed one", all_equal)
	_check("second call reuses the cache entry instead of adding a new one", MechRendererScript._component_polygon_cache.size() == 1)

	# --- Cache correctness: DIFFERENT layout -> separate cache entry, not a collision ---
	var comp_b = ComponentEquipmentScript.new()
	var hexes_b: Array[HexCoord] = [HexCoordScript.new(0, 0), HexCoordScript.new(-1, 0), HexCoordScript.new(0, -1)]
	comp_b.valid_hexes = hexes_b
	var pts3 = renderer._get_component_polygon(comp_b, 1.0)
	_check("a different hex layout gets its own cache entry (2 total now)",
		MechRendererScript._component_polygon_cache.size() == 2)

	# Same coordinates, different scale_mult - also must NOT collide (the
	# cache key includes scale_mult specifically for this reason).
	var pts4 = renderer._get_component_polygon(comp_a, 2.0)
	_check("the same layout at a different scale_mult also gets its own cache entry (3 total)",
		MechRendererScript._component_polygon_cache.size() == 3)
	_check("a bigger scale_mult actually produces a bigger polygon", pts4.size() > 0 and _bbox_area(pts4) > _bbox_area(pts1))

	# --- Safety: returned arrays are independent copies, not shared references ---
	var pts5 = renderer._get_component_polygon(comp_a, 1.0) # cache hit
	if pts5.size() > 0:
		pts5[0] = Vector2(999999, 999999) # mutate the caller's copy
	var pts6 = renderer._get_component_polygon(comp_a, 1.0) # fresh fetch from cache
	_check("mutating a returned polygon never corrupts the cached original (duplicate() on every hit)",
		pts6.size() == 0 or pts6[0] != Vector2(999999, 999999))

	# --- Real-world speedup: second mech sharing the same starter-torso
	# archetype should spawn dramatically faster than the first (cache miss
	# vs cache hit), matching what actually happens across a real enemy wave.
	MechRendererScript._component_polygon_cache.clear()
	var t0 = Time.get_ticks_usec()
	var mech1 = MechScript.new()
	mech1.is_player = false
	mech1.equip_component(ComponentEquipmentScript.create_starter_torso())
	add_child(mech1)
	var t1 = Time.get_ticks_usec()
	var mech2 = MechScript.new()
	mech2.is_player = false
	mech2.equip_component(ComponentEquipmentScript.create_starter_torso())
	add_child(mech2)
	var t2 = Time.get_ticks_usec()
	var first_spawn_us = t1 - t0
	var second_spawn_us = t2 - t1
	print("first spawn (cache miss): %d us, second spawn (cache hit): %d us" % [first_spawn_us, second_spawn_us])
	_check("a second mech with the same starter-torso archetype spawns meaningfully faster than the first (cache actually engaging)",
		second_spawn_us < first_spawn_us * 0.5)
	mech1.queue_free()
	mech2.queue_free()

	if failures == 0:
		print("PASS: MechRenderer's component-silhouette polygon is cached by hex-layout content, correct and safe, and measurably speeds up repeat spawns of the same archetype")
	get_tree().quit(0 if failures == 0 else 1)

func _bbox_area(pts: PackedVector2Array) -> float:
	if pts.is_empty():
		return 0.0
	var min_p = pts[0]
	var max_p = pts[0]
	for p in pts:
		min_p = Vector2(min(min_p.x, p.x), min(min_p.y, p.y))
		max_p = Vector2(max(max_p.x, p.x), max(max_p.y, p.y))
	return (max_p.x - min_p.x) * (max_p.y - min_p.y)
