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
# _on_equip_chip, _on_splice_chips, _on_overclock_part,
# _on_recalibrate_chip_capacity, _open_black_market, _on_sell_all,
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

	# Was HSplitContainer - user report: "the screen not fitting the interface
	# is still around", after a prior pass already widened inventory_panel to
	# 420 (see that field's own comment) and fixed a different EXPAND_FILL
	# mistake on deploy_button. Neither actually touched the real cause here:
	# an HSplitContainer's split_offset is computed once against whatever
	# window size existed at that layout pass and then stays FIXED in pixels
	# from then on - it does not recompute proportionally on a later resize/
	# maximize the way a plain BoxContainer's size-flag-driven layout does.
	# On a window that gets maximized shortly after the Garage builds (or is
	# just much wider than the ~1280px design canvas to start), the right
	# pane's rendered width can end up pinned far below its declared 420px
	# custom_minimum_size, with left_vbox eating 100% of the difference -
	# exactly the "COMPONENT INFO"/inventory text clipped flush against the
	# real window edge the screenshot showed. Plain HBoxContainer has no
	# split_offset/drag-handle state to go stale: left_vbox keeps its
	# SIZE_EXPAND_FILL (grows to fill whatever's left) and inventory_panel
	# keeps its default non-expanding SIZE_FILL (stays at exactly its
	# custom_minimum_size), self-correcting on every resize with no stored
	# pixel value to freeze. No player-facing drag-to-resize behavior existed
	# for this split anyway, so losing that affordance costs nothing real.
	var hsplit = HBoxContainer.new()
	hsplit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	garage.add_child(hsplit)

	# Left Side: Grid Editor
	var left_vbox = VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsplit.add_child(left_vbox)

	# Clears Main's "Wave: N | Lives: N" HUD label, which sits at the same
	# top-left corner in its own CanvasLayer underneath (user report: the
	# two overlapped, unreadable, on a wide/maximized window) - the Garage
	# itself has no reason to start flush at y=0.
	var top_spacer = Control.new()
	top_spacer.custom_minimum_size = Vector2(0, 44)
	left_vbox.add_child(top_spacer)

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
	# A build can legitimately produce a LOT of tabs (body slots + backpack
	# + one per installed Drone Bay). Without clip_tabs the bar silently
	# scrolls with no way back - playtest report: "I can't get back to my
	# torso!" clip_tabs shows prev/next arrows when the bar overflows, and
	# max_tab_width keeps long procedural component names from eating the
	# whole bar by themselves.
	garage.component_tabs.clip_tabs = true
	garage.component_tabs.max_tab_width = 110
	garage.component_tabs.add_to_group("tutorial:component_tabs") # onboarding spotlight anchor - see TutorialManager.gd
	garage.component_tabs.tab_changed.connect(garage._on_tab_changed)
	tab_hbox.add_child(garage.component_tabs)

	var action_vbox = VBoxContainer.new()
	tab_hbox.add_child(action_vbox)

	var swap_btn = Button.new()
	swap_btn.text = "Swap Component"
	swap_btn.pressed.connect(garage._on_swap_component_pressed)
	action_vbox.add_child(swap_btn)

	var infuse_btn = Button.new()
	infuse_btn.text = "Salvage for XP"
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
	auto_button.tooltip_text = "Fills empty cells on this part from your tile inventory - prioritizes routing/output tiles and tunes any Elemental Infusers it places toward your build's favored element."
	auto_button.custom_minimum_size = Vector2(120, 50)
	auto_button.pressed.connect(garage._on_auto_equip_pressed)
	bottom_bar.add_child(auto_button)

	# Auto-Upgrade (user request, 2026-08-13: "a button in the garage that
	# automatically upgrades any hex tiles with the highest rarity
	# available... starting at the core then clockwise for the torso, or
	# the energy intakes... for all other components") - see GarageMenu.
	# _on_auto_upgrade_pressed's own header comment for the full algorithm.
	var upgrade_button = Button.new()
	upgrade_button.text = "Auto-Upgrade"
	upgrade_button.tooltip_text = "Swaps every equipped tile for the highest-rarity copy of the same type in your inventory, across your whole mech - starting at each part's Core/Energy Intake and working clockwise."
	upgrade_button.custom_minimum_size = Vector2(120, 50)
	upgrade_button.pressed.connect(garage._on_auto_upgrade_pressed)
	bottom_bar.add_child(upgrade_button)

	var clear_button = Button.new()
	clear_button.text = "Clear Grid"
	clear_button.custom_minimum_size = Vector2(120, 50)
	clear_button.pressed.connect(garage._on_clear_grid_pressed)
	bottom_bar.add_child(clear_button)

	# Blueprint import: apply a friend's card PNG (any Champion Card - every
	# card carries the full buildout by design ruling) as a build recipe
	# assembled from parts you actually own. See GarageMenu.
	var blueprint_button = Button.new()
	blueprint_button.text = "Blueprints"
	blueprint_button.custom_minimum_size = Vector2(120, 50)
	blueprint_button.pressed.connect(garage._on_blueprint_pressed)
	bottom_bar.add_child(blueprint_button)

	# Drone template (playtest ruling: "use a drone template for several
	# drones instead of manually building each one") - copies the OPEN
	# drone tab's loadout onto every other installed Drone Bay.
	var drone_copy_button = Button.new()
	drone_copy_button.text = "Drone->All"
	drone_copy_button.custom_minimum_size = Vector2(100, 50)
	drone_copy_button.pressed.connect(garage._on_drone_copy_all_pressed)
	bottom_bar.add_child(drone_copy_button)

	# Test Range (Status.md queue): live-fire any armed mount's REAL energy
	# feed at a dummy mech in a private physics world - see GarageTestRange.
	var test_range_button = Button.new()
	test_range_button.text = "Test Range"
	test_range_button.custom_minimum_size = Vector2(100, 50)
	test_range_button.tooltip_text = "Fire your actual weapon mounts at a target dummy - real projectiles, real spread, real damage numbers."
	test_range_button.add_to_group("tutorial:test_range_button") # onboarding spotlight anchor - see TutorialManager.gd
	test_range_button.pressed.connect(garage._on_test_range_pressed)
	bottom_bar.add_child(test_range_button)

	# War Room (task #9: "accessible from Garage") - previously only
	# reachable from the Main Menu (before a run even starts) or the in-run
	# TAB shortcut; a player deep in a build session between waves had no
	# way to check enemy doctrine analysis without leaving the Garage.
	var war_room_button = Button.new()
	war_room_button.text = "War Room"
	war_room_button.custom_minimum_size = Vector2(100, 50)
	war_room_button.tooltip_text = "Enemy doctrine analysis: threat board, squad lineages, boss kits, and your own death log."
	war_room_button.pressed.connect(garage._on_war_room_pressed)
	bottom_bar.add_child(war_room_button)

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
	# Was SIZE_EXPAND_FILL - the only child in bottom_bar flagged to expand,
	# so on a window wider than the ~1280px design canvas it absorbed 100%
	# of the leftover width and rendered as one giant button with its
	# centered text stranded far from its siblings (user report: "gets cut
	# off... on a 1440 monitor"). Sized like every other button in this row
	# instead.
	deploy_button.pressed.connect(func():
		var main = garage.get_parent()
		# Perf fix (live playtest: ~20s Deploy-to-gameplay stall) - this used
		# to also call SaveManager.save_game() right here, then
		# Main._close_garage() (called right below) did the EXACT SAME
		# save_game("autosave", player, player_inventory) call again a
		# moment later - garage.inventory IS main.player_inventory (set by
		# reference in GarageMenu._ready()), so both calls always
		# serialized identical data. On a save with a large inventory that
		# duplicate synchronous JSON write was a real, pure-waste cost paid
		# twice on every single Deploy. _close_garage() also recalculates
		# the player/drone grids before its own save, so keeping THAT one
		# (not this earlier one) saves the more up-to-date state anyway.
		if main and main.has_method("_close_garage"):
			main._close_garage()
	)
	bottom_bar.add_child(deploy_button)

	# Simulation Timeline Scrubber (Status.md queue) - deterministic re-run
	# to any step, hidden until a simulation has actually run for this grid
	# (see GarageSimulationRunner.run_simulation/_update_scrubber_range and
	# GarageMenu._on_tab_changed/_on_clear_grid_pressed's invalidation).
	# While visible, clicking a tile opens the Packet Inspector instead of
	# the normal edit popup - see GarageMenu._on_tile_clicked.
	var scrubber_bar = HBoxContainer.new()
	left_vbox.add_child(scrubber_bar)

	var scrubber_lbl = Label.new()
	scrubber_lbl.text = "Timeline:"
	scrubber_bar.add_child(scrubber_lbl)

	garage.sim_scrubber = HSlider.new()
	garage.sim_scrubber.min_value = 0
	garage.sim_scrubber.max_value = 0
	garage.sim_scrubber.step = 1
	garage.sim_scrubber.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	garage.sim_scrubber.custom_minimum_size = Vector2(200, 24)
	garage.sim_scrubber.tooltip_text = "Drag to scrub the simulation to any step - deterministic re-run, no memory cost. Click a tile while this is visible to inspect its packet history instead of editing it."
	garage.sim_scrubber.visible = false
	garage.sim_scrubber.value_changed.connect(garage._on_sim_scrubber_changed)
	scrubber_bar.add_child(garage.sim_scrubber)

	garage.sim_step_label = Label.new()
	garage.sim_step_label.text = "Step: 0 / 0"
	garage.sim_step_label.custom_minimum_size = Vector2(100, 0)
	scrubber_bar.add_child(garage.sim_step_label)

	garage.sim_inspect_toggle = CheckButton.new()
	garage.sim_inspect_toggle.text = "Inspect"
	garage.sim_inspect_toggle.tooltip_text = "OFF (default): clicking a tile opens its normal edit popup, same as always. ON: clicking a tile opens the Packet Inspector instead - see what flowed through it at this step."
	garage.sim_inspect_toggle.visible = false
	scrubber_bar.add_child(garage.sim_inspect_toggle)

	# Loadouts Bar - named, unlimited slots (playtest ruling: "a wider
	# variety of builds (Component and full bot) not just 3 slots"). Both
	# buttons open a popup manager in GarageMenu with save-as / load /
	# delete rows; legacy numbered quick-slots still show up in the Builds
	# list as "Quick Slot N".
	var loadout_bar = HBoxContainer.new()
	left_vbox.add_child(loadout_bar)

	var builds_btn = Button.new()
	builds_btn.text = "Builds..."
	builds_btn.custom_minimum_size = Vector2(120, 40)
	builds_btn.tooltip_text = "Save and load full equipped-mech builds under any name, unlimited slots. Separate from the automatic run save (Deploy to Battlefield autosaves your progress). Loading replaces your ENTIRE mech; outgoing parts are not refunded."
	builds_btn.pressed.connect(garage._on_builds_pressed)
	loadout_bar.add_child(builds_btn)

	var parts_btn = Button.new()
	parts_btn.text = "Parts..."
	parts_btn.custom_minimum_size = Vector2(120, 40)
	parts_btn.tooltip_text = "Save and load single parts under any name, unlimited slots - scoped to whichever tab is open (a saved arm only lists on arm tabs). Loading replaces ONLY this tab's part; the outgoing part is not refunded."
	parts_btn.pressed.connect(garage._on_parts_pressed)
	loadout_bar.add_child(parts_btn)

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
	infuse_xp_btn.text = "Upgrade This Part (+100 XP / -100 scrap)"
	infuse_xp_btn.tooltip_text = "500 XP per level. Legendary+ parts roll a random stat modifier each level."
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
	chip_btn.text = "Equip Mod Chip"
	chip_btn.tooltip_text = "Pick a chip from your pool to equip onto the current part, up to its chip capacity. Chips stack, capped at +50% per stat. Click an equipped chip below to unequip it."
	chip_btn.pressed.connect(garage._on_equip_chip)
	feature5_bar.add_child(chip_btn)

	var splice_btn = Button.new()
	splice_btn.text = "Splice Chips"
	splice_btn.modulate = Color(0.85, 0.6, 1.0)
	splice_btn.tooltip_text = "Combine two chips from your inventory. Two different-stat plain chips make a boosted 3-trait 'Corrupted' chip with a random drawback; splicing a Corrupted chip against anything sharing one of its stats nets the shared stats together and keeps the rest."
	splice_btn.pressed.connect(garage._on_splice_chips)
	feature5_bar.add_child(splice_btn)

	garage.chip_count_label = Label.new()
	garage.chip_count_label.text = "Chips: 0"
	# mouse_filter STOP so tooltip_text (the full next-chip trait breakdown,
	# set by TileActionMenu.update_chip_label) actually shows on hover -
	# Label defaults to MOUSE_FILTER_IGNORE and would eat the tooltip
	# otherwise. clip_text (not autowrap) is the defensive floor: an earlier
	# pass tried AUTOWRAP_WORD_SMART, but this Label gets no explicit
	# custom_minimum_size and feature5_bar's other buttons already claim
	# most of the row, so Godot squeezed its allotted width to near zero
	# and autowrap collapsed the text to ONE CHARACTER PER LINE, rendering
	# as a full-screen-height vertical strip (same failure shape as the
	# empty-state HFlowContainer label bug elsewhere in this file - search
	# "one letter per line"). clip_text just ellipsizes whatever doesn't
	# fit instead of needing room to wrap INTO, so it can't blow up
	# minimum size the same way. update_chip_label() already keeps this
	# text short by design (see its own comment on the hsplit-overflow bug
	# that caused), so clip_text is only ever a backstop.
	garage.chip_count_label.mouse_filter = Control.MOUSE_FILTER_STOP
	garage.chip_count_label.clip_text = true
	feature5_bar.add_child(garage.chip_count_label)

	var market_btn = Button.new()
	market_btn.text = "BLACK MARKET"
	market_btn.modulate = Color(1.0, 0.5, 0.9)
	market_btn.tooltip_text = "Experimental oversized parts with severe drawbacks. Stock rotates every 10 real-time minutes."
	market_btn.pressed.connect(garage._open_black_market)
	feature5_bar.add_child(market_btn)

	# --- Equipped-chip row: shows the active component's currently-equipped
	# chips (click one to unequip) and its chip capacity. Overclocking
	# below can reduce that capacity, so this row is the player's main
	# feedback for "how much room do I have left."
	var equipped_chips_row = HBoxContainer.new()
	left_vbox.add_child(equipped_chips_row)
	garage.chip_capacity_label = Label.new()
	garage.chip_capacity_label.text = "Capacity: 0/0"
	equipped_chips_row.add_child(garage.chip_capacity_label)
	garage.equipped_chips_box = HFlowContainer.new()
	equipped_chips_row.add_child(garage.equipped_chips_box)

	# --- Overclocking (prestige) row: unlocks once a component is Mythic. ---
	var prestige_bar = HBoxContainer.new()
	left_vbox.add_child(prestige_bar)

	var overclock_btn = Button.new()
	overclock_btn.text = "Overclock"
	overclock_btn.modulate = Color(0.5, 0.85, 1.0)
	overclock_btn.tooltip_text = "Mythic-rarity parts only. Returns all equipped chips to inventory, permanently drops chip capacity, and grants your choice of permanent mass reduction or +1 hex. Repeatable - cost rises each time."
	overclock_btn.pressed.connect(garage._on_overclock_part)
	prestige_bar.add_child(overclock_btn)

	var recalibrate_btn = Button.new()
	recalibrate_btn.text = "Recalibrate Capacity"
	recalibrate_btn.tooltip_text = "Pays scrap to recover one point of chip capacity lost to Overclocking - never past the part's pre-Overclock baseline."
	recalibrate_btn.pressed.connect(garage._on_recalibrate_chip_capacity)
	prestige_bar.add_child(recalibrate_btn)

	var shop_btn = Button.new()
	shop_btn.text = "SHOP"
	shop_btn.modulate = Color(0.4, 0.9, 1.0)
	shop_btn.tooltip_text = "Spend massive amounts of scrap on full bots, components, and rare tiles - always in stock, no drawbacks."
	shop_btn.pressed.connect(garage._open_shop)
	feature5_bar.add_child(shop_btn)

	var paint_rack_btn = Button.new()
	paint_rack_btn.text = "PAINT RACK"
	paint_rack_btn.modulate = Color(0.9, 0.8, 0.3)
	paint_rack_btn.tooltip_text = "Pick your mech's color. Free, and you can change it any time."
	paint_rack_btn.pressed.connect(garage._open_paint_rack)
	feature5_bar.add_child(paint_rack_btn)

	# Permanent manual re-open, same "free, no penalty, change any time"
	# framing as Paint Rack above - the popup itself only auto-shows once
	# (see SaveManager.sponsor_popup_shown), so this is the only way back
	# in after that first visit.
	var sponsor_btn = Button.new()
	sponsor_btn.text = "SPONSOR"
	sponsor_btn.modulate = Color(0.6, 0.85, 1.0)
	sponsor_btn.tooltip_text = "Pick a corporate sponsor to bias your loot drops toward their gear. Unlocks at wave 125. Free, and you can switch any time."
	sponsor_btn.pressed.connect(garage._open_sponsor_popup)
	sponsor_btn.disabled = SaveManager.max_wave_reached < 125
	feature5_bar.add_child(sponsor_btn)

	# Right Side: Inventory & Stats
	garage.inventory_panel = PanelContainer.new()
	# Was 300 - too narrow for its own content regardless of window size
	# (component/tile rows show "TileType\nRarity (xN.NN) [count]", which
	# genuinely doesn't fit 300px at this font size - user report: "the
	# component view looks terrible", every row's name/rarity/multiplier
	# text truncated). 420 matches the width GarageInventoryPanel.gd's own
	# Swap Component popup already uses for equivalent component-list rows.
	garage.inventory_panel.custom_minimum_size = Vector2(420, 0)
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
	# to be (the user: shrink the hex-grid preview and use the freed space for
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
	# This is the actual draggable tray the user bought Black Market parts
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
	style.content_margin_right = 10
	style.content_margin_bottom = 10
	garage.tooltip_label.add_theme_stylebox_override("normal", style)
	# Fixed-width + word-wrap (user report, 2026-08-05: a long tile blurb like
	# Missile Rack's ran clean off the right edge of the window - unwrapped
	# text at an unclamped mouse-relative position has no ceiling on how far
	# right a single line can extend). Same class of bug FpsCounter.gd's
	# overlay hit before its own VBoxContainer/autowrap fix - see that file's
	# header comment. on_tooltip_requested (GarageInventoryPanel.gd) also
	# clamps the resulting position against the viewport so the box itself
	# can't get placed off-screen even after wrapping shrinks its footprint.
	garage.tooltip_label.custom_minimum_size = Vector2(320, 0)
	garage.tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	garage.tooltip_label.hide()
	garage.add_child(garage.tooltip_label)
