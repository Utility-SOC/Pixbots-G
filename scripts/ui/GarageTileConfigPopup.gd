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
			var syn_names = EnergyPacket.SYNERGY_NAMES # canonical table
			var native_state = [int(tile.face_outputs.get(0, 0))]
			var native_btn = Button.new()
			native_btn.text = "MYTHIC native element: %s (L/R click cycles all faces)" % syn_names[native_state[0] % 10]
			native_btn.gui_input.connect(func(event):
				if event is InputEventMouseButton and event.pressed:
					if event.button_index == MOUSE_BUTTON_LEFT:
						native_state[0] = (native_state[0] + 1) % 10
					elif event.button_index == MOUSE_BUTTON_RIGHT:
						native_state[0] = (native_state[0] + 9) % 10
					else:
						return
					for f in range(6):
						tile.set_face_output(f, native_state[0])
					native_btn.text = "MYTHIC native element: %s (L/R click cycles all faces)" % syn_names[native_state[0]]
					garage._mark_player_grid_dirty()
					garage.grid_renderer.queue_redraw()
			)
			vbox.add_child(native_btn)

		garage.add_child(popup)
		popup.popup_centered(Vector2(250, 300))
		popup.popup_hide.connect(func(): popup.queue_free())

	elif tile.tile_type == "Splitter" or tile.tile_type == "Accessory Return":
		var popup = PopupPanel.new()
		var outer_vbox = VBoxContainer.new()
		popup.add_child(outer_vbox)

		var label = Label.new()
		label.text = "Configure Outputs (Max %d)" % tile.get_max_faces()
		outer_vbox.add_child(label)

		# Scrollable body (title stays fixed above it) - a Mythic Splitter's
		# ratio-tuning rows below can add up to 14+ total rows, which used to
		# silently overflow the popup's old fixed 300px height with no way
		# to reach the lower face checkboxes at all ("I cannot edit splitter
		# directions anymore" - playtest report). custom_minimum_size on the
		# inner vbox (not just the scroll viewport) is what actually forces
		# width - without it, long strings like "MYTHIC output ratios
		# (weights - shares shown live)" and "South-East: weight N (M%)"
		# were wrapping/overlapping the hex grid behind the popup even
		# after the panel itself got wider ("the window is too narrow for
		# readability" - playtest report).
		var scroll = ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(360, 340)
		outer_vbox.add_child(scroll)
		var vbox = VBoxContainer.new()
		vbox.custom_minimum_size = Vector2(360, 0)
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(vbox)

		var directions = ["East", "South-East", "South-West", "West", "North-West", "North-East"]

		for i in range(6):
			var btn = CheckButton.new()
			btn.text = "Face " + str(i) + " (" + directions[i] + ")"
			btn.button_pressed = tile.active_faces.has(i)

			btn.toggled.connect(func(pressed):
				tile.toggle_output(i)
				garage.grid_renderer.queue_redraw()
				for j in range(6):
					var child_btn = vbox.get_child(j)
					if child_btn is CheckButton:
						child_btn.set_block_signals(true)
						child_btn.button_pressed = tile.active_faces.has(j)
						child_btn.set_block_signals(false)
			)
			vbox.add_child(btn)

		# MYTHIC Splitter: ratio tuning - per-face weights replace the forced
		# equal split (weights normalize across active faces, so toggling a
		# face never needs a manual rebalance).
		if tile.tile_type == "Splitter":
			if tile.rarity < HexTile.Rarity.MYTHIC:
				var ratio_hint = Label.new()
				ratio_hint.text = "Output ratio tuning is a Mythic ability - upgrade to unlock."
				ratio_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
				vbox.add_child(ratio_hint)
			else:
				var ratio_title = Label.new()
				ratio_title.text = "MYTHIC output ratios (weights - shares shown live):"
				vbox.add_child(ratio_title)
				var ratio_labels: Array = []
				var refresh_ratios = func():
					for f in range(6):
						var lbl: Label = ratio_labels[f]
						if tile.active_faces.has(f):
							lbl.text = "%s: weight %d  (%d%%)" % [directions[f], int(tile.get_ratio_weight(f)), int(round(tile.get_ratio_percent(f)))]
							lbl.modulate = Color.WHITE
						else:
							lbl.text = "%s: (face off)" % directions[f]
							lbl.modulate = Color(0.5, 0.5, 0.5)
				for f in range(6):
					var row = HBoxContainer.new()
					var minus = Button.new()
					minus.text = "-"
					var val_lbl = Label.new()
					val_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					ratio_labels.append(val_lbl)
					var plus = Button.new()
					plus.text = "+"
					minus.pressed.connect(func():
						tile.adjust_ratio_weight(f, -1.0)
						refresh_ratios.call()
						garage._mark_player_grid_dirty()
					)
					plus.pressed.connect(func():
						tile.adjust_ratio_weight(f, 1.0)
						refresh_ratios.call()
						garage._mark_player_grid_dirty()
					)
					row.add_child(minus)
					row.add_child(val_lbl)
					row.add_child(plus)
					vbox.add_child(row)
				refresh_ratios.call()

		garage.add_child(popup)
		popup.popup_centered(Vector2(400, 420))
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

		var btn = Button.new()
		var prop_name = "secondary_synergy" if tile.tile_type == "Elemental Infuser" else "target_synergy"
		btn.text = "Synergy: %s" % EnergyPacket.element_name(tile.get(prop_name))
		btn.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.pressed:
				if event.button_index == MOUSE_BUTTON_LEFT:
					tile.cycle_synergy()
				elif event.button_index == MOUSE_BUTTON_RIGHT:
					if tile.has_method("cycle_synergy_backward"):
						tile.cycle_synergy_backward()

				btn.text = "Synergy: %s" % EnergyPacket.element_name(tile.get(prop_name))
				garage.grid_renderer.queue_redraw()
		)
		vbox.add_child(btn)

		# Catalyst gated injection (any rarity, same convention as the
		# Jammer Module's base-stat config): magnitude gate + every-Nth
		# cadence. Packets that fail a gate pass through unconverted.
		if tile.tile_type == "Catalyst":
			var mag_steps = [0.0, 25.0, 50.0, 100.0, 200.0, 400.0]
			var mag_btn = Button.new()
			var describe_mag = func() -> String:
				return "Magnitude gate: off (click to cycle)" if tile.gate_min_magnitude <= 0.0 else "Magnitude gate: >= %d (click to cycle)" % int(tile.gate_min_magnitude)
			mag_btn.text = describe_mag.call()
			mag_btn.tooltip_text = "Packets below this magnitude pass through unconverted."
			mag_btn.pressed.connect(func():
				var idx = mag_steps.find(tile.gate_min_magnitude)
				tile.gate_min_magnitude = mag_steps[(idx + 1) % mag_steps.size()] if idx >= 0 else 0.0
				mag_btn.text = describe_mag.call()
				garage._mark_player_grid_dirty()
			)
			vbox.add_child(mag_btn)

			var cadence_btn = Button.new()
			var describe_cadence = func() -> String:
				return "Cadence: every packet (click to cycle)" if tile.gate_every_n <= 1 else "Cadence: every %d packets (click to cycle)" % tile.gate_every_n
			cadence_btn.text = describe_cadence.call()
			cadence_btn.tooltip_text = "Only every Nth qualifying packet gets catalyzed - a rhythmic elemental pulse. The rest pass through unconverted."
			cadence_btn.pressed.connect(func():
				tile.gate_every_n = (tile.gate_every_n % 6) + 1
				cadence_btn.text = describe_cadence.call()
				garage._mark_player_grid_dirty()
			)
			vbox.add_child(cadence_btn)

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
		# Wide/tall enough for up to 4 rows (Synergy + magnitude gate +
		# cadence + Mythic Inverted) without wrapping/overlapping the grid
		# behind it - same fix as the Splitter popup above ("the window is
		# too narrow for readability"); the old fixed 250x100 only ever
		# fit the single Synergy button this branch originally had.
		popup.popup_centered(Vector2(340, 160) if tile.tile_type == "Catalyst" else Vector2(250, 100))
		popup.popup_hide.connect(func(): popup.queue_free())

	elif tile.tile_type == "Microcore":
		var popup = PopupPanel.new()
		var vbox = VBoxContainer.new()
		popup.add_child(vbox)

		var label = Label.new()
		label.text = "Configure Microcore Outputs (Max %d)" % tile.get_max_faces()
		vbox.add_child(label)

		var directions = ["East", "South-East", "South-West", "West", "North-West", "North-East"]

		for i in range(6):
			var hbox = HBoxContainer.new()
			var btn = CheckButton.new()
			btn.text = "Face " + str(i) + " (" + directions[i] + ")"
			btn.button_pressed = tile.active_faces.has(i)
			hbox.add_child(btn)

			var syn_btn = Button.new()
			var current_syn = tile.get_face_output(i) if tile.has_method("get_face_output") else 0
			syn_btn.text = "Syn: %s" % EnergyPacket.element_name(current_syn)
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

			# Left-click cycles forward, right-click cycles back (same
			# convention as the Catalyst/Infuser synergy button).
			syn_btn.gui_input.connect(func(event):
				if event is InputEventMouseButton and event.pressed:
					if event.button_index == MOUSE_BUTTON_LEFT and tile.has_method("cycle_face_output"):
						tile.cycle_face_output(i)
					elif event.button_index == MOUSE_BUTTON_RIGHT and tile.has_method("cycle_face_output_backward"):
						tile.cycle_face_output_backward(i)
					else:
						return
					syn_btn.text = "Syn: %s" % EnergyPacket.element_name(tile.get_face_output(i))
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

		# Auto-dump threshold (any rarity): the banked shot releases itself
		# at this fraction of full charge, payload scaled to what was
		# actually banked - automated burst-fire rhythms. Off = key only.
		var dump_lbl = Label.new()
		dump_lbl.text = "Auto-dump (fires itself at this charge):"
		vbox.add_child(dump_lbl)

		var dump_opt = OptionButton.new()
		dump_opt.add_item("Off (key fire only)")
		dump_opt.add_item("25% charge (fast, light volleys)")
		dump_opt.add_item("50% charge")
		dump_opt.add_item("75% charge")
		dump_opt.add_item("100% charge (full auto-release)")
		dump_opt.select(clampi(int(round(tile.auto_dump_threshold * 4.0)), 0, 4))
		dump_opt.item_selected.connect(func(index):
			tile.auto_dump_threshold = index * 0.25
			garage._mark_player_grid_dirty()
		)
		vbox.add_child(dump_opt)

		garage.add_child(popup)
		popup.popup_centered(Vector2(280, 160))
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
					mode_names = ["Normal", "Shotgun", "Radial Burst", "Beam", "Mortar"]
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

	elif tile.tile_type == "Jammer Module":
		# Deliberately its own branch, NOT folded into the Mythic-gated
		# block above - jam_mode/target_synergy are base stats every Jammer
		# Module has (previously only ever randomly rolled once at _init()
		# with no way to change them), not an unlocked Mythic ability, so
		# this stays available at any rarity.
		var popup = PopupPanel.new()
		var vbox = VBoxContainer.new()
		popup.add_child(vbox)

		var label = Label.new()
		label.text = "Configure Jammer Module"
		vbox.add_child(label)

		var mode_names = ["Vision", "Synergy"]
		var mode_btn = Button.new()
		mode_btn.text = "Mode: %s (click to cycle)" % mode_names[tile.jam_mode]
		mode_btn.pressed.connect(func():
			tile.cycle_jam_mode()
			mode_btn.text = "Mode: %s (click to cycle)" % mode_names[tile.jam_mode]
			garage._mark_player_grid_dirty()
		)
		vbox.add_child(mode_btn)

		var synergy_btn = Button.new()
		synergy_btn.text = "Synergy target: %s (click to cycle)" % EnergyPacket.SYNERGY_NAMES[tile.target_synergy]
		synergy_btn.tooltip_text = "Only matters in Synergy mode - mutes this element in the player's damage while jammed."
		synergy_btn.pressed.connect(func():
			tile.cycle_target_synergy()
			synergy_btn.text = "Synergy target: %s (click to cycle)" % EnergyPacket.SYNERGY_NAMES[tile.target_synergy]
			garage._mark_player_grid_dirty()
		)
		vbox.add_child(synergy_btn)

		garage.add_child(popup)
		popup.popup_centered(Vector2(300, 140))
		popup.popup_hide.connect(func(): popup.queue_free())

	elif tile.tile_type == "Resonator":
		# Per-path Sync Dropoff tuning (Status.md queue item 1) - how many
		# simulation steps each traversal path's residue survives. The sync
		# system itself is Mythic-only (see ResonatorTile._process_sync), so
		# below Mythic this just explains the lock.
		var popup = PopupPanel.new()
		var vbox = VBoxContainer.new()
		popup.add_child(vbox)

		var label = Label.new()
		label.text = "Configure Resonator Sync Dropoff"
		vbox.add_child(label)

		if tile.rarity < HexTile.Rarity.MYTHIC:
			var hint = Label.new()
			hint.text = "Resonator Sync (path residue + per-path dropoff) is a Mythic ability - upgrade this tile to unlock."
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD
			vbox.add_child(hint)
		else:
			var path_names = ["East-West", "SE-NW", "SW-NE"]
			var explain = Label.new()
			explain.text = "Steps a path's residue survives before fading (leaves procs for the OTHER two paths to pick up):"
			explain.autowrap_mode = TextServer.AUTOWRAP_WORD
			vbox.add_child(explain)
			for path_id in range(3):
				var row = HBoxContainer.new()
				var minus = Button.new()
				minus.text = "-"
				var val_lbl = Label.new()
				val_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				val_lbl.text = "%s: %d steps" % [path_names[path_id], tile.get_sync_dropoff(path_id)]
				var plus = Button.new()
				plus.text = "+"
				minus.pressed.connect(func():
					tile.adjust_sync_dropoff(path_id, -1)
					val_lbl.text = "%s: %d steps" % [path_names[path_id], tile.get_sync_dropoff(path_id)]
					garage._mark_player_grid_dirty()
				)
				plus.pressed.connect(func():
					tile.adjust_sync_dropoff(path_id, 1)
					val_lbl.text = "%s: %d steps" % [path_names[path_id], tile.get_sync_dropoff(path_id)]
					garage._mark_player_grid_dirty()
				)
				row.add_child(minus)
				row.add_child(val_lbl)
				row.add_child(plus)
				vbox.add_child(row)

		garage.add_child(popup)
		popup.popup_centered(Vector2(300, 200))
		popup.popup_hide.connect(func(): popup.queue_free())

	elif tile.tile_type == "Drone Bay":
		# Cosmetic choice, not a power spike - ungated by rarity like the
		# Jammer Module branch above. Utility-SOC: "I'd also like to be able
		# to choose drone design from the drone bay tile."
		var popup = PopupPanel.new()
		var vbox = VBoxContainer.new()
		popup.add_child(vbox)

		var label = Label.new()
		label.text = "Configure Drone Bay"
		vbox.add_child(label)

		var class_names = ["Quad-Rotor", "Hover-Orb", "Spider", "Flyer", "Recon Plane", "Chinook"]
		tile.get_or_build_loadout() # ensures visual_class is assigned, not still -1
		var class_btn = Button.new()
		class_btn.text = "Design: %s (click to cycle)" % class_names[tile.visual_class]
		class_btn.pressed.connect(func():
			tile.cycle_visual_class()
			class_btn.text = "Design: %s (click to cycle)" % class_names[tile.visual_class]
		)
		vbox.add_child(class_btn)

		var hint = Label.new()
		hint.text = "Recon Plane: much longer engagement range, loiters in a slow figure-eight. Chinook: carries a Heal Beacon, pulses heals to nearby allies."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD
		vbox.add_child(hint)

		garage.add_child(popup)
		popup.popup_centered(Vector2(320, 160))
		popup.popup_hide.connect(func(): popup.queue_free())
