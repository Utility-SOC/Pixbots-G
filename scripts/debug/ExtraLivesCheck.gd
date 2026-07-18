extends Node

# Regression harness for the "3 lives so it isn't game over as soon as I get
# killed once" feature. Main.gd is scene-coupled (wave_label/timer_label/
# world are @onready references into the real game scene) so it can't be
# safely instantiated standalone in a headless check - same constraint
# AICounterWobbleCheck.gd already hit for Main.gd's wave-cadence lines.
# Source-text assertions instead, same technique used there.

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var main_source: String = FileAccess.get_file_as_string("res://scripts/core/Main.gd")

	_check("MAX_PLAYER_LIVES const exists and is 3",
		main_source.contains("const MAX_PLAYER_LIVES = 3"))
	_check("player_lives_remaining starts at MAX_PLAYER_LIVES",
		main_source.contains("var player_lives_remaining: int = MAX_PLAYER_LIVES"))
	_check("_close_garage() refills lives on every deploy (same checkpoint as last_garage_wave)",
		main_source.contains("player_lives_remaining = MAX_PLAYER_LIVES"))
	_check("_on_player_died() checks lives before running the full death sequence",
		main_source.contains("if player_lives_remaining > 1:"))
	_check("a life-saved respawn heals hp back to max",
		main_source.contains("player.hp = player.max_hp") and main_source.contains("player.is_dead = false"))
	_check("a life-saved respawn restores shield_hp to max",
		main_source.contains("player.shield_hp = player.max_shield_hp"))
	_check("the true (0-lives) death still prints the original GAME OVER line",
		main_source.contains("GAME OVER - MAGNIFICENT EXPLOSION"))
	_check("HUD shows remaining lives",
		main_source.contains("Lives: \" + str(player_lives_remaining)"))

	if failures == 0:
		print("PASS: 3-lives system wired into _on_player_died()/_close_garage()/_update_hud()")
	get_tree().quit(0 if failures == 0 else 1)
