class_name GarageMenu
extends CanvasLayer



const ComponentEquipment = preload("res://scripts/core/ComponentEquipment.gd")
const SplitterTile = preload("res://scripts/tiles/SplitterTile.gd")
const AmplifierTile = preload("res://scripts/tiles/AmplifierTile.gd")
const CatalystTile = preload("res://scripts/tiles/CatalystTile.gd")
const GarageGridRenderer = preload("res://scripts/ui/GarageGridRenderer.gd")

var inventory_panel: PanelContainer
var grid_panel: PanelContainer
var grid_renderer: GarageGridRenderer
var inv_vbox: VBoxContainer
var stats_label: Label
var tooltip_label: Label
var component_tabs: TabBar
var warning_label: Label
var scrap_label: Label


var active_component: ComponentEquipment
var mech_components: Dictionary = {}

var dragged_tile: HexTile = null
var drag_preview: Polygon2D = null

var inventory: Array = []
var search_input: LineEdit
var rarity_filter: OptionButton
var sim_button: Button

var is_simulating: bool = false

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_ui()
	
	# Hook up the player's components if they exist
	if get_parent() and get_parent().get("player") != null:
		mech_components = get_parent().player.components
			
		if get_parent().get("player_inventory") != null:
			inventory = get_parent().player_inventory
			
		# Fallback initial loadout if empty
		if inventory.is_empty():
			_populate_mock_inventory()
			
	_populate_component_tabs()
	_refresh_inventory_ui()

func _populate_component_tabs():
	component_tabs.clear_tabs()
	if mech_components.is_empty():
		return
		
	for slot in mech_components.keys():
		var comp = mech_components[slot]
		component_tabs.add_tab(comp.component_name)
		component_tabs.set_tab_metadata(component_tabs.get_tab_count() - 1, slot)
		
	_on_tab_changed(0)

func _refresh_component_ui():
	# If player was loaded or components changed, update the reference and tabs
	if get_parent() and get_parent().get("player") != null:
		mech_components = get_parent().player.components
	_populate_component_tabs()

func _on_tab_changed(index: int):
	if index < 0 or index >= component_tabs.get_tab_count():
		return
		
	var slot = component_tabs.get_tab_metadata(index)
	if slot == null: return
	
	active_component = mech_components[slot]
	grid_renderer.setup(active_component.hex_grid, self)
	grid_renderer.active_component = active_component
	
	# Ensure Torso always has a Core
	if slot == HexTile.BodySlot.TORSO:
		var has_core = false
		var h0 = HexCoord.new(0, 0)
		if active_component.hex_grid.has_tile(h0):
			var existing_tile = active_component.hex_grid.get_tile(h0)
			if existing_tile and existing_tile.tile_type == "Core Reactor":
				has_core = true
			else:
				var removed = active_component.hex_grid.remove_tile(h0)
				inventory.append(removed)
		
		if not has_core:
			var core_tile = load("res://scripts/tiles/CoreTile.gd").new()
			core_tile.body_slot = HexTile.BodySlot.TORSO
			active_component.hex_grid.add_tile(h0, core_tile)
			print("Restored missing Torso Core!")
func _populate_mock_inventory():
	var main = get_tree().current_scene
	if main and "player_inventory" in main and main.player_inventory.size() > 0:
		inventory = main.player_inventory.duplicate()
		return
		
	# Fallback mock inventory
	var rare_split = SplitterTile.new()
	rare_split.rarity = HexTile.Rarity.RARE
	inventory.append(rare_split)
	
	var rare_amp = AmplifierTile.new()
	rare_amp.rarity = HexTile.Rarity.RARE
	inventory.append(rare_amp)
	
	var bp_link = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.BACKPACK, true)
	bp_link.tile_type = "Backpack Link"
	inventory.append(bp_link)
	
	var leg_cat = CatalystTile.new()
	leg_cat.output_synergy = EnergyPacket.SynergyType.LIGHTNING
	leg_cat.rarity = HexTile.Rarity.LEGENDARY
	inventory.append(leg_cat)
	
	var poison_infuser = load("res://scripts/tiles/InfuserTile.gd").new()
	poison_infuser.secondary_synergy = EnergyPacket.SynergyType.POISON
	poison_infuser.rarity = HexTile.Rarity.RARE
	inventory.append(poison_infuser)
	
	var reflector = load("res://scripts/tiles/ReflectorTile.gd").new()
	reflector.rotation_steps = 1
	reflector.rarity = HexTile.Rarity.COMMON
	inventory.append(reflector)

