extends Node

# Regression harness for: user, 2026-08-13 - "I've gotten killed a few
# times and it doesn't have it in my ai profile" (the War Room's Death Log,
# task #9 - SaveManager.death_log/record_death()).
#
# Root cause: SaveManager.record_death() only mutates death_log IN MEMORY.
# The only SaveManager.save_game() call anywhere in _on_player_died() used
# to be inside the rare "3 straight Rival losses" lockout branch - every
# OTHER death (the overwhelming majority: dying to a regular enemy, or to
# a Rival but not the 3rd loss in a row, or with no SquadDirector/Rival in
# play at all) never got written to disk unless the player happened to
# deploy again afterward. Quitting right after dying - an extremely
# ordinary thing to do - silently lost that death forever.
#
# Main.gd is scene-coupled (@onready references into the real game scene)
# and can't be safely instantiated standalone in a headless check - same
# constraint ExtraLivesCheck.gd already hit for this exact file. Source-
# text assertions instead: confirm the unconditional save now runs
# immediately after record_death(), strictly BEFORE the rival-loss-
# specific branch (so it isn't accidentally gated behind that check too).

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
	return cond

func _ready():
	var failures = 0
	var main_source: String = FileAccess.get_file_as_string("res://scripts/core/Main.gd")

	var record_idx = main_source.find("SaveManager.record_death(current_wave, _top_damage_label(player.recent_damage_log))")
	if not _check("_on_player_died() still calls SaveManager.record_death() with the wave/killed-by snapshot", record_idx != -1):
		failures += 1

	var rival_branch_idx = main_source.find("director.consecutive_rival_losses += 1")
	if not _check("_on_player_died() still has the consecutive-Rival-losses branch to anchor against", rival_branch_idx != -1):
		failures += 1

	if record_idx != -1 and rival_branch_idx != -1:
		var between = main_source.substr(record_idx, rival_branch_idx - record_idx)
		if not _check("an unconditional SaveManager.save_game(\"autosave\", ...) call runs between record_death() and the Rival-loss branch - every death is now persisted immediately, not just the rare 3-straight-Rival-loss case",
			between.contains('SaveManager.save_game("autosave", player, player_inventory)')):
			failures += 1

	# death_log itself must actually be part of the save payload, or an
	# immediate save_game() call would be pointless - regression guard
	# against that field ever being dropped from serialization.
	var save_manager_source: String = FileAccess.get_file_as_string("res://scripts/core/SaveManager.gd")
	if not _check("SaveManager's save payload still includes death_log",
		save_manager_source.contains('"death_log": death_log')):
		failures += 1
	if not _check("SaveManager's load path still restores death_log from the save payload",
		save_manager_source.contains('death_log = json["death_log"]')):
		failures += 1

	if failures == 0:
		print("PASS: every player death is persisted to disk immediately, not just the rare 3-straight-Rival-loss case - a death followed by quitting no longer silently vanishes from the War Room's Death Log")
	get_tree().quit(0 if failures == 0 else 1)
