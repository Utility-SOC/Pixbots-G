class_name GarageInventoryPanel
extends RefCounted

const TileActionMenu = preload("res://scripts/ui/TileActionMenu.gd")

# Hex-tile inventory list, spare-component tray, and all drag/drop/tooltip
# handling for both - split out of GarageMenu.gd, see SightAndSearch.gd/
# MagnetSystem.gd for the established composed-RefCounted-helper pattern
# this follows. All state (inventory, dragged_tile, drag_preview,
# dragged_component, component_drag_preview, drag_hover_hex/since,
# fill_mode, fill_origin_hex, inv_vbox, component_inventory_list, and every
# other Control reference) stays on GarageMenu itself - only the behavior
# that reads/writes it moved here. Lazily constructed the first time any
# inventory/drag action fires (see GarageMenu's thin wrappers below).
#
# Several entry points keep thin wrappers on GarageMenu (not moved):
#   - _input/_process are Godot engine callbacks - they're only ever invoked
#     by name directly on the Node in the scene tree, so they have to stay
#     defined on GarageMenu regardless of where the logic behind them lives.
#   - refresh_inventory_ui/_refresh_component_inventory_list are called from
#     signal lambdas still living in GarageMenu._setup_ui (not yet split -
#     see GarageUIBuilder task) and from other files entirely
#     (GarageMarket.gd, TileActionMenu.gd, scripts/ui/DebugMenu.gd via
#     duck-typed has_method check), so they have to stay reachable as plain
#     GarageMenu-level methods.
#   - _add_to_inventory is called directly on the GarageMenu instance by
#     scripts/ui/GarageGridRenderer.gd (menu_parent._add_to_inventory(tile)).
#   - _on_tooltip_requested/_on_tooltip_cleared are connected directly as
#     Callables in _setup_ui (grid_renderer.tooltip_requested.connect(...)).
# Everything else here (the drag-start gui_input handlers, _drop_tile/
# _drop_component/_drop_fill_line, _find_matching_inventory_index) has no
# wrapper - their only callers are other functions in this same file.

var garage: GarageMenu

func _init(p_garage: GarageMenu):
	garage = p_garage

