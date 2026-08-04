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
# repair_all/infuse_part/upgrade_part/extract_modifier/equip_chip/
# overclock_part/recalibrate_chip_capacity/open_splice_popup keep thin
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

# Explicit preload, not bare ComponentEquipment - this codebase's established
# convention (see e.g. HexTile.gd/MapGenerator.gd's DestructibleObstacleScript)
# to avoid relying on class_name global resolution.
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const ChipSplicerScript = preload("res://scripts/core/ChipSplicer.gd")
const EnergyPacketScript = preload("res://scripts/core/EnergyPacket.gd")

# Splice popup display: short 3-letter code per stat, and a swatch color -
# the 9 elemental stats reuse EnergyPacket's canonical per-element color
# table (SynergyType) instead of inventing a second one; dmg_mult/spd_mult
# aren't elemental so they get two fixed colors of their own. See
# _chip_stat_color()/_build_stat_pill() below.
const CHIP_STAT_ABBREV = {
	"kin_mult": "KIN", "fire_mult": "FIR", "ice_mult": "ICE", "vtx_mult": "VTX",
	"ltg_mult": "LTG", "psn_mult": "PSN", "exp_mult": "EXP", "prc_mult": "PRC",
	"vmp_mult": "VMP", "dmg_mult": "DMG", "spd_mult": "SPD",
}

# Overclocking (prestige system) - repeatable, per-component, gated on
# Mythic rarity (ComponentEquipment.can_overclock()). Cost scales with
# overclock_count/chip_capacity_upgrades, same rate-limiter every other
# scrap-gated action here already uses.
const OVERCLOCK_BASE_COST = 5000
const OVERCLOCK_MASS_REDUCTION = 5.0
const RECAL_BASE_COST = 800

var garage: GarageMenu
var _popup_helper: GarageTileConfigPopup = null # lazy - reuses its proven click-outside-to-dismiss wiring, see _show_overclock_choice_popup

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

# Human-readable summary of a chip's full trait list (task: Chip Splicing -
# a chip can now carry more than one trait). "[Corrupted] " prefix flags a
# spliced (2+ trait) chip at a glance, same spirit as a rarity color-code
# elsewhere in this codebase. Used everywhere a chip gets shown to the
# player instead of directly reading chip["stat"]/chip["value"], which only
# ever worked for the old single-trait shape.
func _describe_chip(chip: Dictionary) -> String:
	var traits = chip.get("traits", [])
	if traits.is_empty():
		return "(empty chip)"
	var parts = []
	for t in traits:
		var pct = int(round((float(t["value"]) - 1.0) * 100.0))
		parts.append("%s %+d%%" % [str(t["stat"]), pct])
	var prefix = "" if traits.size() == 1 else "[Corrupted] "
	return prefix + ", ".join(parts)

func update_chip_label():
	var main = garage.get_parent()
	if garage.chip_count_label and main and main.get("player_modifier_chips") != null:
		var txt = "Chips: %d" % main.player_modifier_chips.size()
		if main.player_modifier_chips.size() > 0:
			txt += "  (next: %s)" % _describe_chip(main.player_modifier_chips[0])
		garage.chip_count_label.text = txt
	if garage.chip_capacity_label and garage.active_component:
		garage.chip_capacity_label.text = "Capacity: %d/%d" % [garage.active_component.equipped_chips.size(), garage.active_component.get_chip_capacity()]

# Rebuilds the per-component equipped-chip list (one small unequip button
# per chip, showing its full trait breakdown via _describe_chip()). No UI
# previously showed individually-equipped chips - only the merged
# stat_modifiers tooltip line (GarageInventoryPanel._build_component_tooltip).
func refresh_equipped_chips_ui():
	if not garage.equipped_chips_box or not garage.active_component:
		return
	for c in garage.equipped_chips_box.get_children():
		c.queue_free()
	var comp = garage.active_component
	for i in range(comp.equipped_chips.size()):
		var chip = comp.equipped_chips[i]
		var btn = Button.new()
		btn.text = "%s  x" % _describe_chip(chip)
		btn.tooltip_text = "Click to unequip - returns this chip to your inventory"
		btn.pressed.connect(unequip_chip.bind(i))
		garage.equipped_chips_box.add_child(btn)
	update_chip_label()

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
			# Always a plain (single-trait) chip - extraction only ever
			# grabs mods.keys()[0], unchanged scope (see this file's
			# header). Multi-trait Corrupted chips only ever come from
			# splicing (ChipSplicer.gd), never from extraction.
			main.player_modifier_chips.append({"traits": [{"stat": stat, "value": float(mods[stat])}]})
			main.player_component_inventory.remove_at(i)
			update_chip_label()
			garage._show_scrap_float("Extracted %s chip (part destroyed)" % str(stat), Color(0.3, 0.9, 1.0))
			return
	garage._show_scrap_float("No spare part with a modifier to extract", Color(0.9, 0.4, 0.3))

