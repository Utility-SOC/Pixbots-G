class_name GarageUIBuilder
extends RefCounted

# Builds the entire Garage node tree (grid editor, action bars, loadout
# slots, inventory/spare-parts sidebar, drag previews, tooltip) - split out
# of GarageMenu.gd's _setup_ui(), see SightAndSearch.gd/MagnetSystem.gd for
# the established composed-RefCounted-helper pattern this follows. Every
# Control/field it creates is assigned directly onto GarageMenu (component_
# tabs, grid_renderer, stats_label, ...) since that's the state everything
# else in the Garage (including all the other split-out helpers) already
# reads by those exact field names - only the one-time construction code
# moved here.
#
# Not lazily constructed like the other helpers - _ready() calls build()
# exactly once and the builder isn't kept around afterward (nothing needs
# to call back into it later, unlike e.g. GarageInventoryPanel which is
# re-entered every frame).
#
# Every signal.connect(_on_x) below references a still-real GarageMenu
# method - either the original unmoved implementation (_on_tab_changed,
# _set_inventory_view, _on_diagram_slot_pressed, _on_swap_component_pressed,
# _on_infuse_component_pressed, _on_auto_equip_pressed,
# _on_clear_grid_pressed) or one of the thin wrappers left behind by the
# other extractions (_on_codex_pressed, _on_tooltip_requested,
# _on_tooltip_cleared, _on_tile_clicked, _on_simulate_pressed,
# _on_repair_all, _on_infuse_part, _on_upgrade_part, _on_extract_modifier,
# _on_infuse_chip, _open_black_market, _on_sell_all,
# _refresh_inventory_ui, _refresh_component_inventory_list) - so every
# connect below is written as garage._on_x to resolve against the right
# instance.

var garage: GarageMenu

func _init(p_garage: GarageMenu):
	garage = p_garage

