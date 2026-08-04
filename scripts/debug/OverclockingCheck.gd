extends Node

# Regression harness for the Overclocking prestige system (Late-game
# progression, execution queue item 2) - see ComponentEquipment.gd's
# header comment and the plan at
# C:\Users\Utility\.claude\plans\effervescent-drifting-kazoo.md for the
# full design. Covers: chip capacity formula, equip/unequip round-trip,
# capacity enforcement, stat-cap semantics (chip-touched stats capped,
# infusion-only stats NOT retroactively capped), overclock gating/effect,
# both reward paths, repeatability, capacity recalibration, the mass
# floor, save/load round-trip, and legacy pre-v5 save migration.
#
# UI harness mirrors GarageTabPreservationCheck.gd's proven minimal setup
# (component_tabs/grid_renderer/stats_label - the exact set
# _refresh_component_ui()/_populate_component_tabs() actually touch
# without crashing on a null reference) plus DebugChipGrantCheck.gd's
# fake-Main pattern (player_scrap/player_modifier_chips/
# player_component_inventory - the fields TileActionMenu's actions read
# off garage.get_parent()).

const GarageMenuScript = preload("res://scripts/ui/GarageMenu.gd")
const GarageGridRendererScript = preload("res://scripts/ui/GarageGridRenderer.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")
const SaveManagerScript = preload("res://scripts/core/SaveManager.gd")
const TileActionMenuScript = preload("res://scripts/ui/TileActionMenu.gd")

var failures = 0

func _check(label: String, actual, expected):
	if actual != expected:
		push_error("FAIL: %s - got %s, expected %s" % [label, actual, expected])
		failures += 1
	else:
		print("ok: %s = %s" % [label, actual])

func _check_true(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _make_garage() -> GarageMenu:
	var fake_main_script = GDScript.new()
	fake_main_script.source_code = "extends Node2D\nvar player_modifier_chips: Array = []\nvar player_component_inventory: Array = []\nvar player_scrap: int = 1000000\n"
	fake_main_script.reload()
	var fake_main = Node2D.new()
	fake_main.set_script(fake_main_script)
	add_child(fake_main)

	var garage = GarageMenuScript.new()
	fake_main.add_child(garage)
	garage.component_tabs = TabBar.new()
	garage.add_child(garage.component_tabs)
	garage.grid_renderer = GarageGridRendererScript.new()
	garage.add_child(garage.grid_renderer)
	garage.stats_label = Label.new()
	garage.add_child(garage.stats_label)
	return garage

func _make_component(rarity: int) -> ComponentEquipment:
	var comp = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, rarity)
	comp.generate_shape()
	var core = CoreTileScript.new()
	core.rarity = rarity
	comp.hex_grid.add_tile(HexCoord.new(0, 0), core)
	return comp