# Equips one chip from the player's flat pool onto the active component, by
# pool index - was infuse_chip(), a one-way merge into a single opaque
# stat_modifiers float. Reworked (task: Overclocking prestige system) into a
# reversible, capacity-gated equip via ComponentEquipment.equip_chip()/
# unequip_chip() - see that file's header comment for the full data-model
# story. Renamed from "infuse" to "equip" partly because "infuse" already
# meant something else entirely in this same file (infuse_part()'s
# XP-leveling system), a naming collision that predates this rework.
func equip_chip_at(index: int):
	var main = garage.get_parent()
	if not garage.active_component or not main or main.get("player_modifier_chips") == null:
		return
	var pool = main.player_modifier_chips
	if pool.is_empty():
		garage._show_scrap_float("No chips - extract one first", Color(0.9, 0.4, 0.3))
		return
	if index < 0 or index >= pool.size():
		return
	var comp = garage.active_component
	if comp.equipped_chips.size() >= comp.get_chip_capacity():
		garage._show_scrap_float("Chip capacity full (%d/%d)" % [comp.equipped_chips.size(), comp.get_chip_capacity()], Color(0.9, 0.4, 0.3))
		return
	var chip = pool[index]
	# equip_chip_data (not equip_chip) - moves the chip's FULL trait set
	# onto the component, not just a first/only trait. Task: Chip Splicing.
	if not comp.equip_chip_data(chip):
		return # shouldn't happen given the capacity check above, but don't lose/remove the chip if it does
	pool.remove_at(index)
	refresh_equipped_chips_ui()
	garage._mark_player_grid_dirty()
	garage._show_scrap_float("Equipped: %s" % _describe_chip(chip), Color(0.4, 1.0, 0.5))

# Default entry point (debug-check call sites, no picker involved) - equips
# whichever chip is next up in the pool. open_equip_chip_popup() below is
# what the real "Equip Mod Chip" button now opens instead, letting the
# player pick a specific chip rather than always getting the front of the
# queue (same spirit as Chip Splicing's picker).
func equip_chip():
	equip_chip_at(0)