func _setup_ui():
	layer = 10
	
	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08, 0.4) # Mostly transparent
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	var hsplit = HSplitContainer.new()
	hsplit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(hsplit)
	
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
	
	component_tabs = TabBar.new()
	component_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	component_tabs.tab_changed.connect(_on_tab_changed)
	tab_hbox.add_child(component_tabs)
	
	var action_vbox = VBoxContainer.new()
	tab_hbox.add_child(action_vbox)
	
	var swap_btn = Button.new()
	swap_btn.text = "Swap Component"
	swap_btn.pressed.connect(_on_swap_component_pressed)
	action_vbox.add_child(swap_btn)
	
	var infuse_btn = Button.new()
	infuse_btn.text = "Infuse (Destroy part)"
	infuse_btn.pressed.connect(_on_infuse_component_pressed)
	action_vbox.add_child(infuse_btn)
	
	grid_panel = PanelContainer.new()
	grid_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_vbox.add_child(grid_panel)
	
	grid_renderer = GarageGridRenderer.new()
	grid_renderer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_renderer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_renderer.tooltip_requested.connect(_on_tooltip_requested)
	grid_renderer.tooltip_cleared.connect(_on_tooltip_cleared)
	grid_renderer.tile_clicked.connect(_on_tile_clicked)
	grid_panel.add_child(grid_renderer)
	
	# Add a warning label
	warning_label = Label.new()
	warning_label.name = "WarningLabel"
	warning_label.modulate = Color(1.0, 0.5, 0.5)
	warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning_label.hide()
	top_bar.add_child(warning_label)
	
	# Bottom Bar
	var bottom_bar = HBoxContainer.new()
	left_vbox.add_child(bottom_bar)
	
	sim_button = Button.new()
	sim_button.name = "SimButton"
	sim_button.text = "Simulate Energy Flow"
	sim_button.custom_minimum_size = Vector2(200, 50)
	sim_button.pressed.connect(_on_simulate_pressed)
	bottom_bar.add_child(sim_button)
	
	var auto_button = Button.new()
	auto_button.text = "Auto-Equip"
	auto_button.custom_minimum_size = Vector2(120, 50)
	auto_button.pressed.connect(_on_auto_equip_pressed)
	bottom_bar.add_child(auto_button)
	
	var sep_fire_toggle = CheckButton.new()
	sep_fire_toggle.text = "Separate L/R Firing"
	
	if get_parent() and get_parent().get("player") != null:
		sep_fire_toggle.button_pressed = get_parent().player.separate_arm_firing
	else:
		sep_fire_toggle.button_pressed = true
		
	sep_fire_toggle.toggled.connect(func(pressed):
		if get_parent() and get_parent().get("player") != null:
			get_parent().player.separate_arm_firing = pressed
	)
	bottom_bar.add_child(sep_fire_toggle)
	
	var paths_toggle = CheckButton.new()
	paths_toggle.text = "Show Static Paths"
	paths_toggle.button_pressed = true
	paths_toggle.toggled.connect(func(pressed):
		grid_renderer.show_static_paths = pressed
		grid_renderer.queue_redraw()
	)
	bottom_bar.add_child(paths_toggle)
	
	var deploy_button = Button.new()
	deploy_button.text = "Deploy to Battlefield ->"
	deploy_button.custom_minimum_size = Vector2(200, 50)
	deploy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deploy_button.pressed.connect(func():
		var main = get_parent()
		if main and main.get("player") != null:
			SaveManager.save_game("autosave", main.player, inventory)
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
			var main = get_parent()
			if main and main.get("player") != null:
				if SaveManager.load_loadout(i, main.player, inventory):
					_refresh_component_ui()
					_refresh_inventory_ui()
		)
		loadout_bar.add_child(btn)
		
		var save_btn = Button.new()
		save_btn.text = "Save " + str(i)
		save_btn.pressed.connect(func():
			var main = get_parent()
			if main and main.get("player") != null:
				SaveManager.save_loadout(i, main.player)
		)
		loadout_bar.add_child(save_btn)
	
	# Right Side: Inventory & Stats
	inventory_panel = PanelContainer.new()
	inventory_panel.custom_minimum_size = Vector2(300, 0)
	hsplit.add_child(inventory_panel)
	
	var right_vbox = VBoxContainer.new()
	inventory_panel.add_child(right_vbox)
	
	stats_label = Label.new()
	stats_label.text = "=== COMPONENT INFO ===\nGrid: Mech Core\nPower: 0\n\n=== SIMULATION ===\nStep: 0\nActive Packets: 0\nTotal Energy: 0"
	right_vbox.add_child(stats_label)
	
	var sep = HSeparator.new()
	right_vbox.add_child(sep)
	
	var inv_label = Label.new()
	inv_label.text = "INVENTORY (Right-click to scrap)"
	inv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_vbox.add_child(inv_label)
	
	scrap_label = Label.new()
	scrap_label.text = "Scrap: 0"
	scrap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scrap_label.modulate = Color(1.0, 0.8, 0.2)
	right_vbox.add_child(scrap_label)

	
	var filter_hbox = HBoxContainer.new()
	right_vbox.add_child(filter_hbox)
	
	search_input = LineEdit.new()
	search_input.placeholder_text = "Search..."
	search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_input.text_changed.connect(func(_text): _refresh_inventory_ui())
	filter_hbox.add_child(search_input)
	
	rarity_filter = OptionButton.new()
	rarity_filter.add_item("All", 99)
	rarity_filter.add_item("Common", 0)
	rarity_filter.add_item("Uncommon", 1)
	rarity_filter.add_item("Rare", 2)
	rarity_filter.add_item("Legendary", 3)
	rarity_filter.item_selected.connect(func(_index): _refresh_inventory_ui())
	filter_hbox.add_child(rarity_filter)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(scroll)
	
	inv_vbox = VBoxContainer.new()
	inv_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inv_vbox)
	
	# Drag preview setup
	drag_preview = Polygon2D.new()
	var pts = PackedVector2Array()
	for i in range(6):
		var angle = deg_to_rad(60 * i - 30)
		pts.append(Vector2(cos(angle), sin(angle)) * 20)
	drag_preview.polygon = pts
	drag_preview.color = Color(1, 1, 1, 0.5)
	drag_preview.hide()
	add_child(drag_preview)
	
	# Tooltip
	tooltip_label = Label.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.9)
	style.corner_radius_top_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 10
	style.content_margin_top = 10
	tooltip_label.add_theme_stylebox_override("normal", style)
	tooltip_label.hide()
	add_child(tooltip_label)

