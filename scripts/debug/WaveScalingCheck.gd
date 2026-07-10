extends Node

# Prints and sanity-checks SaveManager.wave_hp_multiplier's soft-knee curve:
# monotonically increasing, no discontinuity at the knee, and long-game
# magnitudes in the intended band (hundreds-to-thousands x at wave 100, not
# the old pure-exponential millions).

func _ready():
	var failures = 0
	for diff in range(4):
		var row = "diff %d (%s): " % [diff, SaveManager.DIFFICULTY_NAMES[diff]]
		var prev = 0.0
		for wave in [1, 10, 25, 26, 27, 50, 100]:
			var m = SaveManager.wave_hp_multiplier(diff, wave)
			row += "w%d=%.1fx  " % [wave, m]
			if m < prev:
				push_error("FAIL: curve not monotonic at diff %d wave %d" % [diff, wave])
				failures += 1
			prev = m
		print(row)
		# Continuity: the knee's linear step must not jump more than the
		# exponential step just before it did.
		var pre_step = SaveManager.wave_hp_multiplier(diff, 26) / SaveManager.wave_hp_multiplier(diff, 25)
		var post_step = SaveManager.wave_hp_multiplier(diff, 28) / SaveManager.wave_hp_multiplier(diff, 27)
		if post_step > pre_step + 0.001:
			push_error("FAIL: post-knee growth rate exceeds pre-knee rate at diff %d" % diff)
			failures += 1
	var w100_normal = SaveManager.wave_hp_multiplier(1, 100)
	if w100_normal > 1000.0 or w100_normal < 50.0:
		push_error("FAIL: Normal wave-100 multiplier %.0fx outside intended 50-1000x band" % w100_normal)
		failures += 1
	if failures == 0:
		print("PASS: wave HP curve is monotonic, knee-continuous, and long-game sane")
	get_tree().quit(0 if failures == 0 else 1)