func refresh_component_list():
	if garage.component_diagram:
		garage.component_diagram.refresh(garage.mech_components)

	if not garage.component_inventory_list:
		return
	for c in garage.component_inventory_list.get_children():
		c.queue_free()

	var main = garage.get_parent()
	if not main or main.get("player_component_inventory") == null:
		return
	var comps = main.player_component_inventory

	# Defensive filter: previously a SINGLE malformed entry (e.g. a leftover
	# from an older save predating some earlier fix, or any future edge case
	# that slips a bad object into this array) could take down this entire
	# function the moment the sort comparator or the card-building loop below
	# touched its .rarity/.slot_type - which produces a tray with ZERO cards
	# and no placeholder text at all, even though comps itself (and any
	# perfectly good entries alongside the bad one, including a purchase that
	# just landed) was fine. That failure mode is indistinguishable from "my
	# purchase just didn't show up" from the player's side, which is exactly
	# what the user kept reporting even after two rounds of pure layout fixes.
	# Filtering up front means one bad apple can never hide everyone else's
	# entries, and the warning below at least gets it into the log instead of
	# vanishing silently.
	var valid_comps = []
	var dropped = 0
	for c in comps:
		if is_instance_valid(c) and c.get("rarity") != null and c.get("slot_type") != null:
			valid_comps.append(c)
		else:
			dropped += 1
	if dropped > 0:
		push_warning("GarageMenu: %d malformed player_component_inventory entries hidden from Spare Parts tray" % dropped)

	if valid_comps.is_empty():
		var empty_lbl = Label.new()
		if comps.is_empty():
			empty_lbl.text = "(none yet - boss kills, rare salvage drops, or the Black Market)"
		else:
			empty_lbl.text = "(%d entries couldn't be displayed - corrupted data, see log)" % dropped
		empty_lbl.modulate = Color(0.6, 0.6, 0.6)
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# component_inventory_list is an HFlowContainer, which sizes a child
		# from its own minimum size rather than granting it any width - a
		# word-wrapped Label's minimum width can shrink to a single
		# character, so without an explicit floor the container collapsed
		# this label down to one letter per line (playtest report: spare
		# parts empty-state text rendering vertically, one character at a
		# time). Same fix shape as GarageTileConfigPopup.gd's wrapped-text
		# rows.
		empty_lbl.custom_minimum_size = Vector2(280, 0)
		garage.component_inventory_list.add_child(empty_lbl)
		return

	var sorted_comps = valid_comps.duplicate()
	var sort_by_type = garage.component_sort != null and garage.component_sort.get_selected_id() == 1
	if sort_by_type:
		sorted_comps.sort_custom(func(a, b):
			if a.slot_type == b.slot_type:
				return a.rarity > b.rarity
			return a.slot_type < b.slot_type
		)
	else:
		sorted_comps.sort_custom(func(a, b):
			if a.rarity == b.rarity:
				return a.slot_type < b.slot_type
			return a.rarity > b.rarity
		)

	var rarity_names = ["Common", "Uncommon", "Rare", "Legendary", "Mythic"]
	var rarity_colors = [Color(0.5, 0.5, 0.5), Color(0.2, 0.7, 0.3), Color(0.2, 0.4, 0.8), Color(0.8, 0.5, 0.1), Color(0.1, 0.8, 0.8)]
	for comp in sorted_comps:
		var rarity_name = rarity_names[comp.rarity] if comp.rarity < rarity_names.size() else "?"
		var rarity_color = rarity_colors[comp.rarity] if comp.rarity < rarity_colors.size() else Color.WHITE

		var card = PanelContainer.new()
		card.custom_minimum_size = Vector2(92, 70)
		var style = StyleBoxFlat.new()
		style.bg_color = rarity_color * 0.45
		style.bg_color.a = 1.0
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.border_color = rarity_color
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		card.add_theme_stylebox_override("panel", style)
		if comp.rarity == 4:
			card.material = garage._get_mythic_shimmer_mat()

		var vbox = VBoxContainer.new()
		card.add_child(vbox)

		var slot_lbl = Label.new()
		slot_lbl.text = garage._slot_display_name(comp.slot_type)
		slot_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_lbl.add_theme_font_size_override("font_size", 11)
		slot_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(slot_lbl)

		var rarity_lbl = Label.new()
		var rarity_txt = rarity_name
		if comp.infusion_level > 0:
			rarity_txt += " Lv%d" % comp.infusion_level
		rarity_lbl.text = rarity_txt
		rarity_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rarity_lbl.add_theme_font_size_override("font_size", 10)
		vbox.add_child(rarity_lbl)

		# Every component is really a distinct hex-grid build (not just a
		# slot+rarity pair) - previously the tray had no way to tell two
		# same-slot-same-rarity spares apart short of dragging each one onto
		# the diagram and eyeballing the shape. Tile count is the cheapest
		# signal that two "Torso Mythic" cards are actually different builds.
		var tile_count = comp.hex_grid.get_all_tiles().size() if comp.hex_grid else 0
		var count_lbl = Label.new()
		count_lbl.text = "%d tiles" % tile_count
		count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count_lbl.add_theme_font_size_override("font_size", 9)
		count_lbl.modulate = Color(0.75, 0.75, 0.75)
		vbox.add_child(count_lbl)

		# Compact badge row: a green "+" for a stat-modifier buff (from
		# Infuse Chip), a red "!" for a Black Market forbidden-tile drawback.
		# Full detail (which stat, which types) lives in the tooltip below -
		# these are just "something's different here, hover to find out".
		var has_modifiers = not comp.stat_modifiers.is_empty()
		var has_forbidden = not comp.forbidden_tile_types.is_empty()
		if has_modifiers or has_forbidden:
			var badge_row = HBoxContainer.new()
			badge_row.alignment = BoxContainer.ALIGNMENT_CENTER
			if has_modifiers:
				var mod_badge = Label.new()
				mod_badge.text = "+"
				mod_badge.modulate = Color(0.4, 1.0, 0.5)
				mod_badge.add_theme_font_size_override("font_size", 13)
				badge_row.add_child(mod_badge)
			if has_forbidden:
				var forb_badge = Label.new()
				forb_badge.text = "!"
				forb_badge.modulate = Color(1.0, 0.4, 0.4)
				forb_badge.add_theme_font_size_override("font_size", 13)
				badge_row.add_child(forb_badge)
			vbox.add_child(badge_row)

		card.tooltip_text = _build_component_tooltip(comp)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.gui_input.connect(_on_component_item_gui_input.bind(comp))
		card.mouse_entered.connect(_on_component_card_hover.bind(comp))
		card.mouse_exited.connect(_on_component_card_unhover)
		garage.component_inventory_list.add_child(card)