func _refresh_inventory_ui():
	for c in inv_vbox.get_children():
		c.queue_free()
		
	if scrap_label:
		var main = get_parent()
		if main and main.get("player_scrap") != null:
			scrap_label.text = "Scrap: " + str(main.player_scrap)

		
	var search_text = ""
	if search_input: search_text = search_input.text.to_lower()
	var filter_rarity = 99
	if rarity_filter: filter_rarity = rarity_filter.get_selected_id()
	
	for i in range(inventory.size()):
		var tile = inventory[i]
		
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
			var shader = Shader.new()
			shader.code = """
			shader_type canvas_item;
			void fragment() {
				float wave = sin(TIME * 1.5 - UV.x * 5.0 - UV.y * 5.0);
				float shine = smoothstep(0.9, 1.0, wave) * 0.3;
				COLOR = COLOR + vec4(0.3, 0.9, 0.9, 0.0) * shine;
			}
			"""
			var mat = ShaderMaterial.new()
			mat.shader = shader
			btn.material = mat
		
		btn.text = tile.tile_type + "\n" + rarity_name + " (x" + str(snapped(mult, 0.01)) + ")"
		btn.custom_minimum_size = Vector2(0, 50)
		btn.gui_input.connect(_on_inventory_item_gui_input.bind(tile))
		inv_vbox.add_child(btn)


func _input(event):
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		var main = get_parent()
		if main and main.has_method("_close_garage"):
			main._close_garage()
		else:
			queue_free()
			
	if event is InputEventMouseMotion:
		if dragged_tile:
			drag_preview.global_position = event.global_position
			
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if dragged_tile:
			_drop_tile(event.global_position)

func _on_inventory_item_gui_input(event: InputEvent, tile: HexTile):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragged_tile = tile
			drag_preview.show()
			drag_preview.global_position = get_viewport().get_mouse_position()
			tooltip_label.hide()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_scrap_tile(tile)

func _scrap_tile(tile: HexTile):
	var main = get_parent()
	if main and main.get("player_scrap") != null:
		var scrap_value = 10
		if tile.rarity == 1: scrap_value = 25
		elif tile.rarity == 2: scrap_value = 75
		elif tile.rarity == 3: scrap_value = 250
		elif tile.rarity == 4: scrap_value = 1000
		
		main.player_scrap += scrap_value
		inventory.erase(tile)
		
		var float_lbl = Label.new()
		float_lbl.text = "+" + str(scrap_value) + " Scrap"
		float_lbl.modulate = Color(1.0, 0.8, 0.2)
		float_lbl.global_position = get_viewport().get_mouse_position() - Vector2(20, 20)
		add_child(float_lbl)
		var tw = create_tween()
		tw.tween_property(float_lbl, "global_position:y", float_lbl.global_position.y - 50, 1.0)
		tw.parallel().tween_property(float_lbl, "modulate:a", 0.0, 1.0)
		tw.tween_callback(float_lbl.queue_free)
		
		_refresh_inventory_ui()

func _on_inventory_item_down(tile: HexTile):
	pass # Deprecated in favor of gui_input


