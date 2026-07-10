class_name TileActionMenu
extends RefCounted

# Tile/part economy actions (scrap, upgrade, repair, infuse, modifier
# extraction) - split out of GarageMenu.gd, see SightAndSearch.gd/
# MagnetSystem.gd for the established composed-RefCounted-helper pattern
# this follows. All state (pending_expansion_hexes, chip_count_label,
# active_component, inventory) and the shared tile_scrap_value/
# tile_upgrade_cost/_show_scrap_float/_slot_display_name utilities stay on
# GarageMenu itself (the latter are used well outside tile actions - the
# Black Market and sell-all also derive costs from tile_scrap_value) - only
# the tile-action behavior moved here. Lazily constructed the first time a
# tile action fires (see GarageMenu's thin wrappers below).
#
# repair_all/infuse_part/upgrade_part/extract_modifier/infuse_chip keep thin
# wrappers on GarageMenu (not moved) - they're connected directly as
# Callables (repair_btn.pressed.connect(_on_repair_all), etc.) in _setup_ui,
# so they have to be reachable as plain GarageMenu-level methods regardless.
# scrap_tile/upgrade_tile/update_chip_label have no wrapper - their only
# callers (_on_inventory_item_gui_input, _refresh_component_ui) are plain
# internal calls updated to go through this helper directly.

const MAX_TILE_LEVEL = 10
const INFUSE_COST = 100
const INFUSE_XP = 100
const UPGRADE_COSTS = [0, 500, 1500, 4000, 10000] # cost to REACH rarity index

var garage: GarageMenu

func _init(p_garage: GarageMenu):
	garage = p_garage

func scrap_tile(tile: HexTile):
	var main = garage.get_parent()
	if main and main.get("player_scrap") != null:
		var scrap_value = garage.tile_scrap_value(tile)
		main.player_scrap += scrap_value
		garage.inventory.erase(tile)
		garage._refresh_inventory_ui()
		garage._show_scrap_float("+" + str(scrap_value) + " Scrap")

# Middle-click: spend scrap to level a tile up (+10% power per level via
# the shared _get_power_multiplier() curve every tile type already uses).
func upgrade_tile(tile: HexTile):
	var main = garage.get_parent()
	if not main or main.get("player_scrap") == null:
		return
	if tile.level >= MAX_TILE_LEVEL:
		garage._show_scrap_float("Max level!", Color(0.9, 0.4, 0.3))
		return
	var cost = garage.tile_upgrade_cost(tile)
	if main.player_scrap < cost:
		garage._show_scrap_float("Need " + str(cost) + " scrap", Color(0.9, 0.4, 0.3))
		return
	main.player_scrap -= cost
	tile.level += 1
	garage._refresh_inventory_ui()
	garage._show_scrap_float("Lv." + str(tile.level) + "  (-" + str(cost) + " scrap)", Color(0.4, 1.0, 0.5))

func repair_all():
	var main = garage.get_parent()
	if not main or main.get("player") == null or main.get("player_scrap") == null:
		return
	var mech = main.player

	var missing_hp = max(0.0, mech.max_hp - mech.hp)
	var damaged_tiles = 0
	var disabled_tiles = 0
	var destroyed_tiles = 0
	for comp in mech.components.values():
		for tile in comp.hex_grid.get_all_tiles():
			if "power_lost" in tile and tile.power_lost:
				destroyed_tiles += 1
			elif tile.is_disabled:
				disabled_tiles += 1
			elif tile.hp < tile.max_hp:
				damaged_tiles += 1

	# Destroyed (power_lost) tiles - the "grave enough hit" outcome from
	# Mech._roll_component_disable - cost more than an ordinary knocked-out
	# tile since they'd otherwise never come back on their own.
	var cost = int(ceil(missing_hp / 2.0)) + disabled_tiles * 25 + destroyed_tiles * 100
	if cost <= 0 and damaged_tiles == 0:
		garage._show_scrap_float("Nothing to repair", Color(0.7, 0.7, 0.7))
		return
	cost = max(cost, 1)
	if main.player_scrap < cost:
		garage._show_scrap_float("Need " + str(cost) + " scrap", Color(0.9, 0.4, 0.3))
		return

	main.player_scrap -= cost
	mech.hp = mech.max_hp
	for comp in mech.components.values():
		for tile in comp.hex_grid.get_all_tiles():
			tile.hp = tile.max_hp
			tile.is_disabled = false
			tile.disable_timer = 0.0
			tile.times_disabled = 0
			if "power_lost" in tile:
				tile.power_lost = false
	garage._refresh_inventory_ui() # updates the scrap label
	garage._show_scrap_float("Fully repaired  (-" + str(cost) + " scrap)", Color(0.4, 1.0, 0.5))

