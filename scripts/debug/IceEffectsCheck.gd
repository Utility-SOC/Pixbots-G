extends Node

# Ice embrittlement + shatter (scripts/core/IceEffects.gd): the pure maths, then the Mech wiring (embrittle on an ice hit,
# reactive plating off while embrittled, slow proportional to the block, shatter only on a big kinetic hit on a frozen mech).

const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	_check("I == F blocks half (60000 vs 60000)", is_equal_approx(IceEffects.blocked_fraction(60000.0, 60000.0), 0.5))
	_check("no ice blocks nothing", IceEffects.blocked_fraction(0.0, 500.0) == 0.0)
	_check("more ice blocks more", IceEffects.blocked_fraction(300.0, 100.0) > IceEffects.blocked_fraction(100.0, 100.0))
	_check("block never reaches 1", IceEffects.blocked_fraction(1e9, 1.0) < 1.0)
	_check("duration grows with ice but is capped", IceEffects.embrittle_duration(500.0) > IceEffects.embrittle_duration(10.0) and IceEffects.embrittle_duration(1e9) <= IceEffects.EMBRITTLE_MAX_SEC)
	_check("small kinetic does not shatter", IceEffects.shatter(200.0, 10.0)["radius"] == 0.0)
	var a = IceEffects.shatter(100.0, 100.0)
	var b = IceEffects.shatter(300.0, 100.0)
	var c = IceEffects.shatter(100.0, 400.0)
	_check("more ice -> bigger shatter", b["radius"] > a["radius"] and b["damage"] > a["damage"])
	_check("more kinetic -> bigger shatter", c["radius"] > a["radius"] and c["damage"] > a["damage"])
	_check("shatter radius is capped", IceEffects.shatter(1e6, 1e8)["radius"] <= IceEffects.SHATTER_MAX_RADIUS)

	var m = MechScript.new()
	m.has_reactive_plating = true
	m.base_move_speed = 100.0
	IceEffects.apply_hit(m, 1.0, 200.0)
	_check("ice hit freezes", m.status_effects.has("frozen"))
	_check("ice hit embrittles (block %.2f)" % m.embrittle_block, m.embrittle_timer > 0.0 and is_equal_approx(m.embrittle_block, 0.5))
	_check("ice energy remembered", is_equal_approx(m.frozen_ice_energy, 200.0))
	m.status_effects.clear()
	m.embrittle_timer = 0.0
	m.frozen_ice_energy = 0.0
	# Frozen mech shrugs off a small kinetic hit; a big one shatters it.
	IceEffects.apply_hit(m, 1.0, 200.0)
	IceEffects.try_shatter(m, "KINETIC", 5.0, null)
	_check("small kinetic leaves it frozen", m.status_effects.has("frozen") and m.pending_shatter.is_empty())
	IceEffects.try_shatter(m, "FIRE", 500.0, null)
	_check("non-kinetic never shatters", m.status_effects.has("frozen"))
	# A mixed shot's Kinetic share does the shattering: 50% Kinetic of a 500 hit is 250, big enough; of a 60 hit it is 30, too small.
	m.hit_kinetic_ratio = 0.5
	IceEffects.try_shatter(m, "ICE", 60.0, null)
	_check("mixed shot below the kinetic threshold leaves it frozen", m.status_effects.has("frozen") and m.pending_shatter.is_empty())
	IceEffects.try_shatter(m, "ICE", 500.0, null)
	_check("mixed Ice+Kinetic shot shatters a frozen target (dominant element is not Kinetic)", not m.status_effects.has("frozen") and not m.pending_shatter.is_empty())
	_check("shatter remembers who fired it", m.pending_shatter.has("source"))
	m.hit_kinetic_ratio = -1.0
	m.pending_shatter = {}
	IceEffects.apply_hit(m, 1.0, 200.0)
	m.hit_kinetic_ratio = 0.0
	IceEffects.try_shatter(m, "KINETIC", 500.0, null)
	_check("a zero-Kinetic-share hit never shatters even if the element name says KINETIC", m.status_effects.has("frozen"))
	m.hit_kinetic_ratio = -1.0
	IceEffects.try_shatter(m, "KINETIC", 500.0, null)
	_check("big kinetic shatters: thaws and queues collateral", not m.status_effects.has("frozen") and not m.pending_shatter.is_empty() and m.embrittle_timer == 0.0)
	m.free()
	print("ice effects check done, failures=%d" % failures)
	get_tree().quit(failures)