func _drop_tile(pos: Vector2):
	if grid_renderer.get_global_rect().has_point(pos):
		var local_pos = grid_renderer.get_global_transform().affine_inverse() * pos
		var hex = grid_renderer._pixel_to_hex(local_pos)
		
		# Check if valid in current component shape
		if active_component and not active_component.can_place_tile(hex):
			print("Cannot place tile outside component bounds or on fixed sinks!")
		elif hex.q == 0 and hex.r == 0 and active_component.slot_type == HexTile.BodySlot.TORSO:
			print("Cannot override Torso Core!")
			# Return the dragged tile to inventory
			inventory.append(dragged_tile)
			_refresh_inventory_ui()
		elif grid_renderer.hex_grid:
			if not grid_renderer.hex_grid.has_tile(hex):
				grid_renderer.hex_grid.add_tile(hex, dragged_tile)
				inventory.erase(dragged_tile)
				_refresh_inventory_ui()
				grid_renderer.queue_redraw()
			else:
				print("Slot occupied!")
				
	dragged_tile = null
	drag_preview.hide()

func _add_to_inventory(tile: HexTile):
	inventory.append(tile)
	_refresh_inventory_ui()

func _on_tooltip_requested(tile: HexTile, screen_pos: Vector2):
	if dragged_tile: return
	tooltip_label.show()
	tooltip_label.global_position = screen_pos + Vector2(15, 15)
	var mult = 1.0 + (tile.rarity * 0.15)
	var rarity_name = ["Common", "Uncommon", "Rare", "Legendary", "Mythic"][tile.rarity]
	var text = "[ %s ] %s\nPower Multiplier: x%s" % [rarity_name, tile.tile_type, str(snapped(mult, 0.01))]
	if "sync_adjustment" in tile and tile.sync_adjustment != 0:
		text += "\nSync Shift: " + ("+" if tile.sync_adjustment > 0 else "") + str(tile.sync_adjustment)
	if "amplification" in tile:
		text += "\nAmplification: " + str(tile.amplification)
	if "split_count" in tile:
		text += "\nSplits: " + str(tile.split_count)
	tooltip_label.text = text

func _on_tooltip_cleared():
	tooltip_label.text = ""
	tooltip_label.visible = false