func infuse_part():
	var main = garage.get_parent()
	if not main or main.get("player_scrap") == null or not garage.active_component:
		return
	if main.player_scrap < INFUSE_COST:
		garage._show_scrap_float("Need " + str(INFUSE_COST) + " scrap", Color(0.9, 0.4, 0.3))
		return
	main.player_scrap -= INFUSE_COST
	var before_level = garage.active_component.infusion_level
	garage.active_component.add_infusion_xp(INFUSE_XP)
	garage._refresh_inventory_ui() # updates the scrap label
	if garage.active_component.infusion_level > before_level:
		garage._show_scrap_float("INFUSION LEVEL UP! (Lv." + str(garage.active_component.infusion_level) + ")", Color(0.3, 0.9, 1.0))
	else:
		garage._show_scrap_float("+%d XP (%d/%d)" % [INFUSE_XP, garage.active_component.infusion_xp, 500 + garage.active_component.infusion_level * 500], Color(0.4, 1.0, 0.5))

func upgrade_part():
	var main = garage.get_parent()
	if not garage.active_component or not main or main.get("player_scrap") == null:
		return
	if garage.active_component.rarity >= HexTile.Rarity.MYTHIC:
		garage._show_scrap_float("Already Mythic!", Color(0.7, 0.7, 0.7))
		return
	var cost = UPGRADE_COSTS[garage.active_component.rarity + 1]
	if main.player_scrap < cost:
		garage._show_scrap_float("Need " + str(cost) + " scrap", Color(0.9, 0.4, 0.3))
		return
	# Consume one same-slot salvage component - drops feed the upgrade loop
	var salvage_idx = -1
	if main.get("player_component_inventory") != null:
		for i in range(main.player_component_inventory.size()):
			var c = main.player_component_inventory[i]
			if c != garage.active_component and c.slot_type == garage.active_component.slot_type:
				salvage_idx = i
				break
	if salvage_idx < 0:
		garage._show_scrap_float("Need a spare %s to sacrifice" % garage._slot_display_name(garage.active_component.slot_type), Color(0.9, 0.4, 0.3))
		return

	main.player_scrap -= cost
	main.player_component_inventory.remove_at(salvage_idx)
	var granted = garage.active_component.upgrade_rarity()
	garage.pending_expansion_hexes += granted
	garage._mark_player_grid_dirty()
	garage._refresh_component_ui()
	garage._refresh_inventory_ui()
	garage._show_scrap_float("UPGRADED! Click %d pulsing cells to grow the part" % granted, Color(0.3, 0.9, 1.0))
	garage.grid_renderer.queue_redraw()

func update_chip_label():
	var main = garage.get_parent()
	if garage.chip_count_label and main and main.get("player_modifier_chips") != null:
		var txt = "Chips: %d" % main.player_modifier_chips.size()
		if main.player_modifier_chips.size() > 0:
			var next = main.player_modifier_chips[0]
			txt += "  (next: %s +%d%%)" % [str(next["stat"]), int(round((float(next["value"]) - 1.0) * 100.0))]
		garage.chip_count_label.text = txt

func extract_modifier():
	var main = garage.get_parent()
	if not main or main.get("player_modifier_chips") == null or main.get("player_component_inventory") == null:
		return
	# First spare component carrying a stat modifier gets sacrificed
	for i in range(main.player_component_inventory.size()):
		var c = main.player_component_inventory[i]
		var mods = c.get("stat_modifiers")
		if mods != null and not mods.is_empty():
			var stat = mods.keys()[0]
			main.player_modifier_chips.append({"stat": stat, "value": float(mods[stat])})
			main.player_component_inventory.remove_at(i)
			update_chip_label()
			garage._show_scrap_float("Extracted %s chip (part destroyed)" % str(stat), Color(0.3, 0.9, 1.0))
			return
	garage._show_scrap_float("No spare part with a modifier to extract", Color(0.9, 0.4, 0.3))

func infuse_chip():
	var main = garage.get_parent()
	if not garage.active_component or not main or main.get("player_modifier_chips") == null:
		return
	if main.player_modifier_chips.is_empty():
		garage._show_scrap_float("No chips - extract one first", Color(0.9, 0.4, 0.3))
		return
	var chip = main.player_modifier_chips.pop_front()
	var stat = str(chip["stat"])
	var bonus = float(chip["value"]) - 1.0
	var current = float(garage.active_component.stat_modifiers.get(stat, 1.0))
	# Chips stack, capped at +50% per stat per component ("constants later")
	garage.active_component.stat_modifiers[stat] = min(1.5, current + bonus)
	update_chip_label()
	garage._mark_player_grid_dirty()
	garage._show_scrap_float("%s now +%d%% on this part" % [stat, int(round((garage.active_component.stat_modifiers[stat] - 1.0) * 100.0))], Color(0.4, 1.0, 0.5))
