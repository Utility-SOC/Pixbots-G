extends Node

# Regression harness for JammerField power scaling ("jammer field should
# increase with more power pushed into it"): sustained feed_power must grow
# power_multiplier and the real boundary radii, the bonus must saturate
# below 1 + POWER_MAX_BONUS, and cutting the feed must decay it back to
# baseline. Driven manually at a fixed DT, no wall-clock dependence.

const JammerFieldScript = preload("res://scripts/visuals/JammerField.gd")

const DT := 1.0 / 30.0

func _avg_radius(field) -> float:
	var total = 0.0
	for p in field.boundary_points:
		total += p.length()
	return total / field.boundary_points.size()

func _ready():
	var failures = 0
	var owner_stub = Node2D.new()
	add_child(owner_stub)
	var field = JammerFieldScript.new()
	field.setup(owner_stub, 300.0, -1.0)
	add_child(field)
	field.set_process(false) # drive manually

	# Settle at baseline: no feed, 4 simulated seconds.
	for i in range(120):
		field._process(DT)
	if abs(field.power_multiplier - 1.0) > 0.001:
		push_error("FAIL: unfed field has power_multiplier %f, expected 1.0" % field.power_multiplier)
		failures += 1
	var baseline_avg = _avg_radius(field)
	print("1) unfed baseline: mult=%.3f avg_radius=%.1f" % [field.power_multiplier, baseline_avg])

	# Sustained feed (600 energy/sec) for 8 simulated seconds: multiplier
	# should approach saturation and the actual boundary should have grown
	# through the wobble-reroll path.
	for i in range(240):
		field.feed_power(600.0 * DT)
		field._process(DT)
	var fed_mult = field.power_multiplier
	var fed_avg = _avg_radius(field)
	if fed_mult < 1.5:
		push_error("FAIL: sustained feed only reached mult=%f, expected > 1.5" % fed_mult)
		failures += 1
	elif fed_mult > 1.0 + field.POWER_MAX_BONUS:
		push_error("FAIL: mult=%f exceeded the saturation cap %f" % [fed_mult, 1.0 + field.POWER_MAX_BONUS])
		failures += 1
	if fed_avg < baseline_avg * 1.25:
		push_error("FAIL: boundary barely grew (avg %f -> %f)" % [baseline_avg, fed_avg])
		failures += 1
	if failures == 0:
		print("2) sustained feed: mult=%.3f avg_radius=%.1f (grew, under cap)" % [fed_mult, fed_avg])

	# Saturation: feeding 10x harder must not break the cap.
	for i in range(120):
		field.feed_power(6000.0 * DT)
		field._process(DT)
	if field.power_multiplier > 1.0 + field.POWER_MAX_BONUS:
		push_error("FAIL: overfeed broke the cap: mult=%f" % field.power_multiplier)
		failures += 1
	else:
		print("3) overfeed stays capped: mult=%.3f <= %.1f" % [field.power_multiplier, 1.0 + field.POWER_MAX_BONUS])

	# Cut the feed: 40 simulated seconds (~13 half-lives) back near baseline.
	for i in range(1200):
		field._process(DT)
	var decayed_mult = field.power_multiplier
	var decayed_avg = _avg_radius(field)
	if decayed_mult > 1.1:
		push_error("FAIL: decay stalled at mult=%f, expected <= 1.1" % decayed_mult)
		failures += 1
	elif decayed_avg > baseline_avg * 1.2:
		push_error("FAIL: boundary didn't shrink back (avg %f vs baseline %f)" % [decayed_avg, baseline_avg])
		failures += 1
	else:
		print("4) feed cut: mult=%.3f avg_radius=%.1f (back near baseline)" % [decayed_mult, decayed_avg])

	if failures == 0:
		print("PASS: jammer field power scaling - grows with power, saturates, decays back")
	get_tree().quit(0 if failures == 0 else 1)
