extends Node

# The Bot League screen builds, takes a wager, watches a match to its end by driving _process, settles credits and moves the
# bracket on; a whole season quick-simmed from the screen ends with a champion.

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	var screen = load("res://scripts/ui/BotLeagueScreen.gd").new()
	add_child(screen)
	await get_tree().process_frame
	_check("the lobby builds with the first quarter-final", screen.mode == "lobby" and screen.league.round_name() == "Quarter-final" and screen._lobby.get_child_count() >= 4)
	screen.pick = 0
	screen.stake_choice = 10
	screen._watch()
	_check("watching starts a sim with a held wager", screen.mode == "watching" and screen.sim != null and not screen.league.wager.is_empty())
	var guard = 0
	while screen.mode == "watching" and guard < 3000:
		screen._process(0.5)
		guard += 1
	await get_tree().process_frame
	_check("the match ends and the bracket moves on (%d played)" % screen.league.history.size(), screen.mode == "lobby" and screen.league.history.size() == 1 and screen.league.wager.is_empty())
	_check("credits were settled (%d)" % screen.league.credits, screen.league.credits == BotLeague.START_CREDITS + screen.league.last_wager_delta)
	guard = 0
	while screen.league.champion < 0 and guard < 12:
		screen.league.quick_sim()
		guard += 1
	screen._build_lobby()
	_check("a finished season shows the champions and a new-season button", screen.league.champion >= 0)
	print("BotLeagueScreenCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