func _ready():
	# --- 1. Chip capacity formula at each rarity tier ------------------------
	for r in range(HexTile.Rarity.MYTHIC + 1):
		var comp = _make_component(r)
		_check("get_chip_capacity() at rarity %d" % r, comp.get_chip_capacity(), ComponentEquipmentScript.BASE_CHIP_CAPACITY_BY_RARITY[r])

	var oc_comp = _make_component(HexTile.Rarity.MYTHIC)
	oc_comp.overclock_count = 1
	_check("capacity drops by OVERCLOCK_CAPACITY_PENALTY after one overclock",
		oc_comp.get_chip_capacity(),
		ComponentEquipmentScript.BASE_CHIP_CAPACITY_BY_RARITY[HexTile.Rarity.MYTHIC] - ComponentEquipmentScript.OVERCLOCK_CAPACITY_PENALTY)

	# --- 2. Equip/unequip round-trip + 3. capacity enforcement ---------------
	var garage = _make_garage()
	var comp = _make_component(HexTile.Rarity.RARE) # capacity 4
	garage.active_component = comp
	garage.mech_components = {HexTile.BodySlot.TORSO: comp}
	var main = garage.get_parent()

	main.player_modifier_chips = [{"traits": [{"stat": "kin_mult", "value": 1.2}]}]
	garage.tile_action_menu = TileActionMenuScript.new(garage)
	garage.tile_action_menu.equip_chip()
	_check("equip_chip() moves the chip out of the flat pool", main.player_modifier_chips.size(), 0)
	_check("equip_chip() adds it to equipped_chips", comp.equipped_chips.size(), 1)
	_check_true("stat_modifiers reflects the equipped chip", is_equal_approx(float(comp.stat_modifiers.get("kin_mult", 1.0)), 1.2))

	garage.tile_action_menu.unequip_chip(0)
	_check("unequip_chip() returns the chip to the flat pool", main.player_modifier_chips.size(), 1)
	_check("unequip_chip() removes it from equipped_chips", comp.equipped_chips.size(), 0)
	_check_true("stat_modifiers no longer reflects the unequipped chip", not comp.stat_modifiers.has("kin_mult"))

	# Fill to capacity (4), then try one more - should be rejected.
	main.player_modifier_chips = [
		{"traits": [{"stat": "fire_mult", "value": 1.1}]}, {"traits": [{"stat": "ice_mult", "value": 1.1}]},
		{"traits": [{"stat": "vtx_mult", "value": 1.1}]}, {"traits": [{"stat": "ltg_mult", "value": 1.1}]},
		{"traits": [{"stat": "psn_mult", "value": 1.1}]},
	]
	for i in 4:
		garage.tile_action_menu.equip_chip()
	_check("component filled to its capacity (4)", comp.equipped_chips.size(), 4)
	var pool_before_overflow = main.player_modifier_chips.size()
	garage.tile_action_menu.equip_chip() # 5th attempt, should be rejected
	_check("equipping past capacity is rejected - chip stays in the pool", main.player_modifier_chips.size(), pool_before_overflow)
	_check("equipping past capacity doesn't grow equipped_chips", comp.equipped_chips.size(), 4)

	# --- 4. Same-stat stacking cap + infusion-only stats NOT retroactively capped ---
	var cap_comp = _make_component(HexTile.Rarity.LEGENDARY)
	cap_comp.infusion_stat_modifiers["dmg_mult"] = 1.6 # simulates several uncapped infusion rolls, no chips involved
	cap_comp._recompute_stat_modifiers()
	_check_true("a stat raised ONLY by infusion rolls is NOT retroactively capped at 1.5",
		is_equal_approx(float(cap_comp.stat_modifiers.get("dmg_mult", 1.0)), 1.6))
	cap_comp.equipped_chips.append({"traits": [{"stat": "dmg_mult", "value": 1.2}]})
	cap_comp._recompute_stat_modifiers()
	_check_true("once a chip touches that same stat, the COMBINED total is capped at CHIP_STAT_CAP",
		is_equal_approx(float(cap_comp.stat_modifiers.get("dmg_mult", 1.0)), ComponentEquipmentScript.CHIP_STAT_CAP))

	# --- 5. can_overclock()/overclock_part() gating ---------------------------
	var low_rarity_garage = _make_garage()
	var low_comp = _make_component(HexTile.Rarity.RARE)
	low_rarity_garage.active_component = low_comp
	low_rarity_garage.mech_components = {HexTile.BodySlot.TORSO: low_comp}
	low_rarity_garage.tile_action_menu = TileActionMenuScript.new(low_rarity_garage)
	_check_true("can_overclock() is false below Mythic", not low_comp.can_overclock())
	var scrap_before = low_rarity_garage.get_parent().player_scrap
	low_rarity_garage.tile_action_menu.overclock_part()
	_check("overclock_part() below Mythic is a no-op (no scrap spent)", low_rarity_garage.get_parent().player_scrap, scrap_before)

	var poor_garage = _make_garage()
	var poor_comp = _make_component(HexTile.Rarity.MYTHIC)
	poor_garage.active_component = poor_comp
	poor_garage.mech_components = {HexTile.BodySlot.TORSO: poor_comp}
	poor_garage.get_parent().player_scrap = 0
	poor_garage.tile_action_menu = TileActionMenuScript.new(poor_garage)
	poor_garage.tile_action_menu.overclock_part()
	_check("overclock_part() with insufficient scrap is rejected (still 0)", poor_garage.get_parent().player_scrap, 0)
	_check("overclock_part() with insufficient scrap doesn't mutate overclock_count", poor_comp.overclock_count, 0)

	# --- 6. Overclock effect (bypassing the choice popup - call _apply_overclock directly) ---
	var oc_garage = _make_garage()
	var oc_comp2 = _make_component(HexTile.Rarity.MYTHIC)
	oc_garage.active_component = oc_comp2
	oc_garage.mech_components = {HexTile.BodySlot.TORSO: oc_comp2}
	oc_garage.get_parent().player_modifier_chips = [{"traits": [{"stat": "kin_mult", "value": 1.2}]}]
	oc_garage.tile_action_menu = TileActionMenuScript.new(oc_garage)
	oc_garage.tile_action_menu.equip_chip()
	_check("setup: chip equipped before overclocking", oc_comp2.equipped_chips.size(), 1)
	var scrap_before2 = oc_garage.get_parent().player_scrap
	oc_garage.tile_action_menu._apply_overclock("mass", TileActionMenuScript.OVERCLOCK_BASE_COST)
	_check("overclock scrap cost was deducted", oc_garage.get_parent().player_scrap, scrap_before2 - TileActionMenuScript.OVERCLOCK_BASE_COST)
	_check("equipped chips return to the pool on overclock", oc_garage.get_parent().player_modifier_chips.size(), 1)
	_check("equipped_chips clears on overclock", oc_comp2.equipped_chips.size(), 0)
	_check("overclock_count increments", oc_comp2.overclock_count, 1)
	_check("chip capacity immediately reflects the new penalty",
		oc_comp2.get_chip_capacity(),
		ComponentEquipmentScript.BASE_CHIP_CAPACITY_BY_RARITY[HexTile.Rarity.MYTHIC] - ComponentEquipmentScript.OVERCLOCK_CAPACITY_PENALTY)

	# --- 7. Reward - mass path, real Mech ------------------------------------
	var world = Node2D.new()
	add_child(world)
	var mech = MechScript.new()
	mech.is_player = false
	world.add_child(mech)
	mech.set_physics_process(false)
	var mass_comp = _make_component(HexTile.Rarity.MYTHIC)
	mech.equip_component(mass_comp)
	mech._recalculate_grid()
	var mass_before = mech.total_mass
	mass_comp.mass_reduction += TileActionMenuScript.OVERCLOCK_MASS_REDUCTION
	mech._recalculate_grid()
	_check_true("mass reward reduces total_mass by exactly OVERCLOCK_MASS_REDUCTION",
		is_equal_approx(mech.total_mass, mass_before - TileActionMenuScript.OVERCLOCK_MASS_REDUCTION))

	# --- 8. Reward - hex path -------------------------------------------------
	var hex_garage = _make_garage()
	var hex_comp = _make_component(HexTile.Rarity.MYTHIC)
	hex_garage.active_component = hex_comp
	hex_garage.mech_components = {HexTile.BodySlot.TORSO: hex_comp}
	hex_garage.tile_action_menu = TileActionMenuScript.new(hex_garage)
	var pending_before = hex_garage.pending_expansion_hexes
	hex_garage.tile_action_menu._apply_overclock("hex", TileActionMenuScript.OVERCLOCK_BASE_COST)
	_check("hex reward increments pending_expansion_hexes by exactly 1", hex_garage.pending_expansion_hexes, pending_before + 1)

	# --- 9. Repeatability ------------------------------------------------------
	var rep_garage = _make_garage()
	var rep_comp = _make_component(HexTile.Rarity.MYTHIC)
	rep_garage.active_component = rep_comp
	rep_garage.mech_components = {HexTile.BodySlot.TORSO: rep_comp}
	rep_garage.tile_action_menu = TileActionMenuScript.new(rep_garage)
	# _apply_overclock() directly, not overclock_part() - the latter opens
	# a real choice popup (correct in live gameplay, where the player
	# clicks a reward button), which a headless test never clicks and
	# would otherwise leave dangling at process exit.
	rep_garage.tile_action_menu._apply_overclock("mass", TileActionMenuScript.OVERCLOCK_BASE_COST * 1)
	rep_garage.tile_action_menu._apply_overclock("mass", TileActionMenuScript.OVERCLOCK_BASE_COST * 2)
	_check("two overclocks -> overclock_count == 2", rep_comp.overclock_count, 2)
	# get_chip_capacity() floors at 1 (max(1, ...)) - two overclocks' full
	# penalty (6) would otherwise drive a base-6 Mythic capacity to 0.
	_check("capacity penalty doubles after two overclocks (floored at 1)",
		rep_comp.get_chip_capacity(),
		max(1, ComponentEquipmentScript.BASE_CHIP_CAPACITY_BY_RARITY[HexTile.Rarity.MYTHIC] - (2 * ComponentEquipmentScript.OVERCLOCK_CAPACITY_PENALTY)))
	_check_true("mass_reduction stacks across both overclocks",
		is_equal_approx(rep_comp.mass_reduction, TileActionMenuScript.OVERCLOCK_MASS_REDUCTION * 2))

	# --- 10. Recalibration -----------------------------------------------------
	var recal_garage = _make_garage()
	var recal_comp = _make_component(HexTile.Rarity.MYTHIC)
	recal_garage.active_component = recal_comp
	recal_garage.mech_components = {HexTile.BodySlot.TORSO: recal_comp}
	recal_garage.tile_action_menu = TileActionMenuScript.new(recal_garage)
	recal_comp.overclock_count = 1 # simulate one overclock, penalty = OVERCLOCK_CAPACITY_PENALTY
	var cap_before_recal = recal_comp.get_chip_capacity()
	recal_garage.tile_action_menu.recalibrate_chip_capacity()
	_check("recalibration raises capacity by 1", recal_comp.get_chip_capacity(), cap_before_recal + 1)
	# Recalibrate the rest of the way, then confirm it stops at baseline.
	for i in range(ComponentEquipmentScript.OVERCLOCK_CAPACITY_PENALTY - 1):
		recal_garage.tile_action_menu.recalibrate_chip_capacity()
	var baseline = ComponentEquipmentScript.BASE_CHIP_CAPACITY_BY_RARITY[HexTile.Rarity.MYTHIC]
	_check("fully recalibrated capacity never exceeds the pre-overclock baseline", recal_comp.get_chip_capacity(), baseline)
	var upgrades_before = recal_comp.chip_capacity_upgrades
	recal_garage.tile_action_menu.recalibrate_chip_capacity() # should now reject
	_check("recalibrating past full recovery is rejected", recal_comp.chip_capacity_upgrades, upgrades_before)

	# --- 11. Mass floor ---------------------------------------------------------
	var floor_mech = MechScript.new()
	floor_mech.is_player = false
	world.add_child(floor_mech)
	floor_mech.set_physics_process(false)
	var floor_comp = _make_component(HexTile.Rarity.MYTHIC)
	floor_mech.equip_component(floor_comp)
	floor_mech._recalculate_grid()
	floor_comp.mass_reduction = floor_mech.total_mass + 10000.0 # deliberately far larger than raw tile weight
	floor_mech._recalculate_grid()
	_check_true("mass_reduction larger than raw weight still leaves total_mass >= MIN_TOTAL_MASS",
		floor_mech.total_mass >= MechScript.MIN_TOTAL_MASS)

	# --- 12. Save/load round-trip ------------------------------------------------
	var save_comp = _make_component(HexTile.Rarity.MYTHIC)
	save_comp.equipped_chips.append({"traits": [{"stat": "fire_mult", "value": 1.15}]})
	save_comp.mass_reduction = 12.5
	save_comp.overclock_count = 3
	save_comp.chip_capacity_upgrades = 2
	save_comp.infusion_stat_modifiers["dmg_mult"] = 1.1
	save_comp._recompute_stat_modifiers()
	var expected_stat = float(save_comp.stat_modifiers.get("fire_mult", 1.0))

	var save_mgr = SaveManagerScript.new()
	var serialized = save_mgr._serialize_component(save_comp)
	var restored = save_mgr._deserialize_component(serialized)
	_check("equipped_chips survives save/load", restored.equipped_chips.size(), 1)
	_check_true("mass_reduction survives save/load", is_equal_approx(restored.mass_reduction, 12.5))
	_check("overclock_count survives save/load", restored.overclock_count, 3)
	_check("chip_capacity_upgrades survives save/load", restored.chip_capacity_upgrades, 2)
	_check_true("stat_modifiers is correctly re-derived post-load (not stale/missing)",
		is_equal_approx(float(restored.stat_modifiers.get("fire_mult", 1.0)), expected_stat))

	# --- 13. Legacy migration -----------------------------------------------------
	var legacy_cdata = {
		"slot_type": HexTile.BodySlot.TORSO, "rarity": HexTile.Rarity.LEGENDARY,
		"component_name": "Legacy Part", "infusion_level": 2, "infusion_xp": 100,
		"stat_modifiers": {"kin_mult": 1.35}, # OLD key, no equipped_chips/legacy_stat_modifiers at all
		"forbidden_tile_types": [], "tiles": [], "fixed_sinks": [], "valid_hexes": [],
	}
	var migrated = save_mgr._deserialize_component(legacy_cdata)
	_check_true("legacy stat_modifiers blob lands in legacy_stat_modifiers", is_equal_approx(float(migrated.legacy_stat_modifiers.get("kin_mult", 0.0)), 1.35))
	_check("legacy migration leaves equipped_chips empty (no provenance to recover)", migrated.equipped_chips.size(), 0)
	_check_true("legacy migration preserves the same effective bonus (no power loss)",
		is_equal_approx(float(migrated.stat_modifiers.get("kin_mult", 1.0)), 1.35))

	if failures == 0:
		print("PASS: OverclockingCheck - chip capacity, equip/unequip, overclock effects, mass, recalibration, save/load, and legacy migration all behave correctly")
	get_tree().quit(0 if failures == 0 else 1)
