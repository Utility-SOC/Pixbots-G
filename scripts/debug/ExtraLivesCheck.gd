extends Node

# Regression harness for the extra-lives feature: "3 lives so it isn't game
# over as soon as I get killed once", refined to "3 for casual, 2 for
# regular, 1 for hard, none for why are you doing this to yourself" -
# i.e. lives scale with SaveManager.difficulty. Main.gd is scene-coupled
# (wave_label/timer_label/world are @onready references into the real game
# scene) so it can't be safely instantiated standalone in a headless check -
# same constraint AICounterWobbleCheck.gd already hit for Main.gd's
# wave-cadence lines. Source-text assertions for the Main.gd wiring;
# SaveManager.DIFFICULTY_LIVES itself is tested directly since it's a plain
# static const array.

const SaveManagerScript = preload("res://scripts/core/SaveManager.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# --- SaveManager.DIFFICULTY_LIVES: Casual=3, Normal=2, Hard=1, Why=0 ---
	_check("DIFFICULTY_LIVES has one entry per difficulty tier",
		SaveManagerScript.DIFFICULTY_LIVES.size() == SaveManagerScript.DIFFICULTY_NAMES.size())
	_check("Casual (0) gets 3 lives", SaveManagerScript.DIFFICULTY_LIVES[0] == 3)
	_check("Normal (1) gets 2 lives", SaveManagerScript.DIFFICULTY_LIVES[1] == 2)
	_check("Hard (2) gets 1 life", SaveManagerScript.DIFFICULTY_LIVES[2] == 1)
	_check("\"Why would you do this to yourself?\" (3) gets 0 lives", SaveManagerScript.DIFFICULTY_LIVES[3] == 0)
	_check("lives are non-increasing as difficulty rises", SaveManagerScript.DIFFICULTY_LIVES[0] >= SaveManagerScript.DIFFICULTY_LIVES[1] and SaveManagerScript.DIFFICULTY_LIVES[1] >= SaveManagerScript.DIFFICULTY_LIVES[2] and SaveManagerScript.DIFFICULTY_LIVES[2] >= SaveManagerScript.DIFFICULTY_LIVES[3])

	# --- Main.gd wiring ---
	var main_source: String = FileAccess.get_file_as_string("res://scripts/core/Main.gd")

	_check("player_lives_remaining is seeded from SaveManager.DIFFICULTY_LIVES[difficulty]",
		main_source.contains("var player_lives_remaining: int = SaveManager.DIFFICULTY_LIVES[SaveManager.difficulty]"))
	_check("_close_garage() refills lives from the difficulty table on every deploy (same checkpoint as last_garage_wave)",
		main_source.contains("player_lives_remaining = SaveManager.DIFFICULTY_LIVES[SaveManager.difficulty]"))
	_check("_on_player_died() checks lives before running the full death sequence",
		main_source.contains("if player_lives_remaining > 1:"))
	_check("a life-saved respawn heals hp back to max",
		main_source.contains("player.hp = player.max_hp") and main_source.contains("player.is_dead = false"))
	_check("a life-saved respawn restores shield_hp to max",
		main_source.contains("player.shield_hp = player.max_shield_hp"))
	_check("the true (last-life) death still prints the original GAME OVER line",
		main_source.contains("GAME OVER - MAGNIFICENT EXPLOSION"))
	_check("HUD shows remaining lives",
		main_source.contains("Lives: \" + str(player_lives_remaining)"))
	_check("no leftover reference to the old flat MAX_PLAYER_LIVES constant",
		not main_source.contains("MAX_PLAYER_LIVES"))

	if failures == 0:
		print("PASS: difficulty-scaled lives wired into _on_player_died()/_close_garage()/_update_hud()")
	get_tree().quit(0 if failures == 0 else 1)
