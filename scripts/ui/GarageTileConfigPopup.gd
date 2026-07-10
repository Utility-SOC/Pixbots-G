class_name GarageTileConfigPopup
extends RefCounted

# Per-tile-type "click a placed tile to configure it" popups (face toggles,
# synergy cycling, Mythic mode pickers, etc.) - split out of GarageMenu.gd,
# see SightAndSearch.gd/MagnetSystem.gd for the established composed-
# RefCounted-helper pattern this follows. Entirely self-contained: every
# branch only reads the clicked tile (a parameter) and calls back into
# GarageMenu for add_child/grid_renderer/_mark_player_grid_dirty.
#
# Keeps a thin wrapper on GarageMenu (not moved) - it's connected directly
# as a Callable via grid_renderer.tile_clicked.connect(_on_tile_clicked) in
# _setup_ui, so it has to be reachable as a plain GarageMenu-level method
# regardless.

var garage: GarageMenu

func _init(p_garage: GarageMenu):
	garage = p_garage

func on_tile_clicked(tile: HexTile):
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
				garage.grid_renderer.queue_redraw()
				for j in range(6):
					var child_btn = vbox.get_child(j + 1)
					if child_btn is CheckButton:
						child_btn.set_block_signals(true)
						child_btn.button_pressed = tile.active_faces.has(j)
						child_btn.set_block_signals(false)
			)
			vbox.add_child(btn)

		# MYTHIC Core: shift native generation to a single element on every
		# face at once, bypassing the need for early Catalysts.
		if tile.rarity == HexTile.Rarity.MYTHIC:
			var syn_names = ["RAW", "FIRE", "ICE", "LIGHTNING", "VORTEX", "POISON", "EXPLOSION", "KINETIC", "PIERCE", "VAMPIRIC"]
			var native_state = [int(tile.face_outputs.get(0, 0))]
			var native_btn = Button.new()
			native_btn.text = "MYTHIC native element: %s (click to cycle all faces)" % syn_names[native_state[0] % 10]
			native_btn.pressed.connect(func():
				native_state[0] = (native_state[0] + 1) % 10
				for f in range(6):
					tile.set_face_output(f, native_state[0])
				native_btn.text = "MYTHIC native element: %s (click to cycle all faces)" % syn_names[native_state[0]]
				garage._mark_player_grid_dirty()
				garage.grid_renderer.queue_redraw()
			)
			vbox.add_child(native_btn)

		garage.add_child(popup)
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
				garage.grid_renderer.queue_redraw()
				for j in range(6):
					var child_btn = vbox.get_child(j + 1)
					if child_btn is CheckButton:
						child_btn.set_block_signals(true)
						child_btn.button_pressed = tile.active_faces.has(j)
						child_btn.set_block_signals(false)
			)
			vbox.add_child(btn)

		garage.add_child(popup)
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
			garage.grid_renderer.queue_redraw()
		)
		vbox.add_child(btn)

		garage.add_child(popup)
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
				garage.grid_renderer.queue_redraw()
		)
		vbox.add_child(btn)

		# MYTHIC Catalyst: Inverted mode - a purity filter instead of a
		# converter (voids everything except the chosen element).
		if tile.tile_type == "Catalyst" and tile.rarity == HexTile.Rarity.MYTHIC:
			var inv_btn = CheckButton.new()
			inv_btn.text = "MYTHIC: Inverted (void all but chosen element)"
			inv_btn.button_pressed = tile.get("inverted") == true
			inv_btn.toggled.connect(func(on):
				tile.inverted = on
				garage._mark_player_grid_dirty()
				garage.grid_renderer.queue_redraw()
			)
			vbox.add_child(inv_btn)

		garage.add_child(popup)
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
				garage.grid_renderer.queue_redraw()
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

		garage.add_child(popup)
		popup.popup_centered(Vector2(400, 300))
		popup.popup_hide.connect(func(): popup.queue_free())

	elif tile.tile_type == "Accumulator":
		var popup = PopupPanel.new()
		var vbox = VBoxContainer.new()
		popup.add_child(vbox)

		var label = Label.new()
		label.text = "Configure Accumulator Trigger Key"
		vbox.add_child(label)

		var opt = OptionButton.new()
		opt.add_item("None")
		opt.add_item("Key 1")
		opt.add_item("Key 2")
		opt.add_item("Key 3")

		var current = 0
		if tile.trigger_key == "1": current = 1
		elif tile.trigger_key == "2": current = 2
		elif tile.trigger_key == "3": current = 3
		opt.select(current)

		opt.item_selected.connect(func(index):
			if index == 0: tile.trigger_key = "None"
			elif index == 1: tile.trigger_key = "1"
			elif index == 2: tile.trigger_key = "2"
			elif index == 3: tile.trigger_key = "3"
			garage.grid_renderer.queue_redraw()
		)
		vbox.add_child(opt)

		garage.add_child(popup)
		popup.popup_centered(Vector2(250, 100))
		popup.popup_hide.connect(func(): popup.queue_free())

	elif tile.tile_type == "Magnet":
		var popup = PopupPanel.new()
		var vbox = VBoxContainer.new()
		popup.add_child(vbox)

		var label = Label.new()
		label.text = "Configure Magnet"
		vbox.add_child(label)

		var rarity_names = ["Common", "Uncommon", "Rare", "Legendary", "Mythic"]
		var btn = Button.new()

		var describe_filter = func() -> String:
			if tile.rarity < HexTile.Rarity.MYTHIC:
				return "Rarity filter is a Mythic-only ability"
			elif tile.min_attract_rarity < 0:
				return "Attracts: Any Rarity (click to change)"
			else:
				return "Attracts: %s or above (click to change)" % rarity_names[tile.min_attract_rarity]

		btn.text = describe_filter.call()
		btn.disabled = tile.rarity < HexTile.Rarity.MYTHIC
		btn.pressed.connect(func():
			tile.cycle_min_attract_rarity()
			btn.text = describe_filter.call()
		)
		vbox.add_child(btn)

		if tile.rarity < HexTile.Rarity.MYTHIC:
			var hint = Label.new()
			hint.text = "Upgrade this Magnet to Mythic to filter what it attracts."
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD
			vbox.add_child(hint)
		else:
			# MYTHIC Magnet: Attract/Repel field flip (joins the rarity
			# filter above - Mythic gets BOTH, per design ruling).
			var repel_btn = CheckButton.new()
			repel_btn.text = "MYTHIC: Repel mode (reflect enemy shots back at them)"
			repel_btn.button_pressed = tile.get("repel_mode") == true
			repel_btn.toggled.connect(func(_on):
				tile.toggle_repel_mode()
				garage._mark_player_grid_dirty()
			)
			vbox.add_child(repel_btn)

		garage.add_child(popup)
		popup.popup_centered(Vector2(280, 120))
		popup.popup_hide.connect(func(): popup.queue_free())

	elif tile.tile_type == "Weapon Mount" or tile.tile_type == "Jumpjet" or tile.tile_type == "Amplifier" or tile.tile_type == "Directional Conduit" or tile.tile_type == "Shield Generator" or tile.tile_type == "Actuator":
		# Mythic-ability popup for tiles that had no click config before.
		var popup = PopupPanel.new()
		var vbox = VBoxContainer.new()
		popup.add_child(vbox)

		var label = Label.new()
		label.text = "Configure " + tile.tile_type
		vbox.add_child(label)

		if tile.rarity < HexTile.Rarity.MYTHIC:
			var hint = Label.new()
			hint.text = "Mythic ability locked - upgrade this tile to Mythic."
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD
			vbox.add_child(hint)
		else:
			var mode_names: Array = []
			var prop = ""
			var cycle_method = ""
			match tile.tile_type:
				"Weapon Mount":
					mode_names = ["Normal", "Shotgun", "Radial Burst", "Beam"]
					prop = "mythic_pattern"
					cycle_method = "cycle_mythic_pattern"
				"Jumpjet":
					mode_names = ["Jump", "Blink"]
					prop = "mythic_mode"
					cycle_method = "cycle_mythic_mode"
				"Amplifier":
					mode_names = ["Balanced", "Pure Damage", "AoE Focus"]
					prop = "mythic_focus"
					cycle_method = "cycle_mythic_focus"
				"Directional Conduit":
					mode_names = ["Two-Way", "One-Way Valve"]
					prop = "mythic_mode"
					cycle_method = "cycle_mythic_mode"
				"Shield Generator":
					mode_names = ["Aegis (tank)", "Deflector (overflow eject)"]
					prop = "mythic_mode"
					cycle_method = "cycle_mythic_mode"
				"Actuator":
					mode_names = ["Velocity", "Ember", "Balanced"]
					prop = "mythic_mode"
					cycle_method = "cycle_mythic_mode"

			var mode_btn = Button.new()
			mode_btn.text = "MYTHIC mode: %s (click to cycle)" % mode_names[int(tile.get(prop)) % mode_names.size()]
			mode_btn.pressed.connect(func():
				tile.call(cycle_method)
				mode_btn.text = "MYTHIC mode: %s (click to cycle)" % mode_names[int(tile.get(prop)) % mode_names.size()]
				garage._mark_player_grid_dirty()
			)
			vbox.add_child(mode_btn)

		garage.add_child(popup)
		popup.popup_centered(Vector2(300, 120))
		popup.popup_hide.connect(func(): popup.queue_free())
