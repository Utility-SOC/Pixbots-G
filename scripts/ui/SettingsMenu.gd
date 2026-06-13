class_name SettingsMenu
extends CanvasLayer

var config = ConfigFile.new()
var save_path = "res://settings.cfg"

var slider_master: HSlider
var slider_music: HSlider
var slider_sfx: HSlider
var opt_controls: OptionButton

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 150 # Above everything including debug menu
	
	_setup_ui()
	_load_settings()

func _setup_ui():
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.8)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(400, 300)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	bg.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var tab_container = TabContainer.new()
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(tab_container)
	
	# AUDIO TAB
	var audio_tab = VBoxContainer.new()
	audio_tab.name = "Audio"
	tab_container.add_child(audio_tab)
	
	slider_master = _add_volume_slider(audio_tab, "Master Volume", "Master")
	slider_music = _add_volume_slider(audio_tab, "Music Volume", "Music")
	slider_sfx = _add_volume_slider(audio_tab, "SFX Volume", "SFX")
	
	# CONTROLS TAB
	var controls_tab = VBoxContainer.new()
	controls_tab.name = "Controls"
	tab_container.add_child(controls_tab)
	
	var control_label = Label.new()
	control_label.text = "Movement Keys"
	controls_tab.add_child(control_label)
	
	opt_controls = OptionButton.new()
	opt_controls.add_item("WASD")
	opt_controls.add_item("Arrow Keys")
	opt_controls.item_selected.connect(_on_controls_changed)
	controls_tab.add_child(opt_controls)
	
	# CLOSE BUTTON
	var btn_close = Button.new()
	btn_close.text = "Save & Close"
	btn_close.pressed.connect(_on_close)
	vbox.add_child(btn_close)

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_close()

func _add_volume_slider(parent: Control, label_text: String, bus_name: String) -> HSlider:
	var label = Label.new()
	label.text = label_text
	parent.add_child(label)
	
	var slider = HSlider.new()
	slider.min_value = -40
	slider.max_value = 6
	slider.step = 1
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		slider.value = AudioServer.get_bus_volume_db(bus_idx)
		if AudioServer.is_bus_mute(bus_idx):
			slider.value = slider.min_value
	
	slider.value_changed.connect(_on_volume_changed.bind(bus_name))
	parent.add_child(slider)
	return slider

func _on_volume_changed(value: float, bus_name: String):
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		if value <= -40:
			AudioServer.set_bus_mute(bus_idx, true)
		else:
			AudioServer.set_bus_mute(bus_idx, false)
			AudioServer.set_bus_volume_db(bus_idx, value)

func _on_controls_changed(index: int):
	# 0 = WASD, 1 = Arrows
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
			event.physical_keycode = mapping[action][index]
			InputMap.action_add_event(action, event)

func _load_settings():
	if config.load(save_path) == OK:
		var master_vol = config.get_value("Audio", "Master", 0.0)
		var music_vol = config.get_value("Audio", "Music", 0.0)
		var sfx_vol = config.get_value("Audio", "SFX", 0.0)
		
		_on_volume_changed(master_vol, "Master")
		_on_volume_changed(music_vol, "Music")
		_on_volume_changed(sfx_vol, "SFX")
		
		if slider_master: slider_master.value = master_vol
		if slider_music: slider_music.value = music_vol
		if slider_sfx: slider_sfx.value = sfx_vol
		
		var control_scheme = config.get_value("Controls", "Scheme", 0) # 0 = WASD
		opt_controls.select(control_scheme)
		_on_controls_changed(control_scheme)
	else:
		# Defaults
		_on_controls_changed(0) # WASD default

func _save_settings():
	config.set_value("Audio", "Master", slider_master.value)
	config.set_value("Audio", "Music", slider_music.value)
	config.set_value("Audio", "SFX", slider_sfx.value)
	config.set_value("Controls", "Scheme", opt_controls.selected)
	config.save(save_path)

func _on_close():
	_save_settings()
	queue_free()
