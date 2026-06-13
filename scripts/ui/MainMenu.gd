extends Control

func _ready():
	_apply_controls_from_settings()
	_setup_ui()

func _apply_controls_from_settings():
	var config = ConfigFile.new()
	var scheme = 0 # 0 = WASD
	if config.load("res://settings.cfg") == OK:
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
	
	# Continue Game
	var saves = SaveManager.get_save_files()
	if saves.size() > 0:
		# Just load the most recently modified or simply "autosave" if we have it
		var continue_save = saves[saves.size() - 1]
		if saves.has("autosave"):
			continue_save = "autosave"
			
		var btn_continue = _create_button("Continue (" + continue_save + ")", func():
			SaveManager.save_to_load = continue_save
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
	
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer2)
	
	# Tools & Options
	# Tools & Options
	var btn_import_ai = _create_button("Import AI Templates", _on_import_ai)
	var btn_import_mods = _create_button("Import Mods", _on_import_mods)
	var btn_settings = _create_button("Settings", _on_settings_pressed)
	var btn_quit = _create_button("Quit", _on_quit_pressed)
	
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
	_launch_game("campaign")

func _on_play_endless():
	print("Starting Endless Mode...")
	_launch_game("endless")
	
func _on_play_sandbox():
	print("Starting Sandbox Mode...")
	_launch_game("sandbox")

func _launch_game(mode: String):
	get_tree().change_scene_to_file("res://main.tscn")

func _on_import_ai():
	print("Opening AI Import Menu... (Mock)")
	
func _on_import_mods():
	print("Opening Mod Import Menu... (Mock)")

func _on_settings_pressed():
	var settings = load("res://scripts/ui/SettingsMenu.gd").new()
	add_child(settings)

func _on_quit_pressed():
	get_tree().quit()
