extends Node

# Vortex rework (scripts/core/VortexEffects.gd): gravity-well detection and radius (grows with vortex energy, widened by
# Explosive, capped), deterministic continuous Bezier wander, and pin (a hostile body inside the pin radius rides the shot).

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	_check("large Poison + Vortex is a well", VortexEffects.is_well(0.4, 0.4, 1000.0))
	_check("small shot is not a well", not VortexEffects.is_well(0.4, 0.4, 20.0))
	_check("no Poison is not a well", not VortexEffects.is_well(0.0, 0.6, 5000.0))
	_check("no Vortex is not a well", not VortexEffects.is_well(0.6, 0.0, 5000.0))
	var r1 = VortexEffects.well_radius(200.0, 0.0)
	var r2 = VortexEffects.well_radius(2000.0, 0.0)
	_check("more vortex energy -> bigger well (%.0f < %.0f)" % [r1, r2], r2 > r1)
	_check("Explosive widens the well", VortexEffects.well_radius(200.0, 0.5) > r1)
	_check("well radius is capped", VortexEffects.well_radius(1e9, 1.0) <= VortexEffects.WELL_MAX_RADIUS)

	var a = VortexEffects.wander_velocity(0.3, 12345, 0.6)
	_check("wander is deterministic", a == VortexEffects.wander_velocity(0.3, 12345, 0.6))
	_check("different seeds wander differently", a != VortexEffects.wander_velocity(0.3, 54321, 0.6))
	_check("no wander below the vortex threshold", VortexEffects.wander_velocity(0.3, 12345, 0.05) == 0.0)
	# The lateral POSITION must be continuous across segment seams (integrate the velocity over a few segments).
	var pos = 0.0
	var prev = 0.0
	var max_jump = 0.0
	var dt = 0.002
	var t = 0.0
	while t < 2.0:
		pos += VortexEffects.wander_velocity(t, 777, 0.8) * dt
		max_jump = maxf(max_jump, absf(pos - prev))
		prev = pos
		t += dt
	_check("wander path is continuous and bounded (max step %.3f px, end %.1f px)" % [max_jump, pos], max_jump < 2.0 and absf(pos) < 400.0)
	var bends = false
	for k in range(1, 20):
		if absf(VortexEffects.wander_velocity(k * 0.05, 777, 0.8)) > 1.0:
			bends = true
	_check("wander actually moves the shot sideways", bends)

	# Pin: a hostile body near the source rides the carry; one outside the pin radius is only pulled.
	var near = CharacterBody2D.new()
	var far = CharacterBody2D.new()
	add_child(near)
	add_child(far)
	near.global_position = Vector2(10, 0)
	far.global_position = Vector2(400, 0)
	VortexEffects.pull_target(near, Vector2.ZERO, true, 0.8, 500.0, 0.05, Vector2(25, 0), VortexEffects.pin_radius(0.8))
	VortexEffects.pull_target(far, Vector2.ZERO, true, 0.8, 500.0, 0.05, Vector2(25, 0), VortexEffects.pin_radius(0.8))
	_check("pinned body is carried with the shot (x=%.1f)" % near.global_position.x, near.global_position.x > 30.0)
	_check("a body outside the pin radius is not carried", far.global_position.x <= 400.0)
	print("vortex effects check done, failures=%d" % failures)
	get_tree().quit(failures)