# Full breakdown for the tooltip: dominant tile types (so "14 tiles" on the
# card face becomes actionable - a Torso that's mostly Amplifiers reads very
# differently from one that's mostly Catalysts), exact modifier percentages,
# and the exact Black Market forbidden-type list.
func _build_component_tooltip(comp) -> String:
	var lines = ["%s - drag onto its slot on the diagram above to equip/swap" % comp.component_name]

	if comp.hex_grid:
		var type_counts = {}
		for t in comp.hex_grid.get_all_tiles():
			type_counts[t.tile_type] = type_counts.get(t.tile_type, 0) + 1
		if not type_counts.is_empty():
			var types_sorted = type_counts.keys()
			types_sorted.sort_custom(func(a, b): return type_counts[a] > type_counts[b])
			var top = types_sorted.slice(0, 4)
			var breakdown = ", ".join(top.map(func(t): return "%s x%d" % [t, type_counts[t]]))
			if types_sorted.size() > top.size():
				breakdown += ", +%d more type(s)" % (types_sorted.size() - top.size())
			lines.append(breakdown)

	if not comp.stat_modifiers.is_empty():
		for stat in comp.stat_modifiers.keys():
			var pct = int(round((float(comp.stat_modifiers[stat]) - 1.0) * 100.0))
			lines.append("Modifier: %s +%d%%" % [str(stat), pct])

	if not comp.forbidden_tile_types.is_empty():
		lines.append("Black Market drawback - rejects: %s" % ", ".join(comp.forbidden_tile_types))

	return "\n".join(lines)

# Hovering a spare card temporarily frames the shared mini hex-grid preview
# (side_grid_container) on THIS component's actual shape instead of always
# showing whatever tab is active - "does this Torso look like a good build"
# no longer requires dragging it onto the diagram first to find out.
func _on_component_card_hover(comp):
	if garage.grid_renderer and comp.hex_grid:
		garage.grid_renderer.setup(comp.hex_grid, garage, comp.valid_hexes)

func _on_component_card_unhover():
	if garage.grid_renderer and garage.active_component:
		garage.grid_renderer.setup(garage.active_component.hex_grid, garage, garage.active_component.valid_hexes)

# Mirrors _on_inventory_item_gui_input's hex-tile drag-start pattern below,
# just for spare-component cards instead of tiles.
func _on_component_item_gui_input(event: InputEvent, comp):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		garage.dragged_component = comp
		if garage._component_drag_label:
			garage._component_drag_label.text = "%s\n%s" % [garage._slot_display_name(comp.slot_type), comp.component_name]
		garage.component_drag_preview.show()
		garage.component_drag_preview.global_position = garage.get_viewport().get_mouse_position()

func _drop_component(pos: Vector2):
	var comp = garage.dragged_component
	garage.dragged_component = null
	garage.component_drag_preview.hide()
	if garage.component_diagram:
		garage.component_diagram.set_highlight(-1)
	if not comp:
		return

	if not garage.component_diagram:
		return
	var target_slot = garage.component_diagram.get_slot_at_point(pos)
	if target_slot == -1:
		return # dropped outside any slot box - stays in the spare pool, no-op

	if target_slot != comp.slot_type:
		garage._show_warning("%s doesn't fit the %s slot" % [comp.component_name, garage._slot_display_name(target_slot)])
		return

	var main = garage.get_parent()
	if not main or main.get("player_component_inventory") == null or main.get("player") == null:
		return

	main.player_component_inventory.erase(comp)

	var main_player = main.player
	var old = main_player.components.get(target_slot, null)
	if old:
		main_player.remove_child(old)
		main_player.components.erase(target_slot)
		main.player_component_inventory.append(old)

	main_player.equip_component(comp)
	garage._refresh_component_ui()
	garage._refresh_inventory_ui()
	garage._show_scrap_float("Equipped %s" % comp.component_name, Color(0.3, 0.9, 1.0))

