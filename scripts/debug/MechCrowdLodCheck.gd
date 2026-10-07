extends Node

# Mech.crowd_divisor: close mechs always tick every frame; the divisor grows with the live-enemy count.

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	var far_sq := 800.0 * 800.0
	var close_sq := 200.0 * 200.0
	_check("small crowd: every tick", Mech.crowd_divisor(10, far_sq) == 1)
	_check("just below the mid threshold: every tick", Mech.crowd_divisor(Mech.CROWD_LOD_MID - 1, far_sq) == 1)
	_check("mid crowd: every 2nd tick", Mech.crowd_divisor(Mech.CROWD_LOD_MID, far_sq) == 2)
	_check("just below the high threshold: every 2nd tick", Mech.crowd_divisor(Mech.CROWD_LOD_HIGH - 1, far_sq) == 2)
	_check("big crowd: every 3rd tick", Mech.crowd_divisor(Mech.CROWD_LOD_HIGH, far_sq) == 3)
	_check("huge crowd: still capped at 3", Mech.crowd_divisor(500, far_sq) == 3)
	_check("close mechs always tick every frame, even in a huge crowd", Mech.crowd_divisor(500, close_sq) == 1)
	_check("close boundary is exclusive", Mech.crowd_divisor(500, Mech.CROWD_LOD_CLOSE_SQ) == 3)

	# Staggering: over any 6 consecutive physics frames each id ticks exactly 6/div times, and ids spread out.
	for div in [2, 3]:
		var ticks := {}
		for id in range(1000, 1006):
			var n := 0
			for f in range(600, 606):
				if (f + id) % div == 0: n += 1
			ticks[id] = n
		var ok := true
		for id in ticks:
			ok = ok and ticks[id] == 6 / div
		_check("each mech ticks 6/%d times per 6 frames" % div, ok)
		var per_frame := {}
		for f in range(600, 606):
			var c := 0
			for id in range(1000, 1006):
				if (f + id) % div == 0: c += 1
			per_frame[f] = c
		var mn := 99
		var mx := 0
		for f in per_frame:
			mn = min(mn, per_frame[f])
			mx = max(mx, per_frame[f])
		_check("ids spread across frames (div %d: per-frame ticking count %d..%d)" % [div, mn, mx], mx - mn <= 1)
	print("MechCrowdLodCheck: %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)
