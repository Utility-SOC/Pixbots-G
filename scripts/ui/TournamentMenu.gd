extends Control

func _ready():
	_setup_ui()

func _setup_ui():
	# Background
	var bg = ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.15, 0.95)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	var title = Label.new()
	title.text = "SELECT SAVE FOR TOURNAMENT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)

	var saves = SaveManager.get_save_files()
	if saves.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "No saves found."
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(empty_lbl)
	else:
		for s in saves:
			var save_data = SaveManager.load_game(s)
			var max_wave = save_data.get("max_wave_reached", 1)
			# SaveManager.load_game() restores onto the singleton itself (see
			# its own comments) - same pattern BossRushMenu.gd already relies
			# on for max_wave_reached, snapshotted here before the next save
			# in this loop overwrites it.
			var locked_out = SaveManager.tournament_locked_out
			var champs_beaten = SaveManager.defeated_champion_names()

			var btn = Button.new()
			btn.custom_minimum_size = Vector2(440, 50)

			if max_wave >= 100 and not locked_out:
				var champ_note = ""
				if champs_beaten.size() > 0:
					champ_note = " - Champions: " + str(champs_beaten.size()) + "/4"
				btn.text = s + " (Wave " + str(max_wave) + ")" + champ_note
				btn.pressed.connect(func(): _launch_tournament(s))
			elif locked_out:
				btn.text = s + " (Wave " + str(max_wave) + ") - REGISTRATION PULLED (win a Rival match to restore)"
				btn.disabled = true
			else:
				btn.text = s + " (Wave " + str(max_wave) + ") - LOCKED (Reach Wave 100)"
				btn.disabled = true

			vbox.add_child(btn)

	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(spacer2)

	var back_btn = Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(200, 40)
	back_btn.pressed.connect(func(): queue_free())
	vbox.add_child(back_btn)

func _launch_tournament(save_name: String):
	print("Launching Tournament with save: ", save_name)
	SaveManager.save_to_load = save_name
	SaveManager.current_game_mode = "tournament"
	get_tree().change_scene_to_file("res://main.tscn")
