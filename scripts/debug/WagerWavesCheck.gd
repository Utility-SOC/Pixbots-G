extends Node

# Wager Waves: the window opens from wave 3 when the player can afford a stake; one condition at a time (same key cancels);
# starting the wave takes the stake and applies the condition; clearing it pays stake plus winnings, dying loses the stake;
# the conditions really change enemy count/HP and the player's damage taken / weapon output; nothing changes when no wager.

const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

class StubMain extends Node2D:
	var player = null
	var player_scrap: int = 1000
	var current_wave: int = 5
	var lines: Array = []
	func show_dialogue(speaker, text, _c = Color.WHITE, _d = 4.0):
		lines.append(text)

func _ready():
	_check("stake is 15%% of scrap, at least 10, never more than you have", WagerWaves.stake_for(1000) == 150 and WagerWaves.stake_for(40) == 10 and WagerWaves.stake_for(9) == 0)
	_check("payouts scale with the condition", WagerWaves.payout_for("horde", 100) == 160 and WagerWaves.payout_for("glass", 100) == 180)
	var main = StubMain.new()
	add_child(main)
	var p = MechScript.new()
	p.is_player = true
	p.max_hp = 100000.0
	p.hp = 100000.0
	main.add_child(p)
	p.set_physics_process(false)
	main.player = p
	var w = WagerWaves.new()
	w.main = main
	add_child(w)
	w.open_window(2)
	_check("no window before wave 3", not w.window_open)
	main.player_scrap = 5
	w.open_window(5)
	_check("no window when the stake is unaffordable", not w.window_open)
	main.player_scrap = 1000
	w.open_window(5)
	_check("the window opens", w.window_open)
	_check("choosing works and the same key cancels", w.choose("horde") and w.chosen == "horde" and w.choose("horde") and w.chosen == "")
	w.begin_wave()
	_check("no wager: nothing changes", w.active == "" and main.player_scrap == 1000 and w.count_mult() == 1.0 and w.hp_mult() == 1.0)

	w.open_window(5)
	w.choose("horde")
	w.begin_wave()
	_check("horde: the stake is paid up front and counts rise", main.player_scrap == 850 and w.count_mult() == 1.6)
	w.resolve(true)
	_check("won: stake back plus 1.6x (%d)" % main.player_scrap, main.player_scrap == 850 + 150 + 240)
	_check("the result is recorded", w.results.size() == 1 and w.results[0]["won"] and w.results[0]["delta"] == 240)

	main.player_scrap = 1000
	w.open_window(6)
	w.choose("ironclad")
	w.begin_wave()
	_check("ironclad: enemy HP x1.8", w.hp_mult() == 1.8)
	w.resolve(false)
	_check("lost: the stake is gone (%d)" % main.player_scrap, main.player_scrap == 850 and w.results[1]["delta"] == -150 and w.hp_mult() == 1.0)

	w.open_window(7)
	w.choose("glass")
	w.begin_wave()
	var before = p.hp
	p.apply_damage(1000.0, "RAW")
	_check("glass: damage taken doubles (%.0f)" % (before - p.hp), absf((before - p.hp) - 2000.0) < 1.0)
	w.resolve(true)
	before = p.hp
	p.apply_damage(1000.0, "RAW")
	_check("and returns to normal afterwards (%.0f)" % (before - p.hp), absf((before - p.hp) - 1000.0) < 1.0)

	w.open_window(8)
	w.choose("feeble")
	w.begin_wave()
	_check("feeble: weapons at 70%", is_equal_approx(p.wager_weapons_mult, 0.7))
	w.resolve(true)
	_check("and restored", p.wager_weapons_mult == 1.0)
	print("WagerWavesCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
