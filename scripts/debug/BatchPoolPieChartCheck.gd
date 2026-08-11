extends Node

# Regression check for ProjectileBatchPool's Pie Chart mode (user request,
# 2026-08-11): "add a 'special mode' where each projectile is a pie graph
# showing the projectile's relative contents... +/- 0.5%... flat graph +
# any tail + any aura." Tests _compute_pie_wedges() directly - a pure
# function, no rendering involved, same "test the math, not a render
# round-trip" reasoning as every other _compute_* function in
# ProjectileBatchPool.gd.

const ProjectileBatchPoolScript = preload("res://scripts/entities/ProjectileBatchPool.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# --- A clean two-way blend sums exactly to TAU, no RAW remainder -----
	var wedges_a = ProjectileBatchPoolScript._compute_pie_wedges({
		EnergyPacket.SynergyType.FIRE: 0.6, EnergyPacket.SynergyType.ICE: 0.4,
	})
	_check("a clean 60/40 blend produces exactly 2 wedges (no spurious RAW remainder)",
		wedges_a.size() == 2)
	var fire_span = wedges_a[0]["end_angle"] - wedges_a[0]["start_angle"]
	var ice_span = wedges_a[1]["end_angle"] - wedges_a[1]["start_angle"]
	# +/-0.5% accuracy requirement, checked directly against the true angle
	# rather than a loose eyeball tolerance.
	_check("the FIRE wedge's angle is accurate to within 0.5% of 60% of TAU",
		abs(fire_span - TAU * 0.6) < TAU * 0.005)
	_check("the ICE wedge's angle is accurate to within 0.5% of 40% of TAU",
		abs(ice_span - TAU * 0.4) < TAU * 0.005)
	_check("wedges are contiguous - ICE starts exactly where FIRE ends",
		wedges_a[1]["start_angle"] == wedges_a[0]["end_angle"])
	_check("the full pie sums to exactly TAU (a real circle, not a partial arc)",
		abs(wedges_a[1]["end_angle"] - TAU) < 0.0001)

	# --- A blend that doesn't sum to 1.0 gets a RAW remainder wedge -------
	var wedges_b = ProjectileBatchPoolScript._compute_pie_wedges({
		EnergyPacket.SynergyType.EXPLOSION: 0.7,
	})
	_check("a 70% EXPLOSION packet (30% unaccounted) gets a trailing RAW remainder wedge",
		wedges_b.size() == 2 and wedges_b[1]["synergy"] == EnergyPacket.SynergyType.RAW)
	var raw_span = wedges_b[1]["end_angle"] - wedges_b[1]["start_angle"]
	_check("the RAW remainder wedge's angle is accurate to within 0.5% of 30% of TAU",
		abs(raw_span - TAU * 0.3) < TAU * 0.005)

	# --- Zero-ratio synergies never produce zero-width clutter wedges -----
	var wedges_c = ProjectileBatchPoolScript._compute_pie_wedges({
		EnergyPacket.SynergyType.FIRE: 1.0, EnergyPacket.SynergyType.ICE: 0.0,
		EnergyPacket.SynergyType.LIGHTNING: 0.0,
	})
	_check("zero-ratio synergies are skipped entirely, not emitted as zero-width wedges",
		wedges_c.size() == 1)

	# --- Fixed draw order (PIE_SYNERGY_ORDER), not magnitude-sorted -------
	var wedges_d = ProjectileBatchPoolScript._compute_pie_wedges({
		EnergyPacket.SynergyType.VAMPIRIC: 0.1, EnergyPacket.SynergyType.FIRE: 0.9,
	})
	_check("wedge order follows PIE_SYNERGY_ORDER (FIRE first), not descending magnitude, so a shot's pie never reshuffles frame to frame",
		wedges_d[0]["synergy"] == EnergyPacket.SynergyType.FIRE and wedges_d[1]["synergy"] == EnergyPacket.SynergyType.VAMPIRIC)

	# --- Empty ratios -> pure RAW pie (a genuinely empty/RAW-only shot) ---
	var wedges_e = ProjectileBatchPoolScript._compute_pie_wedges({})
	_check("an empty ratios dict (a pure-RAW shot) produces exactly one full-circle RAW wedge",
		wedges_e.size() == 1 and wedges_e[0]["synergy"] == EnergyPacket.SynergyType.RAW and abs(wedges_e[0]["end_angle"] - TAU) < 0.0001)

	# --- render_mode defaults to FLAT, Pie Chart is a plain settable value ---
	var pool = ProjectileBatchPoolScript.new(4)
	add_child(pool)
	_check("render_mode defaults to FLAT - every existing shot's rendering is unchanged unless explicitly changed",
		pool.render_mode == ProjectileBatchPoolScript.RenderMode.FLAT)
	pool.render_mode = ProjectileBatchPoolScript.RenderMode.PIE_CHART
	_check("render_mode is a plain settable int (GarageTestRange.gd's selector just assigns it directly)",
		pool.render_mode == ProjectileBatchPoolScript.RenderMode.PIE_CHART)

	if failures == 0:
		print("PASS: Pie Chart mode's wedge math is +/-0.5% accurate, contiguous, sums to a full circle, skips zero-ratio synergies, keeps a fixed draw order, and defaults off without disturbing any other rendering")
	get_tree().quit(0 if failures == 0 else 1)
