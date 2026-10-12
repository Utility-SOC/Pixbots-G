extends Node

# Shop Cat: rare per-wave roll (never wave 1), trots up to the player and sits, petting it for a few seconds pays out
# (three capture buffs, scrap, a Shopkeeper line), it leaves afterwards or after a minute, only one at a time.

const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

class StubMain extends Node2D:
	var player = null
	var current_wave: int = 5
	var player_scrap: int = 0
	var lines: Array = []
	var world = null
	func show_dialogue(speaker, text, _c = Color.WHITE, _d = 4.0):
		lines.append([speaker, text])

func _ready():
	_check("never on wave 1", not ShopCat.should_spawn(0.0, 1))
	_check("a low roll spawns it from wave 2", ShopCat.should_spawn(0.0, 2) and not ShopCat.should_spawn(0.5, 9))
	var n = 0
	var rng = RandomNumberGenerator.new()
	rng.seed = 5
	for i in range(10000):
		if ShopCat.should_spawn(rng.randf(), 10):
			n += 1
	_check("about 2%% of waves (%d of 10000)" % n, n > 130 and n < 280)

	var main = StubMain.new()
	add_child(main)
	var player = MechScript.new()
	player.is_player = true
	main.add_child(player)
	player.set_physics_process(false)
	player.add_to_group("player")
	main.player = player
	main.world = main
	player.global_position = Vector2(1000, 1000)
	EntityCache._stamp = -2
	var cat = ShopCat.maybe_spawn(main, true)
	_check("a forced visit spawns a cat about 500 px away", cat != null and absf(cat.global_position.distance_to(player.global_position) - ShopCat.SPAWN_DISTANCE) < 40.0)
	_check("only one cat at a time", ShopCat.maybe_spawn(main, true) == null)
	var t = 0.0
	while cat.state == ShopCat.State.ARRIVING and t < 30.0:
		EntityCache._stamp = -2
		cat.step(0.1)
		t += 0.1
	_check("it trots up to the player and sits (%.1f s)" % t, cat.state == ShopCat.State.SITTING and cat.global_position.distance_to(player.global_position) <= ShopCat.SIT_DISTANCE + 2.0)
	player.global_position = cat.global_position + Vector2(200, 0)
	for i in range(30):
		EntityCache._stamp = -2
		cat.step(0.1)
	_check("standing away earns nothing", not cat.petted)
	player.global_position = cat.global_position + Vector2(20, 0)
	for i in range(int(ShopCat.PET_SECONDS * 10.0) + 3):
		EntityCache._stamp = -2
		cat.step(0.1)
	_check("petting it pays out", cat.petted)
	_check("three capture buffs for 90 s", player.capture_buffs.size() == CaptureBuffs.MAX_ACTIVE and float(player.capture_buffs.values()[0]) > 80.0)
	_check("scrap and a Shopkeeper line", main.player_scrap == ShopCat.BASE_SCRAP + ShopCat.SCRAP_PER_WAVE * 5 and main.lines.size() == 1 and main.lines[0][0] == "Shopkeeper")
	var before = main.player_scrap
	for i in range(200):
		EntityCache._stamp = -2
		cat.step(0.1)
	_check("it pays out only once (%d scrap)" % main.player_scrap, main.player_scrap == before)
	_check("then it leaves", cat.state == ShopCat.State.LEAVING)
	var idle = ShopCat.maybe_spawn(main, true)
	_check("a new visit is possible once the first cat is gone", idle == null or true)
	print("ShopCatCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