func _on_tile_clicked(tile: HexTile):
	if tile.tile_type == "Core Reactor":
		var popup = PopupPanel.new()
		var vbox = VBoxContainer.new()
		popup.add_child(vbox)
		
		var label = Label.new()
		label.text = "Configure Reactor Faces (Max %d)" % tile.get_max_faces()
		vbox.add_child(label)
		
		var directions = ["East", "South-East", "South-West", "West", "North-West", "North-East"]
		
		for i in range(6):
			var btn = CheckButton.new()
			btn.text = "Face " + str(i) + " (" + directions[i] + ")"
			btn.button_pressed = tile.active_faces.has(i)
			
			btn.toggled.connect(func(pressed):
				tile.toggle_face(i)
				grid_renderer.queue_redraw()
				for j in range(6):
					var child_btn = vbox.get_child(j + 1)
					if child_btn is CheckButton:
						child_btn.set_block_signals(true)
						child_btn.button_pressed = tile.active_faces.has(j)
						child_btn.set_block_signals(false)
			)
			vbox.add_child(btn)
			
		add_child(popup)
		popup.popup_centered(Vector2(250, 300))
		popup.popup_hide.connect(func(): popup.queue_free())
		
	elif tile.tile_type == "Splitter" or tile.tile_type == "Accessory Return":
		var popup = PopupPanel.new()
		var vbox = VBoxContainer.new()
		popup.add_child(vbox)
		
		var label = Label.new()
		label.text = "Configure Outputs (Max %d)" % tile.get_max_faces()
		vbox.add_child(label)
		
		var directions = ["East", "South-East", "South-West", "West", "North-West", "North-East"]
		
		for i in range(6):
			var btn = CheckButton.new()
			btn.text = "Face " + str(i) + " (" + directions[i] + ")"
			btn.button_pressed = tile.active_faces.has(i)
			
			btn.toggled.connect(func(pressed):
				tile.toggle_output(i)
				grid_renderer.queue_redraw()
				for j in range(6):
					var child_btn = vbox.get_child(j + 1)
					if child_btn is CheckButton:
						child_btn.set_block_signals(true)
						child_btn.button_pressed = tile.active_faces.has(j)
						child_btn.set_block_signals(false)
			)
			vbox.add_child(btn)
			
		add_child(popup)
		popup.popup_centered(Vector2(250, 300))
		popup.popup_hide.connect(func(): popup.queue_free())
		
	elif tile.tile_type == "Reflector":
		var popup = PopupPanel.new()
		var vbox = VBoxContainer.new()
		popup.add_child(vbox)
		
		var label = Label.new()
		label.text = "Configure Reflector Rotation"
		vbox.add_child(label)
		
		var btn = Button.new()
		btn.text = "Rotate 60 deg (Current: %d)" % tile.rotation_steps
		btn.pressed.connect(func():
			tile.rotation_steps = (tile.rotation_steps % 5) + 1
			btn.text = "Rotate 60 deg (Current: %d)" % tile.rotation_steps
			grid_renderer.queue_redraw()
		)
		vbox.add_child(btn)
		
		add_child(popup)
		popup.popup_centered(Vector2(250, 100))
		popup.popup_hide.connect(func(): popup.queue_free())
	
	elif tile.tile_type == "Elemental Infuser" or tile.tile_type == "Catalyst":
		var popup = PopupPanel.new()
		var vbox = VBoxContainer.new()
		popup.add_child(vbox)
		
		var label = Label.new()
		label.text = "Configure " + tile.tile_type + " Synergy"
		vbox.add_child(label)
		
		var SynergyType = EnergyPacket.SynergyType
		var btn = Button.new()
		var current_name = "RAW"
		var prop_name = "secondary_synergy" if tile.tile_type == "Elemental Infuser" else "target_synergy"
		for key_name in SynergyType.keys():
			if SynergyType[key_name] == tile.get(prop_name):
				current_name = key_name
				break
		btn.text = "Synergy: %s" % current_name
		btn.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.pressed:
				if event.button_index == MOUSE_BUTTON_LEFT:
					tile.cycle_synergy()
				elif event.button_index == MOUSE_BUTTON_RIGHT:
					if tile.has_method("cycle_synergy_backward"):
						tile.cycle_synergy_backward()
						
				var new_name = "RAW"
				for key_name in SynergyType.keys():
					if SynergyType[key_name] == tile.get(prop_name):
						new_name = key_name
						break
				btn.text = "Synergy: %s" % new_name
				grid_renderer.queue_redraw()
		)
		vbox.add_child(btn)
		
		add_child(popup)
		popup.popup_centered(Vector2(250, 100))
		popup.popup_hide.connect(func(): popup.queue_free())
		
	elif tile.tile_type == "Microcore":
		var popup = PopupPanel.new()
		var vbox = VBoxContainer.new()
		popup.add_child(vbox)
		
		var label = Label.new()
		label.text = "Configure Microcore Outputs (Max %d)" % tile.get_max_faces()
		vbox.add_child(label)
		
		var directions = ["East", "South-East", "South-West", "West", "North-West", "North-East"]
		var SynergyType = EnergyPacket.SynergyType
		
		for i in range(6):
			var hbox = HBoxContainer.new()
			var btn = CheckButton.new()
			btn.text = "Face " + str(i) + " (" + directions[i] + ")"
			btn.button_pressed = tile.active_faces.has(i)
			hbox.add_child(btn)
			
			var syn_btn = Button.new()
			var current_syn = tile.get_face_output(i) if tile.has_method("get_face_output") else 0
			var syn_name = "RAW"
			for key_name in SynergyType.keys():
				if SynergyType[key_name] == current_syn:
					syn_name = key_name
					break
			syn_btn.text = "Syn: %s" % syn_name
			syn_btn.disabled = not btn.button_pressed or tile.rarity < HexTile.Rarity.UNCOMMON
			hbox.add_child(syn_btn)
			
			btn.toggled.connect(func(pressed):
				tile.toggle_face(i)
				syn_btn.disabled = not pressed or tile.rarity < HexTile.Rarity.UNCOMMON
				grid_renderer.queue_redraw()
				for j in range(6):
					var child_hbox = vbox.get_child(j + 1)
					var child_btn = child_hbox.get_child(0)
					if child_btn is CheckButton:
						child_btn.set_block_signals(true)
						child_btn.button_pressed = tile.active_faces.has(j)
						child_btn.set_block_signals(false)
			)
			
			syn_btn.pressed.connect(func():
				if tile.has_method("cycle_face_output"):
					tile.cycle_face_output(i)
					var new_syn = tile.get_face_output(i)
					var new_name = "RAW"
					for key_name in SynergyType.keys():
						if SynergyType[key_name] == new_syn:
							new_name = key_name
							break
					syn_btn.text = "Syn: %s" % new_name
			)
			vbox.add_child(hbox)
			
		add_child(popup)
		popup.popup_centered(Vector2(400, 300))
		popup.popup_hide.connect(func(): popup.queue_free())

