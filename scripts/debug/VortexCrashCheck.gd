extends Node

# Vortex crash damage (VortexEffects.note_pull / crash_damage): bodies dragged into each other hurt each other, scaled by the
# vortex energy and their closing speed, with a cooldown, nothing for bodies drifting apart or too slow, and Anchor's
# vortex damage reduction applies because the damage is VORTEX.

const MechScript = preload("res://scripts/entities/Mech.gd")
const E = 100.0 # vortex energy used below

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _mech(pos: Vector2) -> Node:
	var m = MechScript.new()
	m.is_player = false
	add_child(m)
	m.set_physics_process(false)
	m.max_hp = 1e6
	m.hp = 1e6
	m.global_position = pos
	return m

func _lost(m) -> float:
	return 1e6 - m.hp

# Moves a, b toward each other at `speed` px/s each, noting pulls every 0.05 s, from 200 apart until they overlap.
func _drive(a, b, speed: float, energy: float, t0: float = 0.0) -> float:
	var t = t0
	var x = 100.0
	VortexEffects.reset_crashes()
	while x > 5.0:
		a.global_position = Vector2(-x, 0)
		b.global_position = Vector2(x, 0)
		VortexEffects.note_pull(a, t, energy)
		VortexEffects.note_pull(b, t, energy)
		x -= speed * 0.05
		t += 0.05
	return t

func _ready():
	_check("slow closing speed deals nothing", VortexEffects.crash_damage(E, VortexEffects.CRASH_MIN_SPEED - 1.0) == 0.0)
	_check("no energy deals nothing", VortexEffects.crash_damage(0.0, 500.0) == 0.0)
	_check("reference speed deals 0.35x the energy", is_equal_approx(VortexEffects.crash_damage(E, VortexEffects.CRASH_REF_SPEED), VortexEffects.CRASH_DAMAGE_PER_ENERGY * E))
	_check("faster closing hurts more", VortexEffects.crash_damage(E, 600.0) > VortexEffects.crash_damage(E, 300.0))
	_check("more energy hurts more", VortexEffects.crash_damage(400.0, 300.0) > VortexEffects.crash_damage(100.0, 300.0))
	_check("the speed bonus is capped", is_equal_approx(VortexEffects.crash_damage(E, 1e6), VortexEffects.crash_damage(E, VortexEffects.CRASH_REF_SPEED * VortexEffects.CRASH_MAX_SPEED_MULT)))

	var a = _mech(Vector2(-100, 0))
	var b = _mech(Vector2(100, 0))
	_drive(a, b, 300.0, E)
	_check("two bodies pulled into each other both take crash damage (%.1f / %.1f)" % [_lost(a), _lost(b)], _lost(a) > 0.0 and _lost(b) > 0.0)
	var first = _lost(a)
	_check("a crash is bounded by the cooldown (a few hits, not one per note)", first <= VortexEffects.crash_damage(E, 600.0) * 3.0)

	a.hp = 1e6
	b.hp = 1e6
	_drive(a, b, 20.0, E)
	_check("bodies creeping together below the minimum speed take nothing", _lost(a) == 0.0 and _lost(b) == 0.0)

	# Drifting apart: start overlapped and move away.
	a.hp = 1e6
	b.hp = 1e6
	VortexEffects.reset_crashes()
	var t = 0.0
	var x = 10.0
	while x < 100.0:
		a.global_position = Vector2(-x, 0)
		b.global_position = Vector2(x, 0)
		VortexEffects.note_pull(a, t, E)
		VortexEffects.note_pull(b, t, E)
		x += 300.0 * 0.05
		t += 0.05
	_check("bodies drifting apart take nothing", _lost(a) == 0.0 and _lost(b) == 0.0)

	# Anchor's vortex damage reduction applies (the crash is VORTEX damage).
	a.hp = 1e6
	b.hp = 1e6
	b.vortex_damage_reduction = 0.5
	_drive(a, b, 300.0, E)
	_check("vortex damage reduction softens the crash (%.1f vs %.1f)" % [_lost(b), _lost(a)], _lost(b) > 0.0 and _lost(b) < _lost(a))

	# A lone pulled body has nothing to crash into.
	a.hp = 1e6
	b.hp = 1e6
	b.vortex_damage_reduction = 0.0
	VortexEffects.reset_crashes()
	for i in range(10):
		a.global_position = Vector2(-100 + i * 15, 0)
		VortexEffects.note_pull(a, i * 0.05, E)
	_check("a lone body takes no crash damage", _lost(a) == 0.0)

	VortexEffects.reset_crashes()
	print("VortexCrashCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
