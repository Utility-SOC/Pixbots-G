extends Node

# Regression harness for: user, 2026-08-13 - "the boss rush bosses should
# start at the level the save file is in, so the boss's hp at least will
# be level appropriate."
#
# Root cause: Boss Rush replays a FIXED 1-15-Regulars-then-Endless-Mega-
# Bosses gauntlet, using current_wave purely as its OWN sequence position
# (1 = first Regular, 16 = first Mega Boss, 17+ = Endless) - completely
# unrelated to how far the chosen save actually progressed.
# _spawn_boss's Mythic-rarity-floor check (the main HP-relevant scaling
# knob for bosses - see that function's own hp_mult header comment) read
# current_wave directly, so a Boss Rush run against a save deep into the
# campaign (say Wave 300) still spawned bosses scaled as if it were the
# gauntlet's own wave 17-20-ish, nowhere near the save's real level.
#
# Fixed via Main._difficulty_scaling_wave(): SaveManager.max_wave_reached
# (the save's own peak progression, already correctly loaded for every
# game mode in _setup_player - see that function's own SaveManager.
# load_game() call) in Boss Rush specifically; current_wave everywhere
# else (regular campaign and Tournament scaling are both unaffected).
#
# Main.gd is scene-coupled (@onready references into the real game scene)
# and can't be safely instantiated standalone in a headless check - same
# constraint ExtraLivesCheck.gd/DeathLogPersistenceCheck.gd already
# documented for this file. Source-text assertions instead.

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
	return cond

func _ready():
	var failures = 0
	var main_source: String = FileAccess.get_file_as_string("res://scripts/core/Main.gd")

	if not _check("Main.gd defines _difficulty_scaling_wave()",
		main_source.contains("func _difficulty_scaling_wave() -> int:")):
		failures += 1

	if not _check("_difficulty_scaling_wave() returns SaveManager.max_wave_reached specifically for boss_rush",
		main_source.contains('if SaveManager.current_game_mode == "boss_rush":\n\t\treturn SaveManager.max_wave_reached')):
		failures += 1

	if not _check("_difficulty_scaling_wave() falls back to current_wave for every other game mode (regular campaign/Tournament unaffected)",
		main_source.contains("func _difficulty_scaling_wave() -> int:") and main_source.contains("\treturn current_wave")):
		failures += 1

	if not _check("_spawn_boss's Mythic-rarity floor now reads _difficulty_scaling_wave(), not raw current_wave",
		main_source.contains("var boss_rarity_floor = HexTile.Rarity.MYTHIC if _difficulty_scaling_wave() >= MYTHIC_MILESTONE_START_WAVE else 0")):
		failures += 1

	if not _check("no leftover reference to the old, wave-blind boss_rarity_floor expression",
		not main_source.contains("var boss_rarity_floor = HexTile.Rarity.MYTHIC if current_wave >= MYTHIC_MILESTONE_START_WAVE else 0")):
		failures += 1

	if not _check("SaveManager.max_wave_reached still exists as the field Boss Rush's save-select screen shows the player (\"Wave N\") and gates unlock on (>= 100) - the field this fix now reuses for scaling",
		FileAccess.get_file_as_string("res://scripts/core/SaveManager.gd").contains("var max_wave_reached")):
		failures += 1

	if failures == 0:
		print("PASS: Boss Rush boss HP/rarity scaling now reads the chosen save's real peak progression (SaveManager.max_wave_reached), not the gauntlet's own low sequence position")
	get_tree().quit(0 if failures == 0 else 1)