func refresh_inventory_ui():
	refresh_component_list()

	for c in garage.inv_vbox.get_children():
		c.queue_free()

	if garage.scrap_label:
		var main = garage.get_parent()
		if main and main.get("player_scrap") != null:
			garage.scrap_label.text = "Scrap: " + str(main.player_scrap)


	var search_text = ""
	if garage.search_input: search_text = garage.search_input.text.to_lower()
	var filter_rarity = 99
	if garage.rarity_filter: filter_rarity = garage.rarity_filter.get_selected_id()

	var grouped_inventory = {}
	for tile in garage.inventory:
		var key = tile.tile_type + "_" + str(tile.rarity)
		if not grouped_inventory.has(key):
			grouped_inventory[key] = []
		grouped_inventory[key].append(tile)

	var sorted_keys = grouped_inventory.keys()
	var sort_by_type = garage.tile_sort != null and garage.tile_sort.get_selected_id() == 1
	if sort_by_type:
		sorted_keys.sort_custom(func(a, b):
			var ta = grouped_inventory[a][0]
			var tb = grouped_inventory[b][0]
			if ta.tile_type == tb.tile_type:
				return ta.rarity > tb.rarity
			return ta.tile_type < tb.tile_type
		)
	else:
		sorted_keys.sort_custom(func(a, b):
			var ta = grouped_inventory[a][0]
			var tb = grouped_inventory[b][0]
			if ta.rarity == tb.rarity:
				return ta.tile_type < tb.tile_type
			return ta.rarity > tb.rarity
		)

	for key in sorted_keys:
		var stack = grouped_inventory[key]
		var tile = stack[0]
		var count = stack.size()

		if search_text != "" and not tile.tile_type.to_lower().contains(search_text):
			continue
		if filter_rarity != 99 and tile.rarity != filter_rarity:
			continue

		var btn = Button.new()
		var mult = 1.0 + (tile.rarity * 0.15)
		var rarity_name = ["Common", "Uncommon", "Rare", "Legendary", "Mythic"][tile.rarity]
		var rarity_colors = [Color(0.5, 0.5, 0.5), Color(0.2, 0.7, 0.3), Color(0.2, 0.4, 0.8), Color(0.8, 0.5, 0.1), Color(0.1, 0.8, 0.8)]

		var style = StyleBoxFlat.new()
		style.bg_color = rarity_colors[tile.rarity] * 0.5 # Darkened background
		style.border_width_bottom = 2
		style.border_color = rarity_colors[tile.rarity]
		btn.add_theme_stylebox_override("normal", style)

		if tile.rarity == 4:
			btn.material = garage._get_mythic_shimmer_mat()

		btn.text = tile.tile_type + "\n" + rarity_name + " (x" + str(snapped(mult, 0.01)) + ")"
		if count > 1:
			btn.text += " [%d]" % count
		btn.custom_minimum_size = Vector2(0, 50)
		btn.gui_input.connect(_on_inventory_item_gui_input.bind(tile))
		garage.inv_vbox.add_child(btn)

func handle_input(event):
	if event is InputEventMouseMotion:
		if garage.dragged_tile:
			garage.drag_preview.global_position = event.global_position
		if garage.dragged_component:
			garage.component_drag_preview.global_position = event.global_position
			if garage.component_diagram:
				garage.component_diagram.set_highlight(garage.component_diagram.get_slot_at_point(event.global_position))

	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if garage.dragged_tile:
			_drop_tile(event.global_position)
		if garage.dragged_component:
			_drop_component(event.global_position)

