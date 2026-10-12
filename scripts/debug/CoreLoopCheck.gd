extends Node

# The core-mode loop rules: a boss-class fight every fifth wave; a forced Garage stop after every tenth wave in the campaign and
# endless modes only; trash converts to scrap on pickup by the chosen mode (new tile types never); dropped tiles can come out a
# tier better, more often later, never past Mythic; the Settings default is Common + Uncommon.

const MainScript = preload("res://scripts/core/Main.gd")
const LootManagerScript = preload("res://scripts/core/LootManager.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	var gaps = []
	for w in range(1, 301):
		var e = MainScript.encounter_for_wave(w)
		if (w % 5 == 0) != (e != ""):
			gaps.append(w)
	_check("every fifth wave, and only those, has a boss-class fight (%s)" % str(gaps), gaps.is_empty())
	_check("the kinds: boss, rival on the tens, nemesis on 20s, megaboss on 25s", MainScript.encounter_for_wave(5) == "boss" and MainScript.encounter_for_wave(10) == "rival" and MainScript.encounter_for_wave(20) == "nemesis" and MainScript.encounter_for_wave(25) == "megaboss" and MainScript.encounter_for_wave(15) == "boss" and MainScript.encounter_for_wave(3) == "")
	var due = []
	for w in range(1, 61):
		if MainScript.forced_garage_due(w, "campaign"):
			due.append(w)
	_check("the Garage is forced after waves 10, 20, ... (%s)" % str(due), due == [10, 20, 30, 40, 50, 60])
	_check("endless too; sandbox, boss rush, tournament and challenges never", MainScript.forced_garage_due(10, "endless") and not MainScript.forced_garage_due(10, "sandbox") and not MainScript.forced_garage_due(10, "boss_rush") and not MainScript.forced_garage_due(10, "tournament") and not MainScript.forced_garage_due(10, "challenge") and not MainScript.forced_garage_due(0, "campaign"))

	_check("the default is Common + Uncommon", SaveManager.auto_scrap_mode >= 0)
	_check("Common + Uncommon converts both, not Rare", AutoScrap.should_scrap_tile(0, true, 1) and AutoScrap.should_scrap_tile(1, true, 1) and not AutoScrap.should_scrap_tile(2, true, 1))
	_check("a new tile type is never converted", not AutoScrap.should_scrap_tile(0, false, 1))
	_check("Off converts nothing", not AutoScrap.should_scrap_tile(0, true, -1) and not AutoScrap.should_scrap_component(0, -1))
	_check("parts convert by rarity", AutoScrap.should_scrap_component(1, 1) and not AutoScrap.should_scrap_component(2, 1) and AutoScrap.component_value(2) == 225)
	_check("scrap values match the Garage's ladder", AutoScrap.tile_scrap_value(0) == 10 and AutoScrap.tile_scrap_value(2) == 75 and AutoScrap.tile_scrap_value(4) == 1000)
	_check("the four modes map to Off/Common/Common+Uncommon/Rare", AutoScrap.MODE_MAX_RARITY == [-1, 0, 1, 2] and AutoScrap.MODE_NAMES.size() == 4)

	_check("no boost on a high roll", LootManagerScript.boosted_rarity(1, 10, 0.99, 0.0) == 1)
	_check("a low roll bumps a tier", LootManagerScript.boosted_rarity(1, 10, 0.0, 0.99) == 2)
	_check("a very low second roll bumps two", LootManagerScript.boosted_rarity(1, 10, 0.0, 0.0) == 3)
	_check("Mythic stays Mythic and a bump stops at Mythic", LootManagerScript.boosted_rarity(4, 10, 0.0, 0.0) == 4 and LootManagerScript.boosted_rarity(3, 10, 0.0, 0.0) == 4)
	var early = 0
	var late = 0
	var rng = RandomNumberGenerator.new()
	rng.seed = 4
	for i in range(4000):
		if LootManagerScript.boosted_rarity(0, 5, rng.randf(), rng.randf()) > 0: early += 1
		if LootManagerScript.boosted_rarity(0, 120, rng.randf(), rng.randf()) > 0: late += 1
	_check("the boost chance climbs with the wave (%d vs %d of 4000)" % [early, late], late > early and early > 250 and late < 1400)
	print("CoreLoopCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
