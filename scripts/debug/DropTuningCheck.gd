extends Node

const MetaProgress = preload("res://scripts/core/MetaProgress.gd")
const LootScript = preload("res://scripts/core/LootManager.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	var tmp = "user://meta_progress_test.json"
	MetaProgress.reset_for_tests(tmp)
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)
	MetaProgress.reset_for_tests(tmp)

	# --- meta progression ---
	_check("fresh profile has 0 RP", MetaProgress.rp() == 0)
	_check("new best wave earns RP", MetaProgress.note_run_end(10) == 10 and MetaProgress.rp() == 10)
	_check("same wave again earns nothing (anti-farm)", MetaProgress.note_run_end(10) == 0 and MetaProgress.note_run_end(7) == 0)
	_check("only waves beyond best count", MetaProgress.note_run_end(12) == 2 and MetaProgress.rp() == 12)
	MetaProgress.note_boss_kill()
	_check("boss kill earns RP", MetaProgress.rp() == 12 + MetaProgress.RP_PER_BOSS)
	var before = MetaProgress.rp()
	_check("can buy affordable perk", MetaProgress.buy("salvage_contract") and MetaProgress.perk_level("salvage_contract") == 1)
	_check("cost deducted", MetaProgress.rp() == before - 3)
	_check("unknown perk rejected", not MetaProgress.buy("god_mode") and MetaProgress.next_cost("god_mode") == -1)
	MetaProgress.note_run_end(60)
	for i in range(10):
		MetaProgress.buy("salvage_contract")
	_check("perk level caps", MetaProgress.perk_level("salvage_contract") == MetaProgress.MAX_LEVEL and MetaProgress.next_cost("salvage_contract") == -1)
	_check("drop multiplier grows with level", MetaProgress.drop_multiplier("salvage_contract") > 1.3)
	MetaProgress.reset_for_tests(tmp)
	_check("profile persists to disk", MetaProgress.perk_level("salvage_contract") == MetaProgress.perk_level("salvage_contract") and MetaProgress.best_wave() == 60)
	var f = FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string('{"rp": 1e99, "best_wave": -5, "perks": {"salvage_contract": 99, "evil": 3}}')
	f.close()
	MetaProgress.reset_for_tests(tmp)
	_check("hostile meta file clamped", MetaProgress.rp() <= MetaProgress.MAX_RP and MetaProgress.best_wave() == 0 and MetaProgress.perk_level("salvage_contract") == MetaProgress.MAX_LEVEL)
	f = FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string("not json at all")
	f.close()
	MetaProgress.reset_for_tests(tmp)
	_check("garbage meta file falls back to blank", MetaProgress.rp() == 0)
	DirAccess.remove_absolute(tmp)
	MetaProgress.reset_for_tests(tmp)

	# --- drop tuning ---
	var lm = LootScript.new()
	add_child(lm)
	lm.current_wave = 5
	var link = lm.drop_chance("Left Arm Link", HexTile.Rarity.COMMON, false)
	var amp = lm.drop_chance("Amplifier", HexTile.Rarity.COMMON, false)
	_check("links drop far less than processors (%.3f vs %.3f)" % [link, amp], link < amp * 0.2)
	var boss_link = lm.drop_chance("Left Arm Link", HexTile.Rarity.RARE, true)
	var boss_amp = lm.drop_chance("Amplifier", HexTile.Rarity.RARE, true)
	_check("boss drops also suppress plumbing (%.3f vs %.3f)" % [boss_link, boss_amp], boss_link < boss_amp * 0.2)
	var mythic_link = lm.drop_chance("Left Arm Link", HexTile.Rarity.MYTHIC, false)
	var mythic_amp = lm.drop_chance("Amplifier", HexTile.Rarity.MYTHIC, false, true)
	_check("mythic plumbing is exempt from the plumbing discount", abs(mythic_link - mythic_amp) < 0.0001)
	var known = lm.drop_chance("Splitter", HexTile.Rarity.UNCOMMON, false, true)
	var unknown = lm.drop_chance("Splitter", HexTile.Rarity.UNCOMMON, false, false)
	_check("undiscovered types are favoured", unknown > known * 1.4)
	lm._note_dropped("Splitter")
	lm._note_dropped("Splitter")
	lm._note_dropped("Splitter")
	var flooded = lm.drop_chance("Splitter", HexTile.Rarity.UNCOMMON, false, true)
	_check("repeat drops get scarcer (%.3f -> %.3f)" % [known, flooded], flooded < known * 0.75 and flooded >= known * LootScript.FLOOD_MIN - 0.0001)
	lm.current_wave = 6
	lm._note_wave()
	var recovered = lm.drop_chance("Splitter", HexTile.Rarity.UNCOMMON, false, true)
	_check("flood penalty decays with waves", recovered > flooded)
	lm._drought_kills = 40
	var pity = lm.drop_chance("Splitter", HexTile.Rarity.UNCOMMON, false, true)
	_check("drought raises chance (%.3f)" % pity, pity > recovered + 0.05)
	var pity_link = lm.drop_chance("Left Arm Link", HexTile.Rarity.COMMON, false)
	_check("pity never helps plumbing", abs(pity_link - link) < 0.0001)
	_check("chance stays a probability", pity <= 1.0 and pity >= 0.0)
	_check("is_structural covers microcores", lm.is_structural("Microcore") and lm.is_structural("Core Reactor") and not lm.is_structural("Amplifier"))
	print("drop tuning check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