# Polling (not motion-event-driven) on purpose: if the cursor goes
# perfectly still, no InputEventMouseMotion fires at all, so a "have you
# been stationary for N seconds" check needs a per-frame timer instead of
# only re-checking whenever the mouse happens to twitch.
func handle_process(_delta):
	if not garage.dragged_tile:
		return

	var pos = garage.get_viewport().get_mouse_position()
	if not garage.grid_renderer.get_global_rect().has_point(pos):
		garage.drag_hover_hex = null
		if not garage.fill_mode:
			garage.grid_renderer.fill_preview_hexes = []
			garage.grid_renderer.queue_redraw()
		return

	var local_pos = garage.grid_renderer.get_global_transform().affine_inverse() * pos
	var hex = garage.grid_renderer._pixel_to_hex(local_pos)

	if garage.dragged_tile.get_footprint_size() > 1:
		# Footprint tiles skip the pause-to-fill-mode tracking entirely -
		# always preview the 3 cells the current rotation would occupy so
		# scrolling to rotate reads as immediate feedback.
		garage.drag_hover_hex = hex
		var c1 = hex.neighbor(garage.footprint_rotation)
		var c2 = c1.neighbor(garage.footprint_rotation)
		garage.grid_renderer.fill_preview_hexes = [hex, c1, c2]
		garage.grid_renderer.queue_redraw()
		return

	if garage.drag_hover_hex == null or not hex.equals(garage.drag_hover_hex):
		garage.drag_hover_hex = hex
		garage.drag_hover_since = Time.get_ticks_msec() / 1000.0
	elif not garage.fill_mode:
		var paused_for = Time.get_ticks_msec() / 1000.0 - garage.drag_hover_since
		if paused_for >= garage.FILL_PAUSE_THRESHOLD:
			garage.fill_mode = true
			garage.fill_origin_hex = hex
			# Template stamping (see GarageMenu.fill_template_tile's field
			# comment): if the hex you paused/hovered on already holds a
			# tile of the same type you're dragging, every tile placed for
			# the rest of this fill line inherits ITS configuration.
			if garage.grid_renderer.hex_grid and garage.grid_renderer.hex_grid.has_tile(hex):
				var origin_tile = garage.grid_renderer.hex_grid.get_tile(hex)
				if origin_tile and origin_tile.tile_type == garage.dragged_tile.tile_type:
					garage.fill_template_tile = origin_tile

	if garage.fill_mode:
		var line = HexCoord.hex_line(garage.fill_origin_hex, hex)
		garage.grid_renderer.fill_preview_hexes = line
		garage.grid_renderer.queue_redraw()

func _on_inventory_item_gui_input(event: InputEvent, tile: HexTile):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			garage.dragged_tile = tile
			garage.drag_preview.show()
			garage.drag_preview.global_position = garage.get_viewport().get_mouse_position()
			garage.tooltip_label.hide()
			# Fresh drag - reset any leftover fill-mode state from a
			# previous drag/drop cycle.
			garage.drag_hover_hex = null
			garage.fill_mode = false
			garage.fill_origin_hex = null
			garage.fill_template_tile = null
			garage.footprint_rotation = 0
			garage.grid_renderer.fill_preview_hexes = []
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if not garage.tile_action_menu:
				garage.tile_action_menu = TileActionMenu.new(garage)
			garage.tile_action_menu.scrap_tile(tile)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			if not garage.tile_action_menu:
				garage.tile_action_menu = TileActionMenu.new(garage)
			garage.tile_action_menu.upgrade_tile(tile)

func _drop_tile(pos: Vector2):
	# Multi-cell tiles (Lance - see HexTile.footprint_offsets) never use the
	# fill-line paint path: that path places several SEPARATE copies of a
	# single-cell tile along a drag, and a footprint tile compounding that
	# (each "copy" needing its OWN valid 3-cell line) is both nonsensical
	# and not something any player would actually want - always fall
	# through to the normal single-drop path instead.
	var is_footprint_tile = garage.dragged_tile and garage.dragged_tile.get_footprint_size() > 1
	if garage.fill_mode and garage.grid_renderer.fill_preview_hexes.size() > 1 and not is_footprint_tile:
		_drop_fill_line()
	elif garage.grid_renderer.get_global_rect().has_point(pos):
		var local_pos = garage.grid_renderer.get_global_transform().affine_inverse() * pos
		var hex = garage.grid_renderer._pixel_to_hex(local_pos)

		# Check if valid in current component shape
		if garage.active_component and not garage.active_component.can_place_tile(hex):
			print("Cannot place tile outside component bounds or on fixed sinks!")
		elif garage.active_component and garage.dragged_tile and garage.active_component.forbidden_tile_types.has(garage.dragged_tile.tile_type):
			# Black Market drawback: this component refuses certain tile types
			garage._show_scrap_float("FORBIDDEN: this part rejects %s tiles" % garage.dragged_tile.tile_type, Color(1.0, 0.4, 0.4))
		elif hex.q == 0 and hex.r == 0 and garage.active_component.slot_type == HexTile.BodySlot.TORSO:
			print("Cannot override Torso Core!")
			# Return the dragged tile to inventory
			garage.inventory.append(garage.dragged_tile)
			garage._refresh_inventory_ui()
		elif garage.grid_renderer.hex_grid:
			if is_footprint_tile:
				_drop_footprint_tile(hex)
			elif not garage.grid_renderer.hex_grid.has_tile(hex):
				garage.grid_renderer.hex_grid.add_tile(hex, garage.dragged_tile)
				garage.inventory.erase(garage.dragged_tile)
				garage._refresh_inventory_ui()
				garage.grid_renderer.queue_redraw()
				garage._tutorial_notify("tile_placed:any")
				garage._tutorial_notify("tile_placed:" + garage.dragged_tile.tile_type)
			else:
				print("Slot occupied!")

	garage.dragged_tile = null
	garage.drag_preview.hide()
	garage.fill_mode = false
	garage.fill_origin_hex = null
	garage.fill_template_tile = null
	garage.drag_hover_hex = null
	garage.grid_renderer.fill_preview_hexes = []

