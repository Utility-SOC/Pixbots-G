extends Node

# Regression check for the wave-75 guaranteed-Mythic milestone (replaced the
# old mythic_seed_chance per-spawn random roll - see SquadDirector.gd's
# _spawn_bot_for_role comment and Main.gd's MYTHIC_MILESTONE_START_WAVE).
# Before wave 75: never force Mythic. At/after wave 75: exactly the FIRST
# bot spawned each wave is forced to Mythic, consuming
# _wave_guaranteed_mythic_used; later spawns that same wave are untouched
# until the flag resets (Main._start_wave's job, not exercised here).
#
# SquadDirector._spawn_bot_for_role reads `main = get_tree().current_scene`
# and duck-types ("current_wave" in main, etc.) rather than requiring a real
# Main instance - Main.gd itself can't be safely instantiated standalone
# headless (see CampaignMapRotationCheck.gd's header comment on the
# @onready constraint). So this check's own root IS the run scene
# (get_tree().current_scene when run via WaveMythicMilestoneCheck.tscn),
# and exposes the same fields Main.gd would - a lighter, equally faithful
# stand-in for the real spawn call site.

var current_wave: int = 1
const MYTHIC_MILESTONE_START_WAVE = 75
var _wave_guaranteed_mythic_used: bool = false

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var director = load("res://scripts/ai/SquadDirector.gd").new()
	director.name = "SquadDirector"
	add_child(director)

	# --- 1: before wave 75, spawning never force-promotes to Mythic, no
	# matter how many bots come through.
	current_wave = 74
	_wave_guaranteed_mythic_used = false
	var pre_milestone_mythic = false
	for i in range(5):
		var bot = director._spawn_bot_for_role("brawler")
		if int(bot.base_rarity) == HexTile.Rarity.MYTHIC:
			pre_milestone_mythic = true
		bot.queue_free()
	_check("before wave 75, no spawn is force-promoted to Mythic", not pre_milestone_mythic)

	# --- 2: at wave 75, the FIRST bot spawned is forced to Mythic.
	current_wave = 75
	_wave_guaranteed_mythic_used = false
	var first_bot = director._spawn_bot_for_role("brawler")
	_check("at wave 75, the first spawn of the wave is forced to Mythic (got %s)" % HexTile.Rarity.keys()[first_bot.base_rarity],
		int(first_bot.base_rarity) == HexTile.Rarity.MYTHIC)
	_check("the guarantee flag is consumed after firing", _wave_guaranteed_mythic_used)
	first_bot.queue_free()

	# --- 3: still wave 75, subsequent spawns are NOT also forced Mythic
	# (the guarantee is once-per-wave, not once-per-milestone-forever).
	var later_bot = director._spawn_bot_for_role("brawler")
	_check("later spawns the same wave are not also forced Mythic (got %s)" % HexTile.Rarity.keys()[later_bot.base_rarity],
		int(later_bot.base_rarity) != HexTile.Rarity.MYTHIC)
	later_bot.queue_free()

	# --- 4: a fresh wave (flag reset, matching Main._start_wave) can
	# trigger the guarantee again.
	current_wave = 76
	_wave_guaranteed_mythic_used = false
	var next_wave_bot = director._spawn_bot_for_role("brawler")
	_check("resetting the flag on a new wave lets the guarantee fire again (got %s)" % HexTile.Rarity.keys()[next_wave_bot.base_rarity],
		int(next_wave_bot.base_rarity) == HexTile.Rarity.MYTHIC)
	next_wave_bot.queue_free()

	if failures == 0:
		print("PASS: wave-75 guaranteed-Mythic milestone fires exactly once per wave, not before, not twice")
	get_tree().quit(0 if failures == 0 else 1)
