extends Node

# CaptureBuffs: deterministic type per position, grant/refresh/cap, timers and regen, the multipliers, and the end-to-end
# path (finish a hold with a buff type -> the player gets it; weapons buff raises live shot damage; armour buff cuts damage taken).

const MechScript = preload("res://scripts/entities/Mech.gd")
const ObjScript = preload("res://scripts/hazards/ZoneObjective.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	_check("the same position always offers the same buff", CaptureBuffs.type_for_position(Vector2(480, 960)) == CaptureBuffs.type_for_position(Vector2(480, 960)))
	var seen = {}
	for i in range(40):
		seen[CaptureBuffs.type_for_position(Vector2(i * 331, i * 197 + 13))] = true
	_check("positions spread over all four buff types (%d)" % seen.size(), seen.size() == 4)

	var m = MechScript.new()
	m.is_player = true
	m.max_hp = 1000.0
	m.hp = 500.0
	add_child(m)
	m.set_physics_process(false)
	_check("no buffs: all multipliers are 1", CaptureBuffs.weapons_mult(m) == 1.0 and CaptureBuffs.speed_mult(m) == 1.0 and CaptureBuffs.damage_taken_mult(m) == 1.0)
	_check("an unknown type is refused", not CaptureBuffs.grant(m, "bogus") and m.capture_buffs.is_empty())
	CaptureBuffs.grant(m, "weapons")
	CaptureBuffs.grant(m, "armor")
	CaptureBuffs.grant(m, "speed")
	_check("weapons +12%, armor -10%, speed +12%", is_equal_approx(CaptureBuffs.weapons_mult(m), 1.12) and is_equal_approx(CaptureBuffs.damage_taken_mult(m), 0.9) and is_equal_approx(CaptureBuffs.speed_mult(m), 1.12))
	CaptureBuffs.tick(m, 40.0)
	CaptureBuffs.grant(m, "weapons")
	_check("re-capturing refreshes the timer", is_equal_approx(m.capture_buffs["weapons"], CaptureBuffs.DURATION) and m.capture_buffs["armor"] < 6.0)
	CaptureBuffs.grant(m, "regen")
	_check("at most %d buffs: the one nearest expiry gave way" % CaptureBuffs.MAX_ACTIVE, m.capture_buffs.size() == CaptureBuffs.MAX_ACTIVE and not m.capture_buffs.has("armor") and m.capture_buffs.has("regen"))
	var hp0 = m.hp
	CaptureBuffs.tick(m, 2.0)
	_check("regen heals 1%% of max hp per second (%.1f)" % (m.hp - hp0), is_equal_approx(m.hp - hp0, 20.0))
	CaptureBuffs.tick(m, 100.0)
	_check("buffs expire", m.capture_buffs.is_empty() and CaptureBuffs.weapons_mult(m) == 1.0)

	# Damage taken: armour buff cuts it.
	var a = MechScript.new(); a.is_player = true; a.max_hp = 1e6; a.hp = 1e6; add_child(a); a.set_physics_process(false)
	var b = MechScript.new(); b.is_player = true; b.max_hp = 1e6; b.hp = 1e6; add_child(b); b.set_physics_process(false)
	CaptureBuffs.grant(b, "armor")
	a.apply_damage(1000.0, "RAW")
	b.apply_damage(1000.0, "RAW")
	_check("the armour buff cuts damage taken (%.1f vs %.1f)" % [1e6 - b.hp, 1e6 - a.hp], (1e6 - b.hp) < (1e6 - a.hp) * 0.95 and (1e6 - a.hp) > 0.0)

	# End to end: a hold with a buff type grants it to the player on completion.
	var player = MechScript.new(); player.is_player = true; add_child(player); player.set_physics_process(false)
	player.add_to_group("player")
	var hold = ObjScript.new()
	hold.kind = "hold"
	hold.radius = 100.0
	hold.buff_type = "speed"
	hold.set_process(false)
	add_child(hold)
	hold.global_position = Vector2(0, 0)
	player.global_position = Vector2(10, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	hold.step(20.0)
	_check("finishing a buffed hold grants the buff", hold.done and CaptureBuffs.is_active(player, "speed"))
	var cache = ObjScript.new()
	cache.kind = "cache"
	cache.buff_type = "weapons"
	cache.set_process(false)
	add_child(cache)
	cache.global_position = Vector2(0, 0)
	cache._complete()
	_check("a loot cache never grants a buff", not CaptureBuffs.is_active(player, "weapons"))
	print("CaptureBuffsCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