# Tries garage.footprint_rotation first (the direction the player scrolled
# to while dragging - see GarageGridRenderer._gui_input's wheel handling),
# then falls back through the other 5 directions in order so a placement
# still usually succeeds even if the chosen orientation doesn't fit. The
# dropped hex itself becomes the anchor/first cell.
func _drop_footprint_tile(hex: HexCoord):
	if garage.grid_renderer.hex_grid.has_tile(hex):
		print("Slot occupied!")
		garage.inventory.append(garage.dragged_tile)
		garage._refresh_inventory_ui()
		return

	for i in range(6):
		var d = (garage.footprint_rotation + i) % 6
		var c1 = hex.neighbor(d)
		var c2 = c1.neighbor(d)
		if not garage.active_component.can_place_tile(c1) or not garage.active_component.can_place_tile(c2):
			continue
		if garage.grid_renderer.hex_grid.has_tile(c1) or garage.grid_renderer.hex_grid.has_tile(c2):
			continue

		garage.dragged_tile.footprint_offsets = [
			Vector2i(c1.q - hex.q, c1.r - hex.r),
			Vector2i(c2.q - hex.q, c2.r - hex.r),
		]
		garage.grid_renderer.hex_grid.add_tile(hex, garage.dragged_tile)
		garage.inventory.erase(garage.dragged_tile)
		garage._refresh_inventory_ui()
		garage.grid_renderer.queue_redraw()
		garage._tutorial_notify("tile_placed:any")
		garage._tutorial_notify("tile_placed:" + garage.dragged_tile.tile_type)
		return

	garage._show_scrap_float("No room for a 3-in-a-row mount here", Color(1.0, 0.4, 0.4))
	garage.inventory.append(garage.dragged_tile)
	garage._refresh_inventory_ui()

# Places dragged_tile at the first valid cell in the paused-then-dragged
# line, then keeps placing additional matching copies (same tile_type +
# rarity) pulled from inventory at each subsequent valid, empty cell along
# the line - stopping early if inventory runs out. Skips the Torso Core
# cell and anything outside the component's shape, same protections as a
# normal single-tile drop.
func _drop_fill_line():
	if not garage.grid_renderer.hex_grid or not garage.dragged_tile:
		return

	var placed_first = false
	for hex in garage.grid_renderer.fill_preview_hexes:
		if garage.active_component and not garage.active_component.can_place_tile(hex):
			continue
		if garage.active_component and garage.active_component.slot_type == HexTile.BodySlot.TORSO and hex.q == 0 and hex.r == 0:
			continue
		if garage.grid_renderer.hex_grid.has_tile(hex):
			continue

		if not placed_first:
			garage.grid_renderer.hex_grid.add_tile(hex, garage.dragged_tile)
			garage.inventory.erase(garage.dragged_tile)
			placed_first = true
			if garage.fill_template_tile:
				garage.dragged_tile.copy_config_from(garage.fill_template_tile)
		else:
			var match_idx = _find_matching_inventory_index(garage.dragged_tile)
			if match_idx < 0:
				break # Out of matching copies - stop filling
			var next_tile = garage.inventory[match_idx]
			garage.inventory.remove_at(match_idx)
			garage.grid_renderer.hex_grid.add_tile(hex, next_tile)
			if garage.fill_template_tile:
				next_tile.copy_config_from(garage.fill_template_tile)

	if not placed_first:
		# Even the origin cell was blocked/invalid - give the tile back
		garage.inventory.append(garage.dragged_tile)
	else:
		garage._tutorial_notify("tile_placed:any")
		garage._tutorial_notify("tile_placed:" + garage.dragged_tile.tile_type)

	garage._refresh_inventory_ui()
	garage.grid_renderer.queue_redraw()

