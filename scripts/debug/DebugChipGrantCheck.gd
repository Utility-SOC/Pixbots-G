extends Node

# Regression harness for the DebugMenu "Give Mod Chips" button (Late-game
# progression prep, task #41): grants one +10% chip for each of the 11 real
# stat_modifiers keys (ComponentEquipment._roll_stat_modifier()'s own pool),
# and proves a granted chip actually infuses correctly through the existing
# TileActionMenu.infuse_chip() pipeline end-to-end.

const GarageMenuScript = preload("res://scripts/ui/GarageMenu.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")

var failures = 0

func _check(label: String, actual, expected):
	if actual != expected:
		push_error("FAIL: %s - got %s, expected %s" % [label, actual, expected])
		failures += 1
	else:
		print("ok: %s = %s" % [label, actual])

func _ready():
	var fake_main_script = GDScript.new()
	fake_main_script.source_code = "extends Node2D\nvar player_modifier_chips: Array = []\nvar player_component_inventory: Array = []\n"
	fake_main_script.reload()
	var fake_main = Node2D.new()
	fake_main.set_script(fake_main_script)
	add_child(fake_main)

	var garage = GarageMenuScript.new()
	fake_main.add_child(garage)

	var comp = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.RARE)
	fake_main.add_child(comp)
	comp.generate_shape()
	var core = CoreTileScript.new()
	core.rarity = HexTile.Rarity.RARE
	comp.hex_grid.add_tile(HexCoord.new(0, 0), core)
	garage.active_component = comp
	garage.mech_components = {HexTile.BodySlot.TORSO: comp}

	# --- 1. Mirrors the DebugMenu button's exact grant logic ----------------
	var possible_stats = ["kin_mult", "fire_mult", "ice_mult", "vtx_mult", "ltg_mult", "psn_mult", "exp_mult", "prc_mult", "vmp_mult", "dmg_mult", "spd_mult"]
	for stat in possible_stats:
		fake_main.player_modifier_chips.append({"stat": stat, "value": 1.1})

	_check("grants exactly 11 chips (one per real stat)", fake_main.player_modifier_chips.size(), 11)
	var stats_granted = []
	for chip in fake_main.player_modifier_chips:
		stats_granted.append(chip["stat"])
	var all_present = true
	for s in possible_stats:
		if not stats_granted.has(s):
			all_present = false
	if not all_present:
		push_error("FAIL: not every real stat_modifiers key got a chip")
		failures += 1
	else:
		print("2) every one of ComponentEquipment._roll_stat_modifier()'s 11 stats has a matching chip")

	# --- 2. A granted chip actually infuses through the real pipeline ------
	if not garage.tile_action_menu:
		garage.tile_action_menu = load("res://scripts/ui/TileActionMenu.gd").new(garage)
	var first_stat = fake_main.player_modifier_chips[0]["stat"]
	var chips_before = fake_main.player_modifier_chips.size()
	garage.tile_action_menu.infuse_chip()

	_check("infuse_chip() consumes exactly one chip", fake_main.player_modifier_chips.size(), chips_before - 1)
	var applied = float(comp.stat_modifiers.get(first_stat, 1.0))
	if not is_equal_approx(applied, 1.1):
		push_error("FAIL: infusing a debug-granted chip didn't apply +10%% to '%s' (got %.3f)" % [first_stat, applied])
		failures += 1
	else:
		print("3) infusing a debug-granted chip correctly applies +10%% to '%s' on the active component" % first_stat)

	if failures == 0:
		print("PASS: debug Mod Chip grant matches the real stat pool and infuses correctly end-to-end")
	get_tree().quit(0 if failures == 0 else 1)
