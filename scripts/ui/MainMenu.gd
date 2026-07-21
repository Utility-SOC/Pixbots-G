extends Control

func _ready():
	_apply_controls_from_settings()
	_setup_ui()

func _apply_controls_from_settings():
	var config = ConfigFile.new()
	var scheme = 0 # 0 = WASD
	# user:// via SaveManager.SETTINGS_PATH - res:// is read-only in
	# exported builds (SaveManager._ready migrates old res:// settings).
	if config.load(SaveManager.SETTINGS_PATH) == OK:
		scheme = config.get_value("Controls", "Scheme", 0)
		
	var mapping = {
		"ui_up": [KEY_W, KEY_UP],
		"ui_down": [KEY_S, KEY_DOWN],
		"ui_left": [KEY_A, KEY_LEFT],
		"ui_right": [KEY_D, KEY_RIGHT]
	}
	
	for action in mapping:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
			var event = InputEventKey.new()
			event.physical_keycode = mapping[action][scheme]
			InputMap.action_add_event(action, event)

func _setup_ui():
	# Background
	var bg = ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.15)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)
	
	# Main Container
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	
	var vbox = VBoxContainer.new()
	center.add_child(vbox)
	
	# Title
	var title = Label.new()
	title.text = "PIXEL BOTS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	vbox.add_child(title)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(spacer)

	# Difficulty picker - persists via SaveManager/settings.cfg. The top
	# option keeps enemies near-peer with your build power, always.
	var diff_row = HBoxContainer.new()
	diff_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(diff_row)

	var diff_lbl = Label.new()
	diff_lbl.text = "Difficulty:  "
	diff_row.add_child(diff_lbl)

	var diff_opt = OptionButton.new()
	for name_idx in range(SaveManager.DIFFICULTY_NAMES.size()):
		diff_opt.add_item(SaveManager.DIFFICULTY_NAMES[name_idx], name_idx)
	diff_opt.selected = SaveManager.difficulty
	diff_opt.item_selected.connect(func(idx):
		SaveManager.set_difficulty(idx)
	)
	diff_row.add_child(diff_opt)

	var spacer_diff = Control.new()
	spacer_diff.custom_minimum_size = Vector2(0, 14)
	vbox.add_child(spacer_diff)

	# Continue Game
	var saves = SaveManager.get_save_files()
	if saves.size() > 0:
		# Resume from whichever save made it FURTHEST (the user: "pick up
		# from the highest level I've made it to"), not just whichever
		# happened to be named "autosave" or sorted last in the directory
		# listing - neither of those reflects actual progress.
		var continue_save = saves[0]
		var best_wave = -1
		for s in saves:
			var w = SaveManager.peek_max_wave(s)
			if w > best_wave:
				best_wave = w
				continue_save = s

		var btn_continue = _create_button("Continue (" + continue_save + " - Wave " + str(best_wave) + ")", func():
			SaveManager.save_to_load = continue_save
			SaveManager.current_game_mode = "campaign"
			_launch_game("campaign")
		)
		btn_continue.modulate = Color(0.8, 1.0, 0.8)
		vbox.add_child(btn_continue)
		
		var spacer1_5 = Control.new()
		spacer1_5.custom_minimum_size = Vector2(0, 10)
		vbox.add_child(spacer1_5)
	
	# Play Modes
	var btn_campaign = _create_button("New Campaign", _on_play_campaign)
	var btn_endless = _create_button("Endless", _on_play_endless)
	var btn_sandbox = _create_button("Sandbox", _on_play_sandbox)

	vbox.add_child(btn_campaign)
	vbox.add_child(btn_endless)
	vbox.add_child(btn_sandbox)

	var btn_boss_rush = _create_button("Boss Rush", _on_play_boss_rush)
	vbox.add_child(btn_boss_rush)

	# Tournament arc - scaffold only (the user, design pass decision #12).
	# Nothing actually sets tournament_arc_unlocked true yet - the real
	# unlock condition is the Level 100 milestone, and that milestone/Round
	# system doesn't exist yet either. This button just reads the flag so
	# unlocking it later is a one-line flip in SaveManager, not new UI work.
	# _on_play_tournament() is a stub for the same reason - the launch target
	# doesn't exist yet, but the wiring does.
	var btn_tournament = _create_button("Tournament", _on_play_tournament)
	btn_tournament.disabled = not SaveManager.tournament_arc_unlocked
	if not SaveManager.tournament_arc_unlocked:
		btn_tournament.text = "Tournament (Locked)"
		btn_tournament.modulate = Color(0.6, 0.6, 0.6)
		btn_tournament.tooltip_text = DialogueManager.get_tournament_teaser()
	vbox.add_child(btn_tournament)

	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer2)
	
	# Tools & Options
	# Tools & Options
	var btn_war_room = _create_button("War Room", _on_war_room_pressed)
	var btn_import_ai = _create_button("Import AI Templates", _on_import_ai)
	var btn_import_mods = _create_button("Import Mods", _on_import_mods)
	var btn_settings = _create_button("Settings", _on_settings_pressed)
	var btn_quit = _create_button("Quit", _on_quit_pressed)

	vbox.add_child(btn_war_room)
	vbox.add_child(btn_import_ai)
	vbox.add_child(btn_import_mods)
	vbox.add_child(btn_settings)
	vbox.add_child(btn_quit)

func _create_button(text: String, callable: Callable) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(250, 40)
	btn.pressed.connect(callable)
	return btn

func _on_play_campaign():
	print("Starting Campaign Mode...")
	SaveManager.save_to_load = "" # Clear load state for new game
	SaveManager.tutorial_completed = false # New save should see the tutorial again
	SaveManager.tournament_arc_unlocked = false # New save starts locked out too
	SaveManager.current_game_mode = "campaign"
	_launch_game("campaign")

func _on_play_endless():
	print("Starting Endless Mode...")
	SaveManager.current_game_mode = "endless"
	_launch_game("endless")
	
func _on_play_sandbox():
	print("Starting Sandbox Mode...")
	SaveManager.current_game_mode = "sandbox"
	_launch_game("sandbox")

func _on_play_boss_rush():
	print("Opening Boss Rush Menu...")
	var boss_rush = load("res://scripts/ui/BossRushMenu.gd").new()
	add_child(boss_rush)

func _on_play_tournament():
	print("Tournament mode not implemented yet.")
	pass

func _launch_game(mode: String):
	get_tree().change_scene_to_file("res://main.tscn")

func _on_war_room_pressed():
	# Reuse a single instance across repeat presses (toggling it back open
	# rather than stacking up hidden duplicates) - see WarRoomMenu._toggle,
	# same instance/toggle pattern the in-game TAB shortcut uses.
	var existing = get_node_or_null("WarRoomInstance")
	if existing:
		existing._toggle()
		return
	var wr = load("res://scripts/ui/WarRoomMenu.gd").new()
	wr.name = "WarRoomInstance"
	add_child(wr)
	wr._toggle() # starts closed by default - open it immediately

func _on_import_ai():
	print("Opening AI Import Menu... (Mock)")
	
func _on_import_mods():
	print("Opening Mod Import Menu... (Mock)")

func _on_settings_pressed():
	var settings = load("res://scripts/ui/SettingsMenu.gd").new()
	add_child(settings)

func _on_quit_pressed():
	get_tree().quit()
