extends Node

# Heals (negative damage: Vampiric lifesteal and the like) stop at max_hp instead of piling up without limit.

const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	var m = MechScript.new()
	m.max_hp = 1000.0
	m.hp = 400.0
	add_child(m)
	m.set_physics_process(false)
	m.apply_damage(-300.0, "VAMPIRIC")
	_check("a heal adds up to its size (%.0f)" % m.hp, is_equal_approx(m.hp, 700.0))
	m.apply_damage(-5000.0, "VAMPIRIC")
	_check("a big heal stops at max_hp (%.0f)" % m.hp, is_equal_approx(m.hp, 1000.0))
	for i in range(50):
		m.apply_damage(-100000.0, "VAMPIRIC")
	_check("repeated lifesteal never banks extra health (%.0f)" % m.hp, is_equal_approx(m.hp, 1000.0))
	m.hp = 1500.0
	m.apply_damage(-200.0, "VAMPIRIC")
	_check("health already above max is not pushed higher or cut by a heal (%.0f)" % m.hp, is_equal_approx(m.hp, 1500.0))
	m.apply_damage(100.0, "RAW")
	_check("damage still lowers it (%.0f)" % m.hp, m.hp < 1500.0)
	print("HealCapCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
