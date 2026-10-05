extends Node

# Long-run economy: unsecured haul (lose 40% per life lost, all on game over, secured by any
# garage visit) and the uncapped per-wave streak bonus to drop chances.

var failures := 0
var _main: Node

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _fill(n_tiles: int, n_comps: int, n_chips: int):
	_main._haul.clear()
	_main.player_inventory.clear()
	_main.player_component_inventory.clear()
	_main.player_modifier_chips.clear()
	for i in range(n_tiles):
		var t = load("res://scripts/tiles/AmplifierTile.gd").new()
		_main.player_inventory.append(t)
		_main.note_haul("tile", t)
	for i in range(n_comps):
		var c = {"name": "comp%d" % i}
		_main.player_component_inventory.append(c)
		_main.note_haul("component", c)
	for i in range(n_chips):
		var ch = {"traits": [i], "id": i}
		_main.player_modifier_chips.append(ch)
		_main.note_haul("chip", ch)

func _total() -> int:
	return _main.player_inventory.size() + _main.player_component_inventory.size() + _main.player_modifier_chips.size()

func _ready():
	_main = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(_main)
	(func(): get_tree().current_scene = _main).call_deferred()
	for i in range(30):
		await get_tree().process_frame

	# --- 40% per life lost (exact at 10 items; averages out at small sizes) ---------------
	_fill(6, 2, 2)
	var lost = _main._apply_haul_loss(_main.HAUL_LOSS_PER_LIFE)
	_check("40%% of a 10-item haul = 4 items lost (lost %d)" % lost, lost == 4)
	_check("lost items are really gone from the inventories (%d left)" % _total(), _total() == 6 and _main.haul_count() == 6)
	var sum = 0
	for t in range(400):
		_fill(1, 1, 0) # 2 items -> expected loss 0.8 per life
		sum += _main._apply_haul_loss(0.4)
	var avg = float(sum) / 400.0
	_check("small hauls still lose ~40%% on average (%.2f of 2 items)" % avg, avg > 0.65 and avg < 0.95)

	# --- game over takes everything ------------------------------------------------------------
	_fill(5, 3, 2)
	_main._apply_haul_loss(1.0)
	_check("game over loses the whole haul", _total() == 0 and _main.haul_count() == 0)

	# --- a garage visit secures it (nothing lost afterwards) --------------------------------
	_fill(4, 2, 2)
	_main._secure_haul()
	var after = _main._apply_haul_loss(1.0)
	_check("secured items are safe even from a game-over loss", after == 0 and _total() == 8)

	# --- items that were never in the haul are untouched -----------------------------------
	_fill(3, 0, 0)
	var keeper = load("res://scripts/tiles/AmplifierTile.gd").new()
	_main.player_inventory.append(keeper) # not noted as haul (e.g. starter/secured stock)
	_main._apply_haul_loss(1.0)
	_check("non-haul inventory survives a total haul loss", _main.player_inventory.has(keeper) and _main.player_inventory.size() == 1)

	# --- streak bonus: uncapped, per wave since the garage ---------------------------------------
	LootManager.garage_wave = 10
	LootManager.current_wave = 10
	_check("no streak bonus at the garage wave", is_equal_approx(LootManager.streak_multiplier(), 1.0))
	LootManager.current_wave = 20
	_check("+3%% per wave since the garage (%.2f at +10)" % LootManager.streak_multiplier(), is_equal_approx(LootManager.streak_multiplier(), 1.3))
	LootManager.current_wave = 210
	_check("uncapped (%.2f at +200 waves)" % LootManager.streak_multiplier(), is_equal_approx(LootManager.streak_multiplier(), 7.0))
	LootManager.current_wave = 10
	var base = LootManager.drop_chance("Amplifier", HexTile.Rarity.RARE, false)
	LootManager.current_wave = 60
	var boosted = LootManager.drop_chance("Amplifier", HexTile.Rarity.RARE, false)
	_check("drop chance rises with the streak (%.4f -> %.4f)" % [base, boosted], boosted > base * 1.5)
	var structural_base = LootManager.drop_chance("Left Arm Link", HexTile.Rarity.RARE, false)
	LootManager.current_wave = 10
	var structural_now = LootManager.drop_chance("Left Arm Link", HexTile.Rarity.RARE, false)
	_check("structural drops are not boosted by the streak", is_equal_approx(structural_base, structural_now))

	if failures == 0:
		print("PASS: haul at risk (40%/life, all on game over, secured by the garage) and uncapped streak bonus")
	get_tree().quit(0 if failures == 0 else 1)