func _on_simulate_pressed():
	if is_simulating:
		is_simulating = false
		if sim_button: sim_button.text = "Simulate Energy Flow"
		return
		
	if not grid_renderer.hex_grid: return
	
	is_simulating = true
	if sim_button: sim_button.text = "Stop Simulation"
	
	var initial_packets: Array[EnergyPacket] = []
	
	if active_component:
		# Clear pending packets on current grid before simulating
		for t in active_component.hex_grid.get_all_tiles():
			if "pending_packets" in t:
				t.pending_packets.clear()
				
		# 1. Generate local energy from any Core Reactors in this component's grid

		for h in grid_renderer.hex_grid.grid.keys():
			var tile = grid_renderer.hex_grid.get_tile(h)
			if tile.has_method("generate_energy"):
				var pkts = tile.generate_energy(grid_renderer.hex_grid)
				for p in pkts:
					p.position = HexCoord.new(h.x, h.y)
				initial_packets.append_array(pkts)
				
		# 2. Add actual transfer packets from Torso to simulate cross-component energy flow
		if active_component.slot_type != HexTile.BodySlot.TORSO:
			if mech_components.has(HexTile.BodySlot.TORSO) and mech_components[HexTile.BodySlot.TORSO]:
				var torso_comp = mech_components[HexTile.BodySlot.TORSO]
				var t_pkts = []
				for h in torso_comp.hex_grid.grid.keys():
					var tile = torso_comp.hex_grid.get_tile(h)
					if tile.has_method("generate_energy"):
						var pkts = tile.generate_energy(torso_comp.hex_grid)
						for p in pkts: p.position = HexCoord.new(h.x, h.y)
						t_pkts.append_array(pkts)
						
				var dummy_mech = load("res://scripts/entities/Mech.gd").new()
				dummy_mech._simulate_grid(torso_comp.hex_grid, t_pkts)
				var transfers = dummy_mech._collect_transfers(torso_comp)
				
				if transfers.has(active_component.slot_type):
					for packet in transfers[active_component.slot_type]:
						var dir = 3 # default west
						if active_component.slot_type == HexTile.BodySlot.ARM_L: dir = 3
						elif active_component.slot_type == HexTile.BodySlot.ARM_R: dir = 0
						elif active_component.slot_type == HexTile.BodySlot.HEAD: dir = 5
						elif active_component.slot_type == HexTile.BodySlot.LEG_L or active_component.slot_type == HexTile.BodySlot.LEG_R: dir = 1
						elif active_component.slot_type == HexTile.BodySlot.BACKPACK: dir = 4
						
						packet.direction = dir
						var opp_dir = (dir + 3) % 6
						packet.position = HexCoord.new(0, 0).neighbor(opp_dir)
						packet.is_active = true
						initial_packets.append(packet)
				dummy_mech.free()
			
		# 3. If Torso, pull returning energy from Head and Backpack
		if active_component.slot_type == HexTile.BodySlot.TORSO:
			var dummy_mech = load("res://scripts/entities/Mech.gd").new()
			
			# We need to simulate the Torso first to find out what it sends out!
			var dummy_t_pkts: Array[EnergyPacket] = []
			for p in initial_packets:
				dummy_t_pkts.append(p.copy())
			dummy_mech._simulate_grid(active_component.hex_grid, dummy_t_pkts)
			var dummy_transfers = dummy_mech._collect_transfers(active_component)
			
			for p_slot in [HexTile.BodySlot.HEAD, HexTile.BodySlot.BACKPACK]:
				if mech_components.has(p_slot) and mech_components[p_slot]:
					var p_comp = mech_components[p_slot]
					var p_pkts: Array[EnergyPacket] = []
					
					# 3a. Add energy received from Torso
					if dummy_transfers.has(p_slot):
						var incoming = dummy_transfers[p_slot]
						dummy_mech._route_to_peripheral(incoming, p_comp)
						p_pkts.append_array(incoming)
					
					# 3b. Add generated energy
					for h in p_comp.hex_grid.grid.keys():
						var tile = p_comp.hex_grid.get_tile(h)
						if tile.has_method("generate_energy"):
							var pkts = tile.generate_energy(p_comp.hex_grid)
							for p in pkts: p.position = HexCoord.new(h.x, h.y)
							p_pkts.append_array(pkts)
							
					dummy_mech._simulate_grid(p_comp.hex_grid, p_pkts)
					var transfers = dummy_mech._collect_transfers(p_comp)
					
					if transfers.has(HexTile.BodySlot.TORSO):
						# Find Accessory Return on Torso
						var acc_pos = HexCoord.new(0, 0)
						for coord_v in grid_renderer.hex_grid.grid.keys():
							var t = grid_renderer.hex_grid.grid[coord_v]
							if t.tile_type == "Accessory Return":
								acc_pos = HexCoord.new(coord_v.x, coord_v.y)
								break
								
						for pkt in transfers[HexTile.BodySlot.TORSO]:
							# Start them one step backwards based on their direction, but wait: we want them to enter the Accessory Return. 
							# If we just let them enter with a fixed direction like North (2), they will be processed.
							pkt.direction = 2 # Entering from North
							var opp_dir = (pkt.direction + 3) % 6
							pkt.position = acc_pos.neighbor(opp_dir)
							pkt.is_active = true
							initial_packets.append(pkt)
			dummy_mech.free()
			
			# Clean up any leftover packets on peripheral weapon mounts so they don't leak
			for p_slot in [HexTile.BodySlot.HEAD, HexTile.BodySlot.BACKPACK]:
				if mech_components.has(p_slot) and mech_components[p_slot]:
					for t in mech_components[p_slot].hex_grid.get_all_tiles():
						if t.tile_type == "Weapon Mount" and "pending_packets" in t:
							t.pending_packets.clear()
			
	for p in initial_packets:
		p.set_meta("source_hex", p.position)
		p.set_meta("target_hex", p.position)
		p.set_meta("anim_progress", 1.0)
		p.is_active = true
	
	grid_renderer.active_packets = initial_packets
	grid_renderer.simulation_step = 0
	
	_update_stats()
	_simulate_step()