# Chip picker for equipping: same pill-row/type-filter/stat-filter widgets
# as open_splice_popup() below (single-select instead of select-2, commits
# via equip_chip_at() instead of splice_chips()). Lets the player choose
# which pool chip lands on the active component instead of always getting
# whatever's next in line.
func open_equip_chip_popup():
	var main = garage.get_parent()
	if not garage.active_component or not main or main.get("player_modifier_chips") == null:
		return
	if main.player_modifier_chips.is_empty():
		garage._show_scrap_float("No chips - extract one first", Color(0.9, 0.4, 0.3))
		return
	if not _popup_helper:
		_popup_helper = GarageTileConfigPopup.new(garage)

	var popup = PopupPanel.new()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	popup.add_child(vbox)

	var title = Label.new()
	title.text = "EQUIP CHIP - select 1"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var type_filter = "all" # "all" | "plain" | "corrupted"
	var stat_filter: Dictionary = {} # stat name -> true; empty = no filter
	var selected_index = -1
	var buttons: Dictionary = {} # pool index -> currently-visible Button

	var list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var equip_btn = Button.new()

	var refresh_equip_btn = func():
		equip_btn.disabled = selected_index < 0

	var rebuild_list: Callable
	rebuild_list = func():
		for c in list_box.get_children():
			c.queue_free()
		buttons.clear()
		for i in range(main.player_modifier_chips.size()):
			var chip = main.player_modifier_chips[i]
			var traits = chip.get("traits", [])
			var is_corrupted = traits.size() > 1
			if type_filter == "plain" and is_corrupted:
				continue
			if type_filter == "corrupted" and not is_corrupted:
				continue
			if not stat_filter.is_empty():
				var has_match = false
				for t in traits:
					if stat_filter.has(str(t["stat"])):
						has_match = true
						break
				if not has_match:
					continue
			var btn = _build_chip_row_button(chip, i == selected_index)
			buttons[i] = btn
			btn.toggled.connect(func(pressed: bool):
				if pressed:
					if selected_index >= 0 and buttons.has(selected_index):
						buttons[selected_index].button_pressed = false
					selected_index = i
				elif selected_index == i:
					selected_index = -1
				refresh_equip_btn.call()
			)
			list_box.add_child(btn)

	# --- Type filter row (All / Plain / Corrupted, single-select) ---
	var type_row = HBoxContainer.new()
	vbox.add_child(type_row)
	var type_buttons: Dictionary = {}
	for kind in ["all", "plain", "corrupted"]:
		var tbtn = Button.new()
		tbtn.text = kind.capitalize()
		tbtn.toggle_mode = true
		tbtn.button_pressed = (kind == "all")
		type_buttons[kind] = tbtn
	for kind in type_buttons:
		type_buttons[kind].pressed.connect(func():
			type_filter = kind
			for k in type_buttons:
				type_buttons[k].button_pressed = (k == kind)
			rebuild_list.call()
		)
		type_row.add_child(type_buttons[kind])

	# --- Per-stat filter row (OR - any selected stat matches) ---
	var stat_row = HBoxContainer.new()
	stat_row.add_theme_constant_override("separation", 3)
	vbox.add_child(stat_row)
	for stat in ComponentEquipmentScript.CHIP_STAT_POOL:
		var sbtn = Button.new()
		sbtn.toggle_mode = true
		sbtn.text = CHIP_STAT_ABBREV.get(stat, stat)
		sbtn.add_theme_color_override("font_color", _chip_stat_color(stat))
		sbtn.custom_minimum_size = Vector2(42, 0)
		sbtn.toggled.connect(func(pressed: bool):
			if pressed:
				stat_filter[stat] = true
			else:
				stat_filter.erase(stat)
			rebuild_list.call()
		)
		stat_row.add_child(sbtn)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(660, 320)
	vbox.add_child(scroll)
	scroll.add_child(list_box)

	rebuild_list.call()

	var button_row = HBoxContainer.new()
	vbox.add_child(button_row)

	equip_btn.text = "Equip Selected"
	equip_btn.disabled = true
	equip_btn.pressed.connect(func():
		if selected_index >= 0:
			equip_chip_at(selected_index)
		popup.hide()
	)
	button_row.add_child(equip_btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(func(): popup.hide())
	button_row.add_child(cancel_btn)

	_popup_helper._show_popup(popup, Vector2(700, 520))

# Removes one equipped chip by index, returning it to the flat pool.
func unequip_chip(index: int):
	var main = garage.get_parent()
	if not garage.active_component or not main or main.get("player_modifier_chips") == null:
		return
	var chip = garage.active_component.unequip_chip(index)
	if chip.is_empty():
		return
	main.player_modifier_chips.append(chip)
	refresh_equipped_chips_ui()
	garage._mark_player_grid_dirty()
	garage._show_scrap_float("Returned to inventory: %s" % _describe_chip(chip), Color(0.7, 0.9, 1.0))

# --- Overclocking (prestige system) -----------------------------------------
# At Mythic rarity, a component can be Overclocked: every equipped chip
# returns to the flat pool, chip capacity permanently drops (see
# ComponentEquipment.get_chip_capacity()), and the player banks a
# permanent mass reduction or an extra placeable hex. Repeatable - see
# ComponentEquipment's own header comment for why.

func overclock_part():
	var main = garage.get_parent()
	if not garage.active_component or not main or main.get("player_scrap") == null:
		return
	var comp = garage.active_component
	if not comp.can_overclock():
		garage._show_scrap_float("Needs Mythic rarity first", Color(0.7, 0.7, 0.7))
		return
	var cost = OVERCLOCK_BASE_COST * (comp.overclock_count + 1)
	if main.player_scrap < cost:
		garage._show_scrap_float("Need %d scrap" % cost, Color(0.9, 0.4, 0.3))
		return
	_show_overclock_choice_popup(cost)

# Nothing is mutated until the player actually clicks a reward button below
# - Cancel (or clicking outside, via the shared dismiss wiring) is a true
# no-op, same "explicit confirmation before a real cost" spirit as every
# other real purchase in this codebase.
func _show_overclock_choice_popup(cost: int):
	if not _popup_helper:
		_popup_helper = GarageTileConfigPopup.new(garage)

	var popup = PopupPanel.new()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	popup.add_child(vbox)

	var title = Label.new()
	title.text = "OVERCLOCK - Pick a permanent reward (%d scrap)" % cost
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var warn = Label.new()
	warn.text = "Every equipped chip returns to inventory. Chip capacity drops by %d until recalibrated." % ComponentEquipmentScript.OVERCLOCK_CAPACITY_PENALTY
	warn.modulate = Color(0.9, 0.7, 0.5)
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(warn)

	var mass_btn = Button.new()
	mass_btn.text = "Permanent Mass Reduction (-%.1f)" % OVERCLOCK_MASS_REDUCTION
	mass_btn.pressed.connect(func():
		popup.hide()
		_apply_overclock("mass", cost)
	)
	vbox.add_child(mass_btn)

	var hex_btn = Button.new()
	hex_btn.text = "+1 Expansion Hex"
	hex_btn.pressed.connect(func():
		popup.hide()
		_apply_overclock("hex", cost)
	)
	vbox.add_child(hex_btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(func(): popup.hide())
	vbox.add_child(cancel_btn)

	_popup_helper._show_popup(popup, Vector2(340, 160))

func _apply_overclock(reward: String, cost: int):
	var main = garage.get_parent()
	if not garage.active_component or not main or main.get("player_scrap") == null:
		return
	var comp = garage.active_component
	main.player_scrap -= cost
	for chip in comp.equipped_chips:
		main.player_modifier_chips.append(chip.duplicate())
	comp.equipped_chips.clear()
	comp.overclock_count += 1
	if reward == "mass":
		comp.mass_reduction += OVERCLOCK_MASS_REDUCTION
	else:
		garage.pending_expansion_hexes += 1
	comp._recompute_stat_modifiers()
	refresh_equipped_chips_ui()
	garage._mark_player_grid_dirty()
	garage._refresh_component_ui()
	garage._refresh_inventory_ui()
	if reward == "mass":
		garage._show_scrap_float("OVERCLOCKED! Permanent -%.1f mass" % OVERCLOCK_MASS_REDUCTION, Color(0.3, 0.9, 1.0))
	else:
		garage._show_scrap_float("OVERCLOCKED! +1 hex to place - click a pulsing cell", Color(0.3, 0.9, 1.0))

# The "until re-upgraded" half of Overclocking - buys back chip capacity
# lost to overclock_count, one point at a time, never past the pre-
# overclock baseline (get_chip_capacity()'s own min(penalty,
# chip_capacity_upgrades) already enforces that ceiling).
func recalibrate_chip_capacity():
	var main = garage.get_parent()
	if not garage.active_component or not main or main.get("player_scrap") == null:
		return
	var comp = garage.active_component
	var penalty = comp.overclock_count * ComponentEquipmentScript.OVERCLOCK_CAPACITY_PENALTY
	if comp.chip_capacity_upgrades >= penalty:
		garage._show_scrap_float("Capacity already fully recalibrated", Color(0.7, 0.7, 0.7))
		return
	var cost = RECAL_BASE_COST * (comp.chip_capacity_upgrades + 1)
	if main.player_scrap < cost:
		garage._show_scrap_float("Need %d scrap" % cost, Color(0.9, 0.4, 0.3))
		return
	main.player_scrap -= cost
	comp.chip_capacity_upgrades += 1
	refresh_equipped_chips_ui()
	garage._refresh_inventory_ui()
	garage._show_scrap_float("Capacity +1 (now %d/%d)" % [comp.equipped_chips.size(), comp.get_chip_capacity()], Color(0.4, 1.0, 0.5))

# --- Chip Splicing -----------------------------------------------------------
# Two-tier merge, see ChipSplicer.gd's own header comment for the full
# mechanic. Tier 1 (two different-stat plain chips, no match needed) makes
# a new 3-trait Corrupted chip with both stats boosted plus a random
# negative. Tier 2 (re-splicing a Corrupted chip against anything else,
# match required) nets shared stats algebraically and carries unmatched
# traits over unchanged - trait count is unbounded.

# Splices two chips from the flat pool by index. On success, both source
# chips are removed and the result is appended; on failure (ineligible
# pairing, or a Tier 2 splice that fully cancels to zero traits), the pool
# is left untouched - nothing is lost on a bad pick.
func splice_chips(index_a: int, index_b: int):
	var main = garage.get_parent()
	if not main or main.get("player_modifier_chips") == null:
		return
	var pool = main.player_modifier_chips
	if index_a == index_b or index_a < 0 or index_b < 0 or index_a >= pool.size() or index_b >= pool.size():
		return
	var result = ChipSplicerScript.splice_chips(pool[index_a], pool[index_b])
	if result.is_empty():
		garage._show_scrap_float("Can't splice - no shared stat, or traits fully cancel out", Color(0.9, 0.4, 0.3))
		return
	var hi = max(index_a, index_b)
	var lo = min(index_a, index_b)
	pool.remove_at(hi)
	pool.remove_at(lo)
	pool.append(result)
	update_chip_label()
	garage._show_scrap_float("Spliced! %s" % _describe_chip(result), Color(0.3, 0.9, 1.0))

# Elemental stats reuse EnergyPacket's canonical per-element color table
# (kin/fire/ice/vtx/ltg/psn/exp/prc/vmp all map 1:1 onto a SynergyType) -
# dmg_mult/spd_mult aren't elemental, so they get two fixed colors of their
# own instead.
func _chip_stat_color(stat: String) -> Color:
	match stat:
		"dmg_mult": return Color(1.0, 0.85, 0.2) # Gold - overall damage
		"spd_mult": return Color(0.4, 0.9, 0.5) # Green - mobility
		"kin_mult": return EnergyPacketScript.get_color_for_synergy(EnergyPacketScript.SynergyType.KINETIC)
		"fire_mult": return EnergyPacketScript.get_color_for_synergy(EnergyPacketScript.SynergyType.FIRE)
		"ice_mult": return EnergyPacketScript.get_color_for_synergy(EnergyPacketScript.SynergyType.ICE)
		"vtx_mult": return EnergyPacketScript.get_color_for_synergy(EnergyPacketScript.SynergyType.VORTEX)
		"ltg_mult": return EnergyPacketScript.get_color_for_synergy(EnergyPacketScript.SynergyType.LIGHTNING)
		"psn_mult": return EnergyPacketScript.get_color_for_synergy(EnergyPacketScript.SynergyType.POISON)
		"exp_mult": return EnergyPacketScript.get_color_for_synergy(EnergyPacketScript.SynergyType.EXPLOSION)
		"prc_mult": return EnergyPacketScript.get_color_for_synergy(EnergyPacketScript.SynergyType.PIERCE)
		"vmp_mult": return EnergyPacketScript.get_color_for_synergy(EnergyPacketScript.SynergyType.VAMPIRIC)
	return Color(1, 1, 1)

# One colored, bordered "pill" per trait - "KIN +13%" in the stat's own
# color - condensed replacement for _describe_chip()'s full "kin_mult +13%"
# text inside the splice picker, where a Corrupted chip's full name list ran
# well past the popup's old width. mouse_filter = IGNORE on every node here
# so clicks pass through to the toggle Button this gets built inside of.
func _build_stat_pill(stat: String, value: float) -> Control:
	var pill = PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var color = _chip_stat_color(stat)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(color.r, color.g, color.b, 0.28)
	sb.border_color = color
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	pill.add_theme_stylebox_override("panel", sb)
	var label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pct = int(round((value - 1.0) * 100.0))
	label.text = "%s %+d%%" % [CHIP_STAT_ABBREV.get(stat, stat), pct]
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 12)
	pill.add_child(label)
	return pill

# The full pill row for one chip - a "✦" mark flags Corrupted (2+
# trait) chips at a glance instead of a "[Corrupted] " text prefix. Filled
# in as a child of a text-less toggle Button by _build_chip_row_button().
func _build_chip_pill_row(chip: Dictionary) -> Control:
	var row = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_right = -10
	var traits = chip.get("traits", [])
	if traits.size() > 1:
		var mark = Label.new()
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.text = "✦"
		mark.add_theme_color_override("font_color", Color(0.85, 0.5, 1.0))
		row.add_child(mark)
	for t in traits:
		row.add_child(_build_stat_pill(str(t["stat"]), float(t["value"])))
	return row

func _build_chip_row_button(chip: Dictionary, is_selected: bool) -> Button:
	var btn = Button.new()
	btn.toggle_mode = true
	btn.button_pressed = is_selected
	btn.custom_minimum_size = Vector2(0, 30)
	btn.tooltip_text = _describe_chip(chip) # full names on hover
	btn.add_child(_build_chip_pill_row(chip))
	return btn

# Chip picker: lists pool chips as toggle buttons of colored stat pills
# (see _build_chip_row_button above, replacing raw _describe_chip() text),
# lets the player select up to 2, and commits via splice_chips() on demand.
# A type filter (All/Plain/Corrupted) plus per-stat filter buttons (OR -
# narrows to chips containing ANY selected stat) help find a Tier 2 shared-
# stat match without reading every chip in a large pool by eye. Reuses
# _popup_helper (already lazily instantiated above for Overclocking's
# reward-choice popup) rather than duplicating GarageTileConfigPopup's
# click-outside-to-dismiss wiring.
func open_splice_popup():
	var main = garage.get_parent()
	if not main or main.get("player_modifier_chips") == null:
		return
	if main.player_modifier_chips.size() < 2:
		garage._show_scrap_float("Need at least 2 chips to splice", Color(0.9, 0.4, 0.3))
		return
	if not _popup_helper:
		_popup_helper = GarageTileConfigPopup.new(garage)

	var popup = PopupPanel.new()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	popup.add_child(vbox)

	var title = Label.new()
	title.text = "SPLICE CHIPS - select 2"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var type_filter = "all" # "all" | "plain" | "corrupted"
	var stat_filter: Dictionary = {} # stat name -> true; empty = no filter
	var selected: Array = [] # up to 2 pool indices, in click order
	var buttons: Dictionary = {} # pool index -> currently-visible Button

	var list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var splice_btn = Button.new()

	var refresh_splice_btn = func():
		splice_btn.disabled = selected.size() != 2

	var rebuild_list: Callable
	rebuild_list = func():
		for c in list_box.get_children():
			c.queue_free()
		buttons.clear()
		for i in range(main.player_modifier_chips.size()):
			var chip = main.player_modifier_chips[i]
			var traits = chip.get("traits", [])
			var is_corrupted = traits.size() > 1
			if type_filter == "plain" and is_corrupted:
				continue
			if type_filter == "corrupted" and not is_corrupted:
				continue
			if not stat_filter.is_empty():
				var has_match = false
				for t in traits:
					if stat_filter.has(str(t["stat"])):
						has_match = true
						break
				if not has_match:
					continue
			var btn = _build_chip_row_button(chip, selected.has(i))
			buttons[i] = btn
			btn.toggled.connect(func(pressed: bool):
				if pressed:
					if selected.size() >= 2:
						# Third click bumps the oldest selection instead of
						# silently ignoring it - lets the player change
						# their mind without hunting for an untoggle first.
						var bumped = selected.pop_front()
						if buttons.has(bumped):
							buttons[bumped].button_pressed = false
					selected.append(i)
				else:
					selected.erase(i)
				refresh_splice_btn.call()
			)
			list_box.add_child(btn)

	# --- Type filter row (All / Plain / Corrupted, single-select) ---
	var type_row = HBoxContainer.new()
	vbox.add_child(type_row)
	var type_buttons: Dictionary = {}
	for kind in ["all", "plain", "corrupted"]:
		var tbtn = Button.new()
		tbtn.text = kind.capitalize()
		tbtn.toggle_mode = true
		tbtn.button_pressed = (kind == "all")
		type_buttons[kind] = tbtn
	for kind in type_buttons:
		type_buttons[kind].pressed.connect(func():
			type_filter = kind
			for k in type_buttons:
				type_buttons[k].button_pressed = (k == kind)
			rebuild_list.call()
		)
		type_row.add_child(type_buttons[kind])

	# --- Per-stat filter row (OR - any selected stat matches) ---
	var stat_row = HBoxContainer.new()
	stat_row.add_theme_constant_override("separation", 3)
	vbox.add_child(stat_row)
	for stat in ComponentEquipmentScript.CHIP_STAT_POOL:
		var sbtn = Button.new()
		sbtn.toggle_mode = true
		sbtn.text = CHIP_STAT_ABBREV.get(stat, stat)
		sbtn.add_theme_color_override("font_color", _chip_stat_color(stat))
		sbtn.custom_minimum_size = Vector2(42, 0)
		sbtn.toggled.connect(func(pressed: bool):
			if pressed:
				stat_filter[stat] = true
			else:
				stat_filter.erase(stat)
			rebuild_list.call()
		)
		stat_row.add_child(sbtn)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(660, 320)
	vbox.add_child(scroll)
	scroll.add_child(list_box)

	rebuild_list.call()

	var button_row = HBoxContainer.new()
	vbox.add_child(button_row)

	splice_btn.text = "Splice Selected"
	splice_btn.disabled = true
	splice_btn.pressed.connect(func():
		if selected.size() == 2:
			splice_chips(selected[0], selected[1])
		popup.hide()
	)
	button_row.add_child(splice_btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(func(): popup.hide())
	button_row.add_child(cancel_btn)

	_popup_helper._show_popup(popup, Vector2(700, 520))