func build():
	garage.layer = 10

	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08, 0.4) # Mostly transparent
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	garage.add_child(bg)

	var hsplit = HSplitContainer.new()
	hsplit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	garage.add_child(hsplit)

	# Left Side: Grid Editor
	var left_vbox = VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsplit.add_child(left_vbox)

	var top_bar = VBoxContainer.new()
	left_vbox.add_child(top_bar)

	var grid_label = Label.new()
	grid_label.text = " (Drag to pan, Scroll to zoom, E to rotate, Right-click to remove)"
	grid_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(grid_label)

	var tab_hbox = HBoxContainer.new()
	top_bar.add_child(tab_hbox)

	garage.component_tabs = TabBar.new()
	garage.component_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	garage.component_tabs.tab_changed.connect(garage._on_tab_changed)
	tab_hbox.add_child(garage.component_tabs)

	var action_vbox = VBoxContainer.new()
	tab_hbox.add_child(action_vbox)

	var swap_btn = Button.new()
	swap_btn.text = "Swap Component"
	swap_btn.pressed.connect(garage._on_swap_component_pressed)
	action_vbox.add_child(swap_btn)

	var infuse_btn = Button.new()
	infuse_btn.text = "Infuse (Destroy part)"
	infuse_btn.pressed.connect(garage._on_infuse_component_pressed)
	action_vbox.add_child(infuse_btn)

	var codex_btn = Button.new()
	codex_btn.text = "Synergy Codex"
	codex_btn.pressed.connect(garage._on_codex_pressed)
	action_vbox.add_child(codex_btn)

	garage.grid_panel = PanelContainer.new()
	garage.grid_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	garage.grid_panel.add_to_group("tutorial:grid_panel") # onboarding spotlight anchor - see TutorialManager.gd
	left_vbox.add_child(garage.grid_panel)

	garage.grid_renderer = GarageGridRenderer.new()
	garage.grid_renderer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	garage.grid_renderer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	garage.grid_renderer.tooltip_requested.connect(garage._on_tooltip_requested)
	garage.grid_renderer.tooltip_cleared.connect(garage._on_tooltip_cleared)
	garage.grid_renderer.tile_clicked.connect(garage._on_tile_clicked)
	garage.grid_panel.add_child(garage.grid_renderer)

	# Add a warning label
	garage.warning_label = Label.new()
	garage.warning_label.name = "WarningLabel"
	garage.warning_label.modulate = Color(1.0, 0.5, 0.5)
	garage.warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	garage.warning_label.hide()
	top_bar.add_child(garage.warning_label)

	# Bottom Bar
	var bottom_bar = HBoxContainer.new()
	left_vbox.add_child(bottom_bar)

	garage.sim_button = Button.new()
	garage.sim_button.name = "SimButton"
	garage.sim_button.text = "Simulate Energy Flow"
	garage.sim_button.custom_minimum_size = Vector2(200, 50)
	garage.sim_button.add_to_group("tutorial:sim_button") # onboarding spotlight anchor - see TutorialManager.gd
	garage.sim_button.pressed.connect(garage._on_simulate_pressed)
	bottom_bar.add_child(garage.sim_button)

	var auto_button = Button.new()
	auto_button.text = "Auto-Equip"
	auto_button.custom_minimum_size = Vector2(120, 50)
	auto_button.pressed.connect(garage._on_auto_equip_pressed)
	bottom_bar.add_child(auto_button)

	var clear_button = Button.new()
	clear_button.text = "Clear Grid"
	clear_button.custom_minimum_size = Vector2(120, 50)
	clear_button.pressed.connect(garage._on_clear_grid_pressed)
	bottom_bar.add_child(clear_button)

	var sep_fire_toggle = CheckButton.new()
	sep_fire_toggle.text = "Separate L/R Firing"

	if garage.get_parent() and garage.get_parent().get("player") != null:
		sep_fire_toggle.button_pressed = garage.get_parent().player.separate_arm_firing
	else:
		sep_fire_toggle.button_pressed = true

	sep_fire_toggle.toggled.connect(func(pressed):
		if garage.get_parent() and garage.get_parent().get("player") != null:
			garage.get_parent().player.separate_arm_firing = pressed
	)
	bottom_bar.add_child(sep_fire_toggle)

	var paths_toggle = CheckButton.new()
	paths_toggle.text = "Show Static Paths"
	paths_toggle.button_pressed = true
	paths_toggle.toggled.connect(func(pressed):
		garage.grid_renderer.show_static_paths = pressed
		garage.grid_renderer.queue_redraw()
	)
	bottom_bar.add_child(paths_toggle)

	var deploy_button = Button.new()
	deploy_button.text = "Deploy to Battlefield ->"
	deploy_button.custom_minimum_size = Vector2(200, 50)
	deploy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deploy_button.pressed.connect(func():
		var main = garage.get_parent()
		if main and main.get("player") != null:
			SaveManager.save_game("autosave", main.player, garage.inventory)
		if main and main.has_method("_close_garage"):
			main._close_garage()
	)
	bottom_bar.add_child(deploy_button)

	# Loadouts Bar
	var loadout_bar = HBoxContainer.new()
	left_vbox.add_child(loadout_bar)

	var loadout_lbl = Label.new()
	loadout_lbl.text = "Loadouts: "
	loadout_bar.add_child(loadout_lbl)

	for i in range(1, 4):
		var btn = Button.new()
		btn.text = "Load " + str(i)
		btn.pressed.connect(func():
			var main = garage.get_parent()
			if main and main.get("player") != null:
				if SaveManager.load_loadout(i, main.player, garage.inventory):
					garage._refresh_component_ui()
					garage._refresh_inventory_ui()
		)
		loadout_bar.add_child(btn)

		var save_btn = Button.new()
		save_btn.text = "Save " + str(i)
		save_btn.pressed.connect(func():
			var main = garage.get_parent()
			if main and main.get("player") != null:
				SaveManager.save_loadout(i, main.player)
		)
		loadout_bar.add_child(save_btn)

	# Per-component loadout bar (FEATURE_ROADMAP.md group 1): same idea as
	# the full-build slots above, but scoped to whichever component tab is
	# currently open - lets a favorite arm/torso wiring be reused across
	# otherwise different builds. Slots are keyed per body-slot type in
	# SaveManager, so "Part Load 1" on the Torso tab is a different file
	# from "Part Load 1" on the Left Arm tab.
	var part_loadout_bar = HBoxContainer.new()
	left_vbox.add_child(part_loadout_bar)

	var part_lbl = Label.new()
	part_lbl.text = "This part: "
	part_loadout_bar.add_child(part_lbl)

	for i in range(1, 4):
		var p_load = Button.new()
		p_load.text = "Load " + str(i)
		p_load.pressed.connect(func():
			var main = garage.get_parent()
			if not garage.active_component or not main or main.get("player") == null:
				return
			var slot_type = garage.active_component.slot_type
			var loaded = SaveManager.load_component_loadout(i, slot_type)
			if not loaded:
				return
			# Swap just this one component on the mech, then re-point the
			# garage at the fresh instance via the normal tab-change path.
			# (Same replace semantics as the full-build loadout slots: the
			# outgoing part and its tiles are not refunded to inventory.)
			var old = main.player.unequip_component(slot_type)
			if old:
				old.queue_free()
			main.player.equip_component(loaded)
			garage._refresh_component_ui()
			garage._on_tab_changed(garage.component_tabs.current_tab)
		)
		part_loadout_bar.add_child(p_load)

		var p_save = Button.new()
		p_save.text = "Save " + str(i)
		p_save.pressed.connect(func():
			if garage.active_component:
				SaveManager.save_component_loadout(i, garage.active_component)
		)
		part_loadout_bar.add_child(p_save)

	# Scrap sinks (FEATURE_ROADMAP.md group 2): repair and infusion give
	# scrap something to buy beyond the tile-upgrade middle-click.
	var scrap_sink_bar = HBoxContainer.new()
	left_vbox.add_child(scrap_sink_bar)

	var repair_btn = Button.new()
	repair_btn.text = "Repair All"
	repair_btn.tooltip_text = "1 scrap per 2 missing HP, +25 per knocked-out tile, +100 per destroyed tile"
	repair_btn.pressed.connect(garage._on_repair_all)
	scrap_sink_bar.add_child(repair_btn)

	# NOTE: named infuse_xp_btn, not infuse_btn - _setup_ui already declares
	# an infuse_btn at the top (the "Infuse (Destroy part)" modifier-infusion
	# button), and GDScript treats a duplicate local name in the same
	# function scope as a compile error, which silently killed the whole
	# garage (GDScript::reload fails -> _open_garage gets a scriptless class).
	var infuse_xp_btn = Button.new()
	infuse_xp_btn.text = "Infuse This Part (+100 XP / 100 scrap)"
	infuse_xp_btn.tooltip_text = "500 XP per infusion level. Legendary+ parts roll a random stat modifier each level."
	infuse_xp_btn.pressed.connect(garage._on_infuse_part)
	scrap_sink_bar.add_child(infuse_xp_btn)

	# --- Feature 5 row: upgrades, modifier chips, Black Market ---------------
	var feature5_bar = HBoxContainer.new()
	left_vbox.add_child(feature5_bar)

	var upgrade_part_btn = Button.new()
	upgrade_part_btn.text = "Upgrade Part"
	upgrade_part_btn.tooltip_text = "Tier this part up one rarity: costs scrap plus ONE same-slot salvage part. YOU place the new hexes - click the pulsing cells on the grid."
	upgrade_part_btn.pressed.connect(garage._on_upgrade_part)
	feature5_bar.add_child(upgrade_part_btn)

	var extract_btn = Button.new()
	extract_btn.text = "Extract Modifier"
	extract_btn.tooltip_text = "Scraps the first spare component that carries a stat modifier and saves that modifier as a chip."
	extract_btn.pressed.connect(garage._on_extract_modifier)
	feature5_bar.add_child(extract_btn)

	var chip_btn = Button.new()
	chip_btn.text = "Infuse Chip"
	chip_btn.tooltip_text = "Applies your oldest extracted modifier chip to the current part. Chips stack, capped at +50% per stat."
	chip_btn.pressed.connect(garage._on_infuse_chip)
	feature5_bar.add_child(chip_btn)

	garage.chip_count_label = Label.new()
	garage.chip_count_label.text = "Chips: 0"
	feature5_bar.add_child(garage.chip_count_label)

	var market_btn = Button.new()
	market_btn.text = "BLACK MARKET"
	market_btn.modulate = Color(1.0, 0.5, 0.9)
	market_btn.tooltip_text = "Experimental oversized parts with severe drawbacks. Stock rotates every 10 real-time minutes."
	market_btn.pressed.connect(garage._open_black_market)
	feature5_bar.add_child(market_btn)

	# Right Side: Inventory & Stats
	garage.inventory_panel = PanelContainer.new()
	garage.inventory_panel.custom_minimum_size = Vector2(300, 0)
	garage.inventory_panel.add_to_group("tutorial:inventory_panel") # onboarding spotlight anchor - see TutorialManager.gd
	hsplit.add_child(garage.inventory_panel)

	var right_vbox = VBoxContainer.new()
	garage.inventory_panel.add_child(right_vbox)

	garage.stats_label = Label.new()
	garage.stats_label.text = "=== COMPONENT INFO ===\nGrid: Mech Core\nPower: 0\n\n=== SIMULATION ===\nStep: 0\nActive Packets: 0\nTotal Energy: 0"
	right_vbox.add_child(garage.stats_label)

	var sep = HSeparator.new()
	right_vbox.add_child(sep)

	garage.scrap_label = Label.new()
	garage.scrap_label.text = "Scrap: 0"
	garage.scrap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	garage.scrap_label.modulate = Color(1.0, 0.8, 0.2)
	right_vbox.add_child(garage.scrap_label)

	# Tiles / Components switch - a ButtonGroup makes the two toggle buttons
	# mutually exclusive automatically (no manual un-press bookkeeping).
	var view_switch_hbox = HBoxContainer.new()
	right_vbox.add_child(view_switch_hbox)

	var view_group = ButtonGroup.new()

	var tiles_tab_btn = Button.new()
	tiles_tab_btn.text = "Tiles"
	tiles_tab_btn.toggle_mode = true
	tiles_tab_btn.button_pressed = true
	tiles_tab_btn.button_group = view_group
	tiles_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tiles_tab_btn.pressed.connect(func(): garage._set_inventory_view("tiles"))
	view_switch_hbox.add_child(tiles_tab_btn)

	var components_tab_btn = Button.new()
	components_tab_btn.text = "Components"
	components_tab_btn.toggle_mode = true
	components_tab_btn.button_group = view_group
	components_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	components_tab_btn.pressed.connect(func(): garage._set_inventory_view("components"))
	view_switch_hbox.add_child(components_tab_btn)

	# --- Tiles panel ---------------------------------------------------------
	garage.tile_panel = VBoxContainer.new()
	garage.tile_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(garage.tile_panel)

	var inv_label = Label.new()
	inv_label.text = "INVENTORY (R-click: scrap | M-click: upgrade)"
	inv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inv_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	garage.tile_panel.add_child(inv_label)

	var mass_sell_hbox = HBoxContainer.new()
	mass_sell_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	garage.tile_panel.add_child(mass_sell_hbox)

	var sell_c_btn = Button.new()
	sell_c_btn.text = "Sell Common"
	sell_c_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell_c_btn.pressed.connect(garage._on_sell_all.bind(0))
	mass_sell_hbox.add_child(sell_c_btn)

	var sell_uc_btn = Button.new()
	sell_uc_btn.text = "Sell <= Uncommon"
	sell_uc_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell_uc_btn.pressed.connect(garage._on_sell_all.bind(1))
	mass_sell_hbox.add_child(sell_uc_btn)

	var sell_r_btn = Button.new()
	sell_r_btn.text = "Sell <= Rare"
	sell_r_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell_r_btn.pressed.connect(garage._on_sell_all.bind(2))
	mass_sell_hbox.add_child(sell_r_btn)

	var filter_hbox = HBoxContainer.new()
	garage.tile_panel.add_child(filter_hbox)

	garage.search_input = LineEdit.new()
	garage.search_input.placeholder_text = "Search..."
	garage.search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	garage.search_input.text_changed.connect(func(_text): garage._refresh_inventory_ui())
	filter_hbox.add_child(garage.search_input)

	garage.rarity_filter = OptionButton.new()
	garage.rarity_filter.add_item("All", 99)
	garage.rarity_filter.add_item("Common", 0)
	garage.rarity_filter.add_item("Uncommon", 1)
	garage.rarity_filter.add_item("Rare", 2)
	garage.rarity_filter.add_item("Legendary", 3)
	garage.rarity_filter.item_selected.connect(func(_index): garage._refresh_inventory_ui())
	filter_hbox.add_child(garage.rarity_filter)

	garage.tile_sort = OptionButton.new()
	garage.tile_sort.add_item("Sort: rarity", 0)
	garage.tile_sort.add_item("Sort: type", 1)
	garage.tile_sort.item_selected.connect(func(_index): garage._refresh_inventory_ui())
	filter_hbox.add_child(garage.tile_sort)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	garage.tile_panel.add_child(scroll)

	garage.inv_vbox = VBoxContainer.new()
	garage.inv_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(garage.inv_vbox)

	# --- Components: mech-loadout diagram (moves to the MAIN area) ------------
	# In Components mode this is reparented into grid_panel as the primary
	# view (see _set_inventory_view) - it starts here in the sidebar, hidden,
	# just so it has a home while in Tiles mode.
	garage.component_diagram_panel = VBoxContainer.new()
	garage.component_diagram_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	garage.component_diagram_panel.visible = false
	right_vbox.add_child(garage.component_diagram_panel)

	var comp_inv_label = Label.new()
	comp_inv_label.text = "MECH LOADOUT (drag a spare part onto a slot to equip or swap it)"
	comp_inv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	comp_inv_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	garage.component_diagram_panel.add_child(comp_inv_label)

	garage.component_diagram = ComponentDiagramView.new()
	garage.component_diagram.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	garage.component_diagram.size_flags_vertical = Control.SIZE_EXPAND_FILL
	garage.component_diagram.slot_pressed.connect(garage._on_diagram_slot_pressed)
	garage.component_diagram_panel.add_child(garage.component_diagram)

	# Lives in the sidebar, hidden until Components mode reparents
	# grid_renderer into it (see _set_inventory_view). Half the height it used
	# to be (Natalia: shrink the hex-grid preview and use the freed space for
	# the actual inventory list below it) - SIZE_FILL (not expand) so it
	# stays exactly this tall and doesn't compete with component_spare_panel
	# for the sidebar's remaining vertical space.
	garage.side_grid_container = PanelContainer.new()
	garage.side_grid_container.size_flags_vertical = Control.SIZE_FILL
	garage.side_grid_container.custom_minimum_size = Vector2(0, 130)
	garage.side_grid_container.visible = false
	right_vbox.add_child(garage.side_grid_container)

	# --- Components: spare-parts inventory (moves to the SIDEBAR, below the
	# shrunk hex preview) --------------------------------------------------
	# This is the actual draggable tray Natalia bought Black Market parts
	# into - previously stacked directly under the (much taller) diagram in
	# this same sidebar column, where it regularly got squeezed to nothing or
	# scrolled below the fold. Splitting it out into its own guaranteed slot,
	# below a HALVED hex preview, means it always has real, visible room.
	garage.component_spare_panel = VBoxContainer.new()
	garage.component_spare_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	garage.component_spare_panel.visible = false
	right_vbox.add_child(garage.component_spare_panel)

	var comp_sort_hbox = HBoxContainer.new()
	garage.component_spare_panel.add_child(comp_sort_hbox)

	var spare_lbl = Label.new()
	spare_lbl.text = "Spare parts (unequipped - drag onto a slot above)"
	spare_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	comp_sort_hbox.add_child(spare_lbl)

	garage.component_sort = OptionButton.new()
	garage.component_sort.add_item("Sort: rarity", 0)
	garage.component_sort.add_item("Sort: type", 1)
	garage.component_sort.item_selected.connect(func(_index): garage._refresh_component_inventory_list())
	comp_sort_hbox.add_child(garage.component_sort)

	var spare_scroll = ScrollContainer.new()
	spare_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	garage.component_spare_panel.add_child(spare_scroll)

	garage.component_inventory_list = HFlowContainer.new()
	garage.component_inventory_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spare_scroll.add_child(garage.component_inventory_list)

	# Drag preview for spare-component cards - separate visual from the hex
	# drag_preview below since a whole component doesn't read well as a hex.
	garage.component_drag_preview = PanelContainer.new()
	garage.component_drag_preview.custom_minimum_size = Vector2(84, 40)
	garage.component_drag_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var drag_style = StyleBoxFlat.new()
	drag_style.bg_color = Color(0.15, 0.15, 0.18, 0.9)
	drag_style.border_width_left = 2
	drag_style.border_width_right = 2
	drag_style.border_width_top = 2
	drag_style.border_width_bottom = 2
	drag_style.border_color = Color(1.0, 1.0, 1.0, 0.6)
	drag_style.corner_radius_top_left = 8
	drag_style.corner_radius_top_right = 8
	drag_style.corner_radius_bottom_left = 8
	drag_style.corner_radius_bottom_right = 8
	garage.component_drag_preview.add_theme_stylebox_override("panel", drag_style)
	garage._component_drag_label = Label.new()
	garage._component_drag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	garage._component_drag_label.add_theme_font_size_override("font_size", 11)
	garage.component_drag_preview.add_child(garage._component_drag_label)
	garage.component_drag_preview.hide()
	garage.add_child(garage.component_drag_preview)

	# Drag preview setup
	garage.drag_preview = Polygon2D.new()
	var pts = PackedVector2Array()
	for i in range(6):
		var angle = deg_to_rad(60 * i - 30)
		pts.append(Vector2(cos(angle), sin(angle)) * 20)
	garage.drag_preview.polygon = pts
	garage.drag_preview.color = Color(1, 1, 1, 0.5)
	garage.drag_preview.hide()
	garage.add_child(garage.drag_preview)

	# Tooltip
	garage.tooltip_label = Label.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.9)
	style.corner_radius_top_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 10
	style.content_margin_top = 10
	garage.tooltip_label.add_theme_stylebox_override("normal", style)
	garage.tooltip_label.hide()
	garage.add_child(garage.tooltip_label)