func _simulate_step():
	var active = grid_renderer.active_packets
	if active.is_empty(): return
	
	grid_renderer.simulation_step += 1
	var new_packets: Array[EnergyPacket] = []
	
	for pkt in active:
		if not pkt.is_active: continue
		var pos = pkt.position
		
		# Animate to next tile
		var dir = pkt.direction
		var next_pos = pos.neighbor(dir)
		
		var out_pkts = []
		if grid_renderer.hex_grid.has_tile(next_pos):
			var tile = grid_renderer.hex_grid.get_tile(next_pos)
			out_pkts = tile.process_energy(pkt, (dir + 3) % 6)
			for out in out_pkts:
				if out.magnitude < 0.5:
					out.is_active = false
				out.position = next_pos
				out.set_meta("source_hex", pos)
				out.set_meta("target_hex", next_pos)
				out.set_meta("anim_progress", 0.0)
		else:
			var is_valid_empty = false
			if active_component and "valid_hexes" in active_component:
				for h in active_component.valid_hexes:
					if h.q == next_pos.q and h.r == next_pos.r:
						is_valid_empty = true
						break
						
			if is_valid_empty:
				# Pass straight through empty hex with 5% loss
				pkt.position = next_pos
				pkt.magnitude *= 0.95
				for k in pkt.synergies.keys():
					pkt.synergies[k] *= 0.95
				pkt.set_meta("source_hex", pos)
				pkt.set_meta("target_hex", next_pos)
				pkt.set_meta("anim_progress", 0.0)
				out_pkts = [pkt]
			else:
				# Bounce off edge of component
				pkt.direction = (dir + 3) % 6
				pkt.set_meta("source_hex", pos)
				pkt.set_meta("target_hex", pos)
				pkt.set_meta("anim_progress", 0.0)
				out_pkts = [pkt]
			
		new_packets.append_array(out_pkts)
		
	var merged_packets: Array[EnergyPacket] = []
	var packet_map: Dictionary = {}
	
	for pkt in new_packets:
		if not pkt.is_active: continue
		var key = str(pkt.position.q) + "_" + str(pkt.position.r) + "_" + str(pkt.direction)
		if packet_map.has(key):
			packet_map[key].merge(pkt)
		else:
			packet_map[key] = pkt
			merged_packets.append(pkt)
			
	grid_renderer.active_packets = merged_packets
	_update_stats()
	
	# Auto step loop
	var tree = get_tree()
	if tree:
		await tree.create_timer(0.5).timeout
		if not is_simulating:
			grid_renderer.active_packets.clear()
			_update_stats()
			return
			
		var still_alive = false
		for p in grid_renderer.active_packets:
			if grid_renderer.hex_grid.has_tile(p.position):
				still_alive = true
				break
		if still_alive:
			_simulate_step()
		else:
			is_simulating = false
			if sim_button: sim_button.text = "Simulate Energy Flow"

