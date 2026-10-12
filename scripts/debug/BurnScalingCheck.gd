extends Node

# Burning scales with the igniting shot (StatusEffectRunner.burn_dps_for / apply_burn) instead of a flat 5/s, never drops
# below the old 5/s, keeps the stronger of two overlapping burns, and resets when the burn ends.

const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	_check("a full-Fire 120 shot burns for the old 5/s", is_equal_approx(StatusEffectRunner.burn_dps_for(120.0, 1.0), 5.0))
	_check("a full-Fire 600 shot burns for 25/s", is_equal_approx(StatusEffectRunner.burn_dps_for(600.0, 1.0), 25.0))
	_check("a weak or low-ratio shot never burns below the old flat 5/s", StatusEffectRunner.burn_dps_for(10.0, 0.2) == 5.0)
	_check("more Fire ratio burns harder", StatusEffectRunner.burn_dps_for(600.0, 0.8) > StatusEffectRunner.burn_dps_for(600.0, 0.4))

	var m = MechScript.new()
	m.max_hp = 1e6
	m.hp = 1e6
	add_child(m)
	m.set_physics_process(false)
	StatusEffectRunner.apply_burn(m, 600.0, 1.0)
	_check("burn applies", m.status_effects.has("burning") and is_equal_approx(m.burn_dps, 25.0))
	StatusEffectRunner.apply_burn(m, 120.0, 1.0)
	_check("a weaker re-ignite does not weaken a running burn", is_equal_approx(m.burn_dps, 25.0))
	StatusEffectRunner.apply_burn(m, 1200.0, 1.0)
	_check("a stronger re-ignite strengthens it", is_equal_approx(m.burn_dps, 50.0))
	var hp0 = m.hp
	m.update_status_effects(1.0)
	_check("one second of burn deals its dps (%.1f)" % (hp0 - m.hp), absf((hp0 - m.hp) - 50.0) < 0.5)
	m.status_effects["burning"] = 0.01
	m.update_status_effects(0.1)
	_check("burn ends and the intensity resets", not m.status_effects.has("burning") and is_equal_approx(m.burn_dps, StatusEffectRunner.BURN_BASE_DPS))
	StatusEffectRunner.apply_burn(m, 120.0, 1.0)
	_check("the next burn starts from its own shot, not the old one", is_equal_approx(m.burn_dps, 5.0))
	m.free()

	print("BurnScalingCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
