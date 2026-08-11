extends Node

# Regression check for ProjectileBatchPool's Shape Blend render mode (user
# request, 2026-08-11): "what if each of the ten synergies had its own
# shape, and then when they are combined, their shape is x/y/z amount
# toward each shape, averaging total shape for the projectiles?" Tests the
# pure geometry functions directly (_ray_segment_intersection_t,
# _polygon_radius_at_angle, _build_radial_profile, _compute_blended_polygon)
# - same "test the math, not a render round-trip" reasoning as every other
# _compute_* function in ProjectileBatchPool.gd - plus the render_mode enum
# itself and the pool's own precomputed radial profiles.

const ProjectileBatchPoolScript = preload("res://scripts/entities/ProjectileBatchPool.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# --- _polygon_radius_at_angle on a known shape (unit square) ----------
	var square = PackedVector2Array([Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)])
	var r_right = ProjectileBatchPoolScript._polygon_radius_at_angle(square, 0.0)
	_check("a unit square's radius pointing straight along +X hits the right edge at exactly 1.0",
		abs(r_right - 1.0) < 0.001)
	var r_up = ProjectileBatchPoolScript._polygon_radius_at_angle(square, PI * 0.5)
	_check("a unit square's radius pointing straight along +Y hits the top edge at exactly 1.0",
		abs(r_up - 1.0) < 0.001)
	var r_corner = ProjectileBatchPoolScript._polygon_radius_at_angle(square, PI * 0.25)
	_check("a unit square's radius pointing at exactly 45 degrees hits the corner at sqrt(2)",
		abs(r_corner - sqrt(2.0)) < 0.01)

	# --- _polygon_radius_at_angle on the RAW circle (16-gon, radius 5) ----
	var raw_poly = ProjectileBatchPoolScript._get_polygon_for_synergy(0)
	var all_in_range = true
	for k in range(16):
		var a = k * TAU / 16.0
		var rad = ProjectileBatchPoolScript._polygon_radius_at_angle(raw_poly, a)
		if rad < 4.7 or rad > 5.01:
			all_in_range = false
	_check("the RAW 16-gon's sampled radius stays close to its true radius (5.0) at every angle",
		all_in_range)

	# --- _polygon_radius_at_angle handles LIGHTNING's origin-touching zigzag
	# without crashing or returning garbage (the case a naive "sort vertices
	# by their own angle" approach breaks on) ---------------------------
	var lightning_poly = ProjectileBatchPoolScript._get_polygon_for_synergy(3)
	var lightning_ok = true
	for k in range(24):
		var a = k * TAU / 24.0
		var rad = ProjectileBatchPoolScript._polygon_radius_at_angle(lightning_poly, a)
		if rad < 0.0 or is_nan(rad) or rad > 20.0:
			lightning_ok = false
	_check("LIGHTNING's self-touching zigzag polygon samples to finite, non-negative radii at every angle",
		lightning_ok)

	# --- _build_radial_profile produces the right length ------------------
	var profile = ProjectileBatchPoolScript._build_radial_profile(square, ProjectileBatchPoolScript.SHAPE_BLEND_SAMPLES)
	_check("_build_radial_profile returns exactly SHAPE_BLEND_SAMPLES samples",
		profile.size() == ProjectileBatchPoolScript.SHAPE_BLEND_SAMPLES)

	# --- _compute_blended_polygon: build real per-synergy profiles --------
	var profiles = []
	profiles.resize(10)
	for syn_idx in range(10):
		profiles[syn_idx] = ProjectileBatchPoolScript._build_radial_profile(
			ProjectileBatchPoolScript._get_polygon_for_synergy(syn_idx), ProjectileBatchPoolScript.SHAPE_BLEND_SAMPLES)

	# A pure 100% FIRE blend must reproduce FIRE's own profile exactly (no
	# RAW remainder, weight 1.0 on a single synergy).
	var pure_fire = ProjectileBatchPoolScript._compute_blended_polygon({EnergyPacket.SynergyType.FIRE: 1.0}, profiles)
	var pure_fire_matches = pure_fire.size() == ProjectileBatchPoolScript.SHAPE_BLEND_SAMPLES
	if pure_fire_matches:
		for k in range(pure_fire.size()):
			if abs(pure_fire[k].length() - profiles[EnergyPacket.SynergyType.FIRE][k]) > 0.01:
				pure_fire_matches = false
	_check("a pure 100% FIRE blend reproduces FIRE's own radial profile exactly (no RAW remainder)",
		pure_fire_matches)

	# A 50/50 FIRE/ICE blend's radius at every sample must be the exact
	# midpoint of the two source profiles - "x% toward each shape" is
	# literal weighted-average arithmetic, not an eyeballed approximation.
	var half_half = ProjectileBatchPoolScript._compute_blended_polygon(
		{EnergyPacket.SynergyType.FIRE: 0.5, EnergyPacket.SynergyType.ICE: 0.5}, profiles)
	var half_half_matches = true
	for k in range(half_half.size()):
		var expected = 0.5 * profiles[EnergyPacket.SynergyType.FIRE][k] + 0.5 * profiles[EnergyPacket.SynergyType.ICE][k]
		if abs(half_half[k].length() - expected) > 0.01:
			half_half_matches = false
	_check("a 50/50 FIRE/ICE blend's radius at every sample is the exact average of both profiles",
		half_half_matches)

	# Empty ratios (a pure-RAW shot, same convention as _compute_pie_wedges)
	# must reproduce RAW's own profile exactly (weight 1.0 on the remainder).
	var empty_blend = ProjectileBatchPoolScript._compute_blended_polygon({}, profiles)
	var empty_matches = true
	for k in range(empty_blend.size()):
		if abs(empty_blend[k].length() - profiles[EnergyPacket.SynergyType.RAW][k]) > 0.01:
			empty_matches = false
	_check("an empty ratios dict (a pure-RAW shot) reproduces RAW's own radial profile exactly",
		empty_matches)

	# A 70% EXPLOSION packet (30% unaccounted) must blend 0.7*EXPLOSION +
	# 0.3*RAW at every sample, same remainder convention as the pie chart.
	var partial_blend = ProjectileBatchPoolScript._compute_blended_polygon({EnergyPacket.SynergyType.EXPLOSION: 0.7}, profiles)
	var partial_matches = true
	for k in range(partial_blend.size()):
		var expected = 0.7 * profiles[EnergyPacket.SynergyType.EXPLOSION][k] + 0.3 * profiles[EnergyPacket.SynergyType.RAW][k]
		if abs(partial_blend[k].length() - expected) > 0.01:
			partial_matches = false
	_check("a 70% EXPLOSION blend (30% unaccounted) blends 0.7*EXPLOSION + 0.3*RAW at every sample",
		partial_matches)

	# --- render_mode enum: defaults to FLAT, settable, pool precomputes its
	# own radial profiles on _ready() -------------------------------------
	var pool = ProjectileBatchPoolScript.new(4)
	add_child(pool)
	_check("render_mode defaults to FLAT - every existing shot's rendering is unchanged unless explicitly changed",
		pool.render_mode == ProjectileBatchPoolScript.RenderMode.FLAT)
	pool.render_mode = ProjectileBatchPoolScript.RenderMode.SHAPE_BLEND
	_check("render_mode is a plain settable int, SHAPE_BLEND assigns and reads back correctly",
		pool.render_mode == ProjectileBatchPoolScript.RenderMode.SHAPE_BLEND)
	_check("the pool precomputes all 10 synergy radial profiles on _ready() (via _setup_render_polygons)",
		pool._synergy_radial_profiles.size() == 10 and pool._synergy_radial_profiles[0].size() == ProjectileBatchPoolScript.SHAPE_BLEND_SAMPLES)

	if failures == 0:
		print("PASS: Shape Blend mode's radial-profile resampling is geometrically correct (square/circle/self-touching-zigzag cases), blend arithmetic is exact weighted averaging with the same RAW-remainder convention as Pie Chart mode, and render_mode defaults to FLAT without disturbing any other rendering")
	get_tree().quit(0 if failures == 0 else 1)