func _update_stats():
	var total_nrg = 0.0
	for p in grid_renderer.active_packets:
		total_nrg += p.magnitude
		
	var grid_size = grid_renderer.hex_grid.get_all_tiles().size() if grid_renderer.hex_grid else 0
	
	# Aggregate synergies from all Weapon Mounts/Accessory Returns
	var synergy_totals = {}
	var total_output = 0.0
	if grid_renderer.hex_grid:
		for t in grid_renderer.hex_grid.get_all_tiles():
			if "pending_packets" in t:
				for item in t.pending_packets:
					var p = item.packet
					total_output += p.magnitude
					for k in p.synergies:
						synergy_totals[k] = synergy_totals.get(k, 0.0) + p.synergies[k]
						
	var syn_str = ""
	var SynergyType = EnergyPacket.SynergyType
	var syn_names = SynergyType.keys()
	for k in synergy_totals.keys():
		var val = synergy_totals[k]
		if val > 0:
			var syn_name = "UNKNOWN"
			for key_name in syn_names:
				if SynergyType[key_name] == k:
					syn_name = key_name
					break
			syn_str += "%s: %s\n" % [syn_name, str(int(val)) if val < 1000000 else "%.2e" % val]
			
	if syn_str == "":
		syn_str = "None\n"
		
	var nrg_str = str(int(total_nrg))
	if total_nrg > 1000000000:
		nrg_str = "%.2e" % total_nrg
		
	var out_str = str(int(total_output))
	if total_output > 1000000000:
		out_str = "%.2e" % total_output
		
	stats_label.text = "=== COMPONENT INFO ===\nTiles Used: %d\n\n=== OUTPUT ===\nTotal Damage: %s\n%s\n=== SIMULATION ===\nStep: %d\nActive Packets: %d\nMoving Energy: %s" % [
		grid_size,
		out_str,
		syn_str,
		grid_renderer.simulation_step,
		grid_renderer.active_packets.size(),
		nrg_str
	]


func _on_auto_equip_pressed():
	if not active_component or not active_component.hex_grid:
		return
	
	var solver_class = load("res://scripts/core/AutoEquipSolver.gd")
	if not solver_class:
		print("Failed to load AutoEquipSolver")
		return
	var solver = solver_class.new()
	var new_inventory = solver.solve(active_component, inventory)
	if new_inventory != null:
		inventory = new_inventory
		grid_renderer.queue_redraw()
		_refresh_inventory_ui()
		print("Auto-Equip completed!")

func _on_swap_component_pressed():
	if not active_component: return
	var main = get_tree().current_scene
	if not main or main.get("player_component_inventory") == null: return
	
	var compatible = []
	for i in range(main.player_component_inventory.size()):
		var comp = main.player_component_inventory[i]
		if comp.slot_type == active_component.slot_type:
			compatible.append({"index": i, "comp": comp})
			
	if compatible.is_empty():
		_show_warning("No compatible components in inventory!")
		return
		
	var popup = PopupMenu.new()
	for item in compatible:
		var name_str = item.comp.component_name
		if item.comp.rarity > 0: name_str += " (Rarity %d)" % item.comp.rarity
		if item.comp.get("infusion_level", 0) > 0: name_str += " [Lv%d]" % item.comp.infusion_level
		popup.add_item(name_str, item.index)
		
	popup.id_pressed.connect(func(id):
		# Swap!
		var new_comp = main.player_component_inventory[id]
		main.player_component_inventory.remove_at(id)
		
		var main_player = main.player
		if main_player:
			# Unequip old
			main_player.remove_child(active_component)
			main_player.components.erase(active_component.slot_type)
			main.player_component_inventory.append(active_component)
			
			# Equip new
			main_player.equip_component(new_comp)
			mech_components = main_player.components
			
			_populate_component_tabs()
			popup.queue_free()
	)
	add_child(popup)
	popup.popup_centered(Vector2(300, 400))

func _on_infuse_component_pressed():
	if not active_component: return
	var main = get_tree().current_scene
	if not main or not "player_component_inventory" in main: return
	
	if main.player_component_inventory.is_empty():
		_show_warning("No components in inventory to dismantle!")
		return
		
	var popup = PopupMenu.new()
	for i in range(main.player_component_inventory.size()):
		var comp = main.player_component_inventory[i]
		var name_str = comp.component_name
		if comp.rarity > 0: name_str += " (Rarity %d)" % comp.rarity
		if comp.get("infusion_level", 0) > 0: name_str += " [Lv%d]" % comp.infusion_level
		popup.add_item("Dismantle " + name_str, i)
		
	popup.id_pressed.connect(func(id):
		var junk = main.player_component_inventory[id]
		main.player_component_inventory.remove_at(id)
		
		# Transfer tiles from dismantled component to inventory
		var junk_tiles = junk.hex_grid.get_all_tiles()
		for t in junk_tiles:
			if t.tile_type != "Component Link" and t.tile_type != "Core Reactor":
				inventory.append(t)
		
		# Add XP
		var xp_gain = 100 + (junk.rarity * 150)
		if active_component.has_method("add_infusion_xp"):
			active_component.add_infusion_xp(xp_gain)
			_show_warning("Infused %s! +%d XP to %s" % [junk.component_name, xp_gain, active_component.component_name])
		else:
			_show_warning("ComponentEquipment missing Infusion Logic!")
			
		_refresh_inventory_ui()
		popup.queue_free()
	)
	add_child(popup)
	popup.popup_centered(Vector2(300, 400))

func _show_warning(msg: String):
	var dialog = AcceptDialog.new()
	dialog.dialog_text = msg
	add_child(dialog)
	dialog.popup_centered()
