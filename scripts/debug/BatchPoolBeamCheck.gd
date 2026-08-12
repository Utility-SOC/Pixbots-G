extends Node

# Regression check for ProjectileBatchPool's Beam pattern support ("could
# you approach beams? ... Beams should have a range multiplier because
# they are very narrow", 2026-08-11 follow-up to the live-combat cutover).
# Covers spawn()'s is_beam param (pierce-count floor of 4, 1.6x max_range
# multiplier stacking with the packet's own range_mult), the precomputed
# BEAM_POLYGON/BEAM_POLYGON_INNER shapes, and _compute_beam_stretch's pure
# speed-proportional math.

const ProjectileBatchPoolScript = preload("res://scripts/entities/ProjectileBatchPool.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var pool = ProjectileBatchPoolScript.new(8)
	add_child(pool)

	# --- is_beam flag + pierce-count floor of 4 -----------------------------
	var i_normal = pool.spawn(Vector2.ZERO, Vector2.RIGHT, 500.0, 100.0, 10.0, 2.0, Color.WHITE, 1.0, true, self)
	_check("a normal (non-beam) shot has _is_beam == 0",
		pool._is_beam[i_normal] == 0)
	_check("a normal shot with no Pierce ratio keeps the ordinary pierce_count of 1 (no floor applied)",
		pool._pierce_count[i_normal] == 1)

	var i_beam = pool.spawn(Vector2.ZERO, Vector2.RIGHT, 500.0, 100.0, 10.0, 2.0, Color.WHITE, 1.0, true, self,
		0, {}, {}, 0.0, {}, 1.0, true)
	_check("a beam shot has _is_beam == 1",
		pool._is_beam[i_beam] == 1)
	_check("a beam shot with no Pierce ratio still gets the pierce-count FLOOR of 4",
		pool._pierce_count[i_beam] == 4)
	_check("the beam's pierce_count_max is captured consistently with the floored count (hit_decay math stays correct)",
		pool._pierce_count_max[i_beam] == 4)

	var i_beam_pierce = pool.spawn(Vector2.ZERO, Vector2.RIGHT, 500.0, 100.0, 10.0, 2.0, Color.WHITE, 1.0, true, self,
		0, {EnergyPacket.SynergyType.PIERCE: 1.0}, {}, 0.0, {}, 1.0, true)
	_check("a beam shot that ALSO has real Pierce ratio (would naturally derive pierce_count=5) keeps the HIGHER of the two, not floor+ratio stacking",
		pool._pierce_count[i_beam_pierce] == 5)

	# --- 1.6x max_range multiplier, stacking with range_mult ----------------
	var i_range_normal = pool.spawn(Vector2.ZERO, Vector2.RIGHT, 500.0, 100.0, 10.0, 2.0, Color.WHITE, 1.0, true, self)
	var base_range = pool._max_range[i_range_normal]
	var i_range_beam = pool.spawn(Vector2.ZERO, Vector2.RIGHT, 500.0, 100.0, 10.0, 2.0, Color.WHITE, 1.0, true, self,
		0, {}, {}, 0.0, {}, 1.0, true)
	_check("a beam shot's max_range is exactly 1.6x a normal shot's, matching Projectile.gd:549-550",
		abs(pool._max_range[i_range_beam] - base_range * 1.6) < 0.01)

	var i_range_beam_mult = pool.spawn(Vector2.ZERO, Vector2.RIGHT, 500.0, 100.0, 10.0, 2.0, Color.WHITE, 1.0, true, self,
		0, {}, {}, 0.0, {}, 2.0, true)
	_check("beam's 1.6x and the packet's own range_mult stack multiplicatively (1.6 * 2.0 = 3.2x), not one overriding the other",
		abs((pool._max_range[i_range_beam_mult] / base_range) - 3.2) < 0.01)

	# --- BEAM_POLYGON / BEAM_POLYGON_INNER precomputed correctly -----------
	_check("BEAM_POLYGON is populated (non-empty) after _ready()/_setup_render_polygons()",
		pool.BEAM_POLYGON.size() > 0)
	_check("BEAM_POLYGON_INNER has the same point count as BEAM_POLYGON",
		pool.BEAM_POLYGON_INNER.size() == pool.BEAM_POLYGON.size())
	var inner_matches_half = true
	for k in range(pool.BEAM_POLYGON.size()):
		if pool.BEAM_POLYGON_INNER[k] != pool.BEAM_POLYGON[k] * 0.5:
			inner_matches_half = false
	_check("every BEAM_POLYGON_INNER point is exactly half its corresponding BEAM_POLYGON point (same relationship every synergy's own inner/outer pair has)",
		inner_matches_half)
	var beam_len = 0.0
	var beam_width = 0.0
	for pt in pool.BEAM_POLYGON:
		beam_len = max(beam_len, abs(pt.x))
		beam_width = max(beam_width, abs(pt.y))
	_check("BEAM_POLYGON is genuinely elongated (much longer than it is wide), not another blob shape",
		beam_len > beam_width * 5.0)

	# --- _compute_beam_stretch: pure speed-proportional math ----------------
	_check("a non-beam shot's stretch is always exactly 1.0 regardless of speed",
		ProjectileBatchPoolScript._compute_beam_stretch(9999.0, false) == 1.0)
	_check("a beam shot at exactly base speed (500) stretches by exactly 1.0 - a no-op at that reference point",
		abs(ProjectileBatchPoolScript._compute_beam_stretch(500.0, true) - 1.0) < 0.001)
	_check("a beam shot at the real Beam speed (500*2.5=1250) stretches by exactly 2.5x",
		abs(ProjectileBatchPoolScript._compute_beam_stretch(1250.0, true) - 2.5) < 0.001)
	_check("beam stretch is capped at 3.0x even for an extremely fast shot",
		abs(ProjectileBatchPoolScript._compute_beam_stretch(999999.0, true) - 3.0) < 0.001)
	_check("beam stretch never goes below 1.0 even for an extremely slow shot",
		abs(ProjectileBatchPoolScript._compute_beam_stretch(1.0, true) - 1.0) < 0.001)

	if failures == 0:
		print("PASS: Beam shots get the pierce-count floor of 4 (not stacked with real Pierce ratio), a 1.6x max_range multiplier that correctly stacks with the packet's own range_mult, a genuinely elongated precomputed needle shape, and speed-proportional draw-time stretching capped at 3x")
	get_tree().quit(0 if failures == 0 else 1)
