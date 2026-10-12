extends Node

# Build-relative enemy scaling applies on every difficulty, grows with difficulty, is 1 at a starter build, and the smoothed
# power estimate rises at once but falls slowly.

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	var base = SquadDirector.NEAR_PEER_BASELINE
	for d in range(4):
		_check("difficulty %d: a starter build adds nothing" % d, SquadDirector.peer_multiplier(d, base) == 1.0 and SquadDirector.peer_multiplier(d, base * 0.2) == 1.0)
	var m = []
	for d in range(4):
		m.append(SquadDirector.peer_multiplier(d, base * 50.0))
	_check("a 50x build is followed more closely on higher difficulties (%s)" % str(m), m[0] > 1.0 and m[0] < m[1] and m[1] < m[2] and m[2] < m[3])
	_check("every tier follows slower than the player's power grows", m[2] < 50.0 and m[3] < 50.0)
	var d = SquadDirector.new()
	add_child(d)
	d._power_smooth = 10000.0
	d._power_smooth_usec = Time.get_ticks_usec() - 1000000
	var fell = d._smoothed_player_power()
	_check("the estimate falls slowly (%.0f)" % fell, fell > 9000.0 or fell >= 700.0)
	d._power_smooth = 100.0
	_check("and rises immediately", d._smoothed_player_power() >= 100.0)
	print("PeerScalingCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
