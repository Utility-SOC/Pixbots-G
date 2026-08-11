extends Node

# Regression check for ProjectileBatchPool's Starburst and Rings render
# modes ("could you make a couple more projectile skins?", 2026-08-11
# follow-up to Pie Chart/Shape Blend). Tests the pure geometry/ratio
# functions directly (_compute_starburst_magnitudes, _compute_starburst_
# spikes, _build_ring_polygon, _compute_halo_rings) - same "test the math,
# not a render round-trip" reasoning as every other _compute_* function in
# ProjectileBatchPool.gd - plus the RenderMode enum's two new values.

const ProjectileBatchPoolScript = preload("res://scripts/entities/ProjectileBatchPool.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# --- _compute_starburst_magnitudes: correct per-index mapping ---------
	var mags_a = ProjectileBatchPoolScript._compute_starburst_magnitudes({
		EnergyPacket.SynergyType.FIRE: 0.6, EnergyPacket.SynergyType.ICE: 0.4,
	})
	_check("starburst magnitudes has size 10 (one slot per SynergyType int)",
		mags_a.size() == 10)
	_check("FIRE's magnitude lands at index SynergyType.FIRE, not some other slot",
		abs(mags_a[EnergyPacket.SynergyType.FIRE] - 0.6) < 0.001)
	_check("ICE's magnitude lands at index SynergyType.ICE",
		abs(mags_a[EnergyPacket.SynergyType.ICE] - 0.4) < 0.001)
	_check("a clean 60/40 blend leaves RAW's magnitude at exactly 0 (no remainder)",
		mags_a[EnergyPacket.SynergyType.RAW] < 0.001)
	var mags_b = ProjectileBatchPoolScript._compute_starburst_magnitudes({
		EnergyPacket.SynergyType.EXPLOSION: 0.7,
	})
	_check("a 70% EXPLOSION packet (30% unaccounted) puts the remainder at RAW's own index",
		abs(mags_b[EnergyPacket.SynergyType.RAW] - 0.3) < 0.001)
	var mags_c = ProjectileBatchPoolScript._compute_starburst_magnitudes({})
	_check("an empty ratios dict (a pure-RAW shot) puts magnitude 1.0 entirely at RAW's index",
		abs(mags_c[EnergyPacket.SynergyType.RAW] - 1.0) < 0.001)

	# --- _compute_starburst_spikes: skip near-zero, correct angle/length --
	var spikes_a = ProjectileBatchPoolScript._compute_starburst_spikes({
		EnergyPacket.SynergyType.FIRE: 0.6, EnergyPacket.SynergyType.ICE: 0.4,
	})
	_check("a clean 60/40 blend produces exactly 2 spikes (RAW's remainder is ~0, skipped)",
		spikes_a.size() == 2)
	var fire_spike = null
	for s in spikes_a:
		if s["synergy"] == EnergyPacket.SynergyType.FIRE:
			fire_spike = s
	_check("FIRE's spike exists and its tip (2nd point) points along FIRE's fixed spoke angle at length MAX_RADIUS*0.6",
		fire_spike != null and abs(fire_spike["points"][1].length() - ProjectileBatchPoolScript.STARBURST_MAX_RADIUS * 0.6) < 0.01)
	var expected_fire_angle = EnergyPacket.SynergyType.FIRE * TAU / 10.0
	var fire_tip_angle = fire_spike["points"][1].angle()
	_check("FIRE's spike tip direction matches its fixed spoke angle (index*TAU/10)",
		abs(angle_difference(fire_tip_angle, expected_fire_angle)) < 0.01)

	var spikes_empty = ProjectileBatchPoolScript._compute_starburst_spikes({})
	_check("an empty ratios dict (pure RAW) produces exactly 1 spike, at RAW's own spoke",
		spikes_empty.size() == 1 and spikes_empty[0]["synergy"] == EnergyPacket.SynergyType.RAW)

	var spikes_trace = ProjectileBatchPoolScript._compute_starburst_spikes({
		EnergyPacket.SynergyType.FIRE: 1.0, EnergyPacket.SynergyType.ICE: 0.0,
	})
	_check("a zero-ratio synergy never produces a zero-length clutter spike",
		spikes_trace.size() == 1)

	# --- _build_ring_polygon: point count, radii correctness --------------
	var ring_poly = ProjectileBatchPoolScript._build_ring_polygon(2.0, 5.0, 8)
	_check("_build_ring_polygon returns 2*(segments+1) points (outer arc + inner arc)",
		ring_poly.size() == 2 * (8 + 1))
	var outer_ok = true
	var inner_ok = true
	for k in range(9):
		if abs(ring_poly[k].length() - 5.0) > 0.01:
			outer_ok = false
	for k in range(9, 18):
		if abs(ring_poly[k].length() - 2.0) > 0.01:
			inner_ok = false
	_check("every point in the first half of a ring polygon sits exactly at the outer radius",
		outer_ok)
	_check("every point in the second half of a ring polygon sits exactly at the inner radius",
		inner_ok)
	var disc_poly = ProjectileBatchPoolScript._build_ring_polygon(0.0, 4.0, 8)
	var disc_center_ok = true
	for k in range(9, 18):
		if disc_poly[k].length() > 0.001:
			disc_center_ok = false
	_check("inner_r=0.0 degenerates cleanly to a solid disc (all inner-arc points collapse to the center)",
		disc_center_ok)

	# --- _compute_halo_rings: cumulative radius correctness ----------------
	var rings_a = ProjectileBatchPoolScript._compute_halo_rings({
		EnergyPacket.SynergyType.FIRE: 0.6, EnergyPacket.SynergyType.ICE: 0.4,
	})
	_check("a clean 60/40 blend produces exactly 2 rings (no RAW remainder)",
		rings_a.size() == 2)
	_check("the FIRE ring starts at the center (inner radius 0)",
		abs(rings_a[0]["inner"]) < 0.001)
	_check("the FIRE ring's outer radius is exactly 60% of RING_MAX_RADIUS",
		abs(rings_a[0]["outer"] - ProjectileBatchPoolScript.RING_MAX_RADIUS * 0.6) < 0.01)
	_check("the ICE ring starts exactly where the FIRE ring ends (no gap, no overlap)",
		abs(rings_a[1]["inner"] - rings_a[0]["outer"]) < 0.0001)
	_check("the ICE ring's outer radius reaches exactly RING_MAX_RADIUS (the full blend accounted for)",
		abs(rings_a[1]["outer"] - ProjectileBatchPoolScript.RING_MAX_RADIUS) < 0.01)

	var rings_b = ProjectileBatchPoolScript._compute_halo_rings({EnergyPacket.SynergyType.EXPLOSION: 0.7})
	_check("a 70% EXPLOSION packet (30% unaccounted) gets a trailing RAW remainder ring reaching RING_MAX_RADIUS",
		rings_b.size() == 2 and rings_b[1]["synergy"] == EnergyPacket.SynergyType.RAW and abs(rings_b[1]["outer"] - ProjectileBatchPoolScript.RING_MAX_RADIUS) < 0.01)

	var rings_empty = ProjectileBatchPoolScript._compute_halo_rings({})
	_check("an empty ratios dict (pure RAW) produces exactly one ring spanning the full radius",
		rings_empty.size() == 1 and rings_empty[0]["synergy"] == EnergyPacket.SynergyType.RAW and abs(rings_empty[0]["outer"] - ProjectileBatchPoolScript.RING_MAX_RADIUS) < 0.01)

	# --- RenderMode enum: STARBURST/RINGS assignable and distinct ---------
	var pool = ProjectileBatchPoolScript.new(4)
	add_child(pool)
	pool.render_mode = ProjectileBatchPoolScript.RenderMode.STARBURST
	_check("render_mode accepts STARBURST and reads back correctly",
		pool.render_mode == ProjectileBatchPoolScript.RenderMode.STARBURST)
	pool.render_mode = ProjectileBatchPoolScript.RenderMode.RINGS
	_check("render_mode accepts RINGS and reads back correctly",
		pool.render_mode == ProjectileBatchPoolScript.RenderMode.RINGS)
	_check("FLAT/PIE_CHART/SHAPE_BLEND/STARBURST/RINGS are 5 distinct enum values",
		ProjectileBatchPoolScript.RenderMode.size() == 5)

	if failures == 0:
		print("PASS: Starburst's fixed-spoke magnitude/spike math and Rings' cumulative-radius/annulus-polygon math are both geometrically exact, share the same RAW-remainder convention as Pie Chart mode, and the RenderMode enum cleanly holds all 5 values")
	get_tree().quit(0 if failures == 0 else 1)
