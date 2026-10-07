extends Node

# AdaptiveTick policy: fast frames keep 60 Hz, slow frames drop tiers (jumping straight to the right one),
# recovery steps up one tier at a time, only after the hold time, with hysteresis (no flapping).

const AT = preload("res://scripts/core/AdaptiveTick.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	_check("60 fps stays at tier 0 (60 Hz)", AT.next_tier(0, 60.0, 10.0) == 0)
	_check("52 fps stays at 60 Hz (above 60*0.85=51)", AT.next_tier(0, 52.0, 10.0) == 0)
	_check("45 fps drops to the 40 Hz tier", AT.next_tier(0, 45.0, 10.0) == 1)
	_check("25 fps drops straight to the 20 Hz tier", AT.next_tier(0, 25.0, 10.0) == 3)
	_check("9 fps drops to the lowest tier (15 Hz)", AT.next_tier(0, 9.0, 10.0) == 4)
	_check("already at the lowest tier stays there", AT.next_tier(4, 5.0, 10.0) == 4)
	_check("at 30 Hz, 29 fps does not flap down (29 > 30*0.85)", AT.next_tier(2, 29.0, 10.0) == 2)
	_check("recovery waits for the hold time", AT.next_tier(3, 70.0, 0.5) == 3)
	_check("recovery after the hold steps up exactly one tier", AT.next_tier(3, 70.0, 5.0) == 2)
	_check("no up-step without headroom (20 Hz tier, 33 fps < 30*1.15)", AT.next_tier(3, 33.0, 5.0) == 3)
	_check("up-step with headroom (20 Hz tier, 36 fps > 30*1.15)", AT.next_tier(3, 36.0, 5.0) == 2)
	# Simulated oscillation around a boundary never changes tier more than once per hold window.
	var tier := 0
	var changes := 0
	var since := 0.0
	for k in range(200):
		var fps := 50.0 + (3.0 if k % 2 == 0 else -3.0) # jitter 47..53 around the 51 boundary
		since += 0.5
		var nt = AT.next_tier(tier, fps, since)
		if nt != tier:
			changes += 1
			tier = nt
			since = 0.0
	_check("jitter around a boundary does not flap (%d changes in 100 s)" % changes, changes <= 4)
	print("AdaptiveTickCheck: %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)
