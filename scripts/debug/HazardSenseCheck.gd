extends Node

# HazardSense: wary bots step out of / avoid a vent about to erupt and a burning oil slick; careless bots are unaffected,
# and wariness rises with difficulty.

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	var vent = LavaVent.new()
	vent.radius = 40.0
	add_child(vent)
	vent.global_position = Vector2(100, 100)
	var vents = [vent]
	_check("an idle vent is not a danger", not vent.is_dangerous() and HazardSense.push(Vector2(100, 100), Vector2.ZERO, vents, []) == Vector2.ZERO)
	vent.start_telegraph()
	_check("a telegraphing vent is a danger", vent.is_dangerous())
	var p = HazardSense.push(Vector2(120, 100), Vector2.ZERO, vents, [])
	_check("a bot inside the ring is pushed straight out", p.is_equal_approx(Vector2.RIGHT))
	_check("a bot far away is left alone", HazardSense.push(Vector2(400, 400), Vector2.ZERO, vents, []) == Vector2.ZERO)
	var ahead = HazardSense.push(Vector2(190, 100), Vector2(-200, 0), vents, [])
	_check("a bot about to walk into the ring is turned away", ahead.x > 0.0)
	_check("a bot standing on the centre still gets a direction", HazardSense.push(Vector2(100, 100), Vector2.ZERO, vents, []).length() > 0.99)

	var slick = OilSlickHazard.new()
	slick.radius = 30.0
	add_child(slick)
	slick.global_position = Vector2(500, 500)
	_check("a cold slick is no danger", HazardSense.push(Vector2(505, 500), Vector2.ZERO, [], [slick]) == Vector2.ZERO)
	slick.is_burning = true
	_check("a burning slick pushes a bot out", HazardSense.push(Vector2(505, 500), Vector2.ZERO, [], [slick]).x > 0.0)

	_check("Casual bots are never wary", not HazardSense.is_wary(12345, 0) and not HazardSense.is_wary(2000000000000, 0))
	var wary = [0, 0, 0, 0]
	for id in range(1, 2001):
		for d in range(4):
			if HazardSense.is_wary(id * 7919 + 4611686018427387904, d):
				wary[d] += 1
	_check("wariness rises with difficulty (%s)" % str(wary), wary[0] == 0 and wary[1] < wary[2] and wary[2] < wary[3])
	_check("share is near the table (top %d of 2000)" % wary[3], absf(wary[3] / 2000.0 - 0.9) < 0.05)
	vent.free()
	slick.free()
	print("HazardSenseCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
