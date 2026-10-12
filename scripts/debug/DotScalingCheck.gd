extends Node

# Poison and bleeding scale with the shot like burning does (floors stay 4/s and 6/s), the stronger running one wins, and
# both reset when they end. Vampiric never heals the shooter for more than the hit removed.

const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	_check("a full-Poison 120 shot poisons for the old 4/s", is_equal_approx(StatusEffectRunner.poison_dps_for(120.0, 1.0), 4.0))
	_check("a full-Poison 600 shot poisons for 20/s", is_equal_approx(StatusEffectRunner.poison_dps_for(600.0, 1.0), 20.0))
	_check("a full-Vampiric 600 shot bleeds for 30/s", is_equal_approx(StatusEffectRunner.bleed_dps_for(600.0, 1.0), 30.0))
	_check("weak shots keep the old floors", StatusEffectRunner.poison_dps_for(10.0, 0.2) == 4.0 and StatusEffectRunner.bleed_dps_for(10.0, 0.2) == 6.0)

	var m = MechScript.new()
	m.max_hp = 1e6
	m.hp = 1e6
	add_child(m)
	m.set_physics_process(false)
	StatusEffectRunner.apply_poison(m, 600.0, 1.0)
	StatusEffectRunner.apply_bleed(m, 600.0, 1.0)
	_check("both apply at shot strength", is_equal_approx(m.poison_dps, 20.0) and is_equal_approx(m.bleed_dps, 30.0))
	StatusEffectRunner.apply_poison(m, 120.0, 1.0)
	_check("a weaker re-poison does not weaken it", is_equal_approx(m.poison_dps, 20.0))
	var hp0 = m.hp
	m.update_status_effects(1.0)
	_check("one second deals poison + bleed (%.1f)" % (hp0 - m.hp), absf((hp0 - m.hp) - 50.0) < 1.0)
	m.status_effects["poisoned"] = 0.01
	m.status_effects["bleeding"] = 0.01
	m.update_status_effects(0.1)
	_check("both reset when they end", is_equal_approx(m.poison_dps, 4.0) and is_equal_approx(m.bleed_dps, 6.0))
	m.free()

	print("DotScalingCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
