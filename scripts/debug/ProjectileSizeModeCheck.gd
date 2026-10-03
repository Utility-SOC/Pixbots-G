extends Node

# Magnitude-vs-size setting: Full keeps 8x, Auto shrinks the cap with
# difficulty, Compact stays small; a real huge shot gets capped + a power ring.

var failures := 0
func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var old_mode = SaveManager.projectile_size_mode
	var old_diff = SaveManager.difficulty
	SaveManager.projectile_size_mode = 0
	_check("Full scale allows the old 8x", SaveManager.projectile_scale_cap() == 8.0)
	SaveManager.projectile_size_mode = 1
	var caps = []
	for d in range(4):
		SaveManager.difficulty = d
		caps.append(SaveManager.projectile_scale_cap())
	_check("Auto cap shrinks with difficulty %s" % str(caps), caps[0] > caps[1] and caps[1] > caps[2] and caps[2] > caps[3])
	SaveManager.projectile_size_mode = 2
	_check("Compact is small", SaveManager.projectile_scale_cap() < 2.0)
	_check("power fraction is 0 for tiny and ~1 at the ceiling", SaveManager.projectile_power_fraction(1.0) < 0.05 and SaveManager.projectile_power_fraction(600000.0) > 0.99)

	# A real max-magnitude legacy projectile is capped, small mags are untouched.
	var Proj = load("res://scripts/entities/Projectile.gd")
	for case in [[600000.0, true], [50.0, false]]:
		var p = Proj.new()
		p.synergies = {EnergyPacket.SynergyType.KINETIC: case[0]}
		add_child(p)
		await get_tree().process_frame
		if case[1]:
			_check("max-magnitude shot is capped to %.1f (compact)" % p.visual_scale, p.visual_scale <= SaveManager.projectile_scale_cap() + 0.01)
		else:
			_check("a small shot is not shrunk further (%.2f)" % p.visual_scale, p.visual_scale < 2.0)
		p.queue_free()
	SaveManager.projectile_size_mode = old_mode
	SaveManager.difficulty = old_diff
	print("projectile size mode check done, failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
