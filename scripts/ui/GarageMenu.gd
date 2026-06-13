class_name GarageMenu
extends CanvasLayer

const HexTile = preload("res://scripts/core/HexTile.gd")
const EnergyPacket = preload("res://scripts/core/EnergyPacket.gd")
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
	if get_parent() and "player" in get_parent() and get_parent().player:
		mech_components = get_parent().player.components
			
		if "player_inventory" in get_parent():
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
		var h0 = grid_renderer.HexCoord.new(0, 0)
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
	
	component_tabs = TabBar.new()
	component_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	component_tabs.tab_changed.connect(_on_tab_changed)
	top_bar.add_child(component_tabs)
	
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
	
	if get_parent() and "player" in get_parent() and get_parent().player:
		sep_fire_toggle.button_pressed = get_parent().player.separate_arm_firing
	else:
		sep_fire_toggle.button_pressed = true
		
	sep_fire_toggle.toggled.connect(func(pressed):
		if get_parent() and "player" in get_parent() and get_parent().player:
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
		if main and "player" in main and main.player:
			SaveManager.save_game("autosave", main.player, inventory)
		if main and main.has_method("_close_garage"):
			main._close_garage()
	)
	bottom_bar.add_child(deploy_button)
	
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
	inv_label.text = "INVENTORY"
	inv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_vbox.add_child(inv_label)
	
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
		var rarity_name = ["Common", "Uncommon", "Rare", "Legendary"][tile.rarity]
		var rarity_colors = [Color(0.5, 0.5, 0.5), Color(0.2, 0.7, 0.3), Color(0.2, 0.4, 0.8), Color(0.8, 0.5, 0.1)]
		
		var style = StyleBoxFlat.new()
		style.bg_color = rarity_colors[tile.rarity] * 0.5 # Darkened background
		style.border_width_bottom = 2
		style.border_color = rarity_colors[tile.rarity]
		btn.add_theme_stylebox_override("normal", style)
		
		btn.text = tile.tile_type + "\n" + rarity_name + " (x" + str(snapped(mult, 0.01)) + ")"
		btn.custom_minimum_size = Vector2(0, 50)
		btn.button_down.connect(_on_inventory_item_down.bind(tile))
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

func _on_inventory_item_down(tile: HexTile):
	dragged_tile = tile
	drag_preview.show()
	drag_preview.global_position = get_viewport().get_mouse_position()
	tooltip_label.hide()

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
	var rarity_name = ["Common", "Uncommon", "Rare", "Legendary"][tile.rarity]
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
		
	elif tile.tile_type == "Splitter":
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
	
	elif tile.tile_type == "Elemental Infuser":
		var popup = PopupPanel.new()
		var vbox = VBoxContainer.new()
		popup.add_child(vbox)
		
		var label = Label.new()
		label.text = "Configure Infuser Synergy"
		vbox.add_child(label)
		
		var synergies = ["RAW", "KINETIC", "FIRE", "POISON", "LIGHTNING", "VAMPIRIC", "VORTEX"]
		var btn = Button.new()
		var current_name = synergies[tile.secondary_synergy] if tile.secondary_synergy < synergies.size() else "UNKNOWN"
		btn.text = "Synergy: %s" % current_name
		btn.pressed.connect(func():
			tile.cycle_synergy()
			var new_name = synergies[tile.secondary_synergy] if tile.secondary_synergy < synergies.size() else "UNKNOWN"
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
		var synergies = ["RAW", "KINETIC", "FIRE", "POISON", "LIGHTNING", "VAMPIRIC", "VORTEX"]
		
		for i in range(6):
			var hbox = HBoxContainer.new()
			var btn = CheckButton.new()
			btn.text = "Face " + str(i) + " (" + directions[i] + ")"
			btn.button_pressed = tile.active_faces.has(i)
			hbox.add_child(btn)
			
			var syn_btn = Button.new()
			var current_syn = tile.get_face_output(i) if tile.has_method("get_face_output") else 0
			var syn_name = synergies[current_syn] if current_syn < synergies.size() else "RAW"
			syn_btn.text = "Syn: %s" % syn_name
			syn_btn.disabled = not btn.button_pressed or tile.rarity < load("res://scripts/core/HexTile.gd").Rarity.UNCOMMON
			hbox.add_child(syn_btn)
			
			btn.toggled.connect(func(pressed):
				tile.toggle_face(i)
				syn_btn.disabled = not pressed or tile.rarity < load("res://scripts/core/HexTile.gd").Rarity.UNCOMMON
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
					var new_name = synergies[new_syn] if new_syn < synergies.size() else "RAW"
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

		
		if active_component.slot_type == HexTile.BodySlot.TORSO:
			var core = grid_renderer.hex_grid.get_tile(grid_renderer.HexCoord.new(0, 0))
			if core and core.has_method("generate_energy"):
				initial_packets = core.generate_energy(grid_renderer.hex_grid)
				for p in initial_packets:
					p.position = HexCoord.new(0, 0)
			else:
				var packet = EnergyPacket.new()
				packet.magnitude = 100.0
				packet.position = grid_renderer.HexCoord.new(0, 0)
				packet.direction = 0
				initial_packets.append(packet)
		else:
			var packet = EnergyPacket.new()
			packet.magnitude = 100.0
			packet.position = grid_renderer.HexCoord.new(0, 0)
			if active_component.slot_type == HexTile.BodySlot.ARM_L:
				packet.direction = 3
				packet.position = grid_renderer.HexCoord.new(0, 0).neighbor(0)
			elif active_component.slot_type == HexTile.BodySlot.ARM_R:
				packet.direction = 0
				packet.position = grid_renderer.HexCoord.new(0, 0).neighbor(3)
			initial_packets.append(packet)
			
	for p in initial_packets:
		p.set_meta("source_hex", p.position)
		p.set_meta("target_hex", p.position)
		p.set_meta("anim_progress", 1.0)
	
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
			# Bounce off empty space
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
	
	stats_label.text = "=== COMPONENT INFO ===\nGrid: Mech Core\nTiles Used: %d\n\n=== SIMULATION ===\nStep: %d\nActive Packets: %d\nTotal Energy: %d" % [
		grid_size,
		grid_renderer.simulation_step,
		grid_renderer.active_packets.size(),
		int(total_nrg)
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