func _find_matching_inventory_index(reference: HexTile) -> int:
	for i in range(garage.inventory.size()):
		var t = garage.inventory[i]
		if t.tile_type == reference.tile_type and t.rarity == reference.rarity:
			return i
	return -1

func add_to_inventory(tile: HexTile):
	garage.inventory.append(tile)
	garage._refresh_inventory_ui()

# One-line "what does this actually do" per tile type - previously the
# inventory tooltip only ever showed stat numbers (power multiplier, sync
# shift, ...), which tells a new player nothing if they don't already know
# what a Resonator or a Filter IS. Kept short on purpose - full mechanics
# still live in the Synergy Codex / tutorial, this is just the "why would I
# place this" one-liner at a glance.
const TILE_TYPE_BLURBS = {
	"Splitter": "Splits one incoming packet across multiple output faces.",
	"Amplifier": "Boosts a packet's magnitude - the core damage-scaling tile.",
	"Reflector": "Redirects a packet's flow direction (rotatable with E).",
	"Catalyst": "Converts a packet's synergy toward one chosen element.",
	"Elemental Infuser": "Blends in a secondary synergy alongside whatever's already flowing.",
	"Filter": "Passes one chosen synergy through in full; everything else gets partly converted back to RAW.",
	"Jumpjet": "Grants mobility (jump or, at Mythic, blink) - powers movement, not weapons.",
	"Maneuvering Thruster": "Kills inertia faster and turns more responsively at speed - agility, not raw movement power.",
	"Weapon Mount": "Fires accumulated energy as a projectile - this is where damage actually leaves the mech.",
	"Lance Mount": "3-hex capital weapon. Fires itself once 6 of its faces are each fed 10,000+ energy - a long-range beam that leaves a lingering damage field, then a 10s cooldown.",
	"Accumulator": "Banks energy for one big charged shot on a trigger key (1/2/3) instead of firing immediately.",
	"Actuator": "Drives melee/ramming behavior and movement speed bonuses.",
	"Directional Conduit": "A wire - passes energy through, rotatable to bias flow direction.",
	"Magnet": "Pulls loot toward the mech - Mythic adds a rarity filter and can flip to reflecting enemy shots.",
	"Microcore": "A smaller Core Reactor variant for outside the Torso - generates energy on backpack/peripheral grids.",
	"Resonator": "Amplifies every packet that crosses it, and lets crossing paths trade elemental status procs (bigger payoff at Mythic).",
	"Shield Generator": "Generates a damage-absorbing shield with an elemental counter-type.",
	"Drone Bay": "Deploys an independent companion Drone with its own small hex-grid loadout.",
	"Missile Rack": "(Stub - not fully implemented yet) planned dedicated indirect-fire weapon mount.",
	"Component Link": "Internal routing tile connecting one component's grid to another - not normally placed by hand.",
}

func on_tooltip_requested(tile: HexTile, screen_pos: Vector2):
	if garage.dragged_tile: return
	garage.tooltip_label.show()
	garage.tooltip_label.global_position = screen_pos + Vector2(15, 15)
	var mult = 1.0 + (tile.rarity * 0.15)
	var rarity_name = ["Common", "Uncommon", "Rare", "Legendary", "Mythic"][tile.rarity]
	var text = "[ %s ] %s\nPower Multiplier: x%s" % [rarity_name, tile.tile_type, str(snapped(mult, 0.01))]
	if TILE_TYPE_BLURBS.has(tile.tile_type):
		text += "\n" + TILE_TYPE_BLURBS[tile.tile_type]
	if "sync_adjustment" in tile and tile.sync_adjustment != 0:
		text += "\nSync Shift: " + ("+" if tile.sync_adjustment > 0 else "") + str(tile.sync_adjustment)
	if "amplification" in tile:
		text += "\nAmplification: " + str(tile.amplification)
	if "split_count" in tile:
		text += "\nSplits: " + str(tile.split_count)
	garage.tooltip_label.text = text

func on_tooltip_cleared():
	garage.tooltip_label.text = ""
	garage.tooltip_label.visible = false
