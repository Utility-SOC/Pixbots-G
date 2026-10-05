extends Node

# Crossfade must keep combined loudness constant (no silent dip) and keys must tier by wave.
func _ready():
	var fails = 0
	for i in range(0, 11):
		var g = AudioManager.crossfade_gains(i / 10.0)
		var p = g.x * g.x + g.y * g.y
		if abs(p - 1.0) > 0.001:
			print("FAIL: power %.4f at t=%d/10" % [p, i])
			fails += 1
	var g0 = AudioManager.crossfade_gains(0.0)
	var g1 = AudioManager.crossfade_gains(1.0)
	if abs(g0.x - 1.0) > 0.001 or abs(g1.y - 1.0) > 0.001:
		print("FAIL: endpoints")
		fails += 1
	if AudioManager.wave_tier_wave(1) != 1 or AudioManager.wave_tier_wave(5) != 4 or AudioManager.wave_tier_wave(99) != 30:
		print("FAIL: wave tiers")
		fails += 1
	print("music crossfade check done, failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
