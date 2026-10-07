class_name SettingsMenu
extends CanvasLayer

var config = ConfigFile.new()
# user:// - res:// is read-only in exported builds, so settings written
# there silently failed to persist for players. SaveManager._ready()
# migrates any legacy res://settings.cfg forward on first boot.
var save_path = SaveManager.SETTINGS_PATH

var slider_master: HSlider
var slider_music: HSlider
var slider_sfx: HSlider
var opt_controls: OptionButton
var edit_pilot_name: LineEdit
var opt_render_mode: OptionButton
var check_batch_combat: CheckButton

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
	
	# CenterContainer: a bare PRESET_CENTER anchor puts the panel's top-left at
	# screen center, pushing it (and its Close button) off-screen.
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.add_child(center)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(400, 300)
	center.add_child(panel)
	
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

	# VISUALS TAB (user request, 2026-08-11: "I would like these things
	# (including enabling pie charts and stuff) in the main menu under a[n]
	# ... settings menu" - the experimental batch-pool render mode's one
	# real home outside the Test Range). Shares its value with
	# GarageTestRange.gd's own selector via SaveManager.batch_render_mode
	# (same settings.cfg) - changing it here changes what the Test Range
	# shows and vice versa, there's only one underlying setting.
	var visuals_tab = VBoxContainer.new()
	visuals_tab.name = "Visuals"
	tab_container.add_child(visuals_tab)

	var size_label = Label.new()
	size_label.text = "Projectile Size vs. Power"
	visuals_tab.add_child(size_label)
	var size_hint = Label.new()
	size_hint.text = "Late-game shots can grow huge. Auto tightens the size cap on harder difficulties; Compact keeps shots small and shows power as glow and a ring. Applies to newly fired shots."
	size_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	size_hint.modulate = Color(0.7, 0.7, 0.7)
	visuals_tab.add_child(size_hint)
	var opt_size = OptionButton.new()
	for n in SaveManager.PROJECTILE_SIZE_MODE_NAMES:
		opt_size.add_item(n)
	opt_size.selected = SaveManager.projectile_size_mode
	opt_size.item_selected.connect(func(index): SaveManager.set_projectile_size_mode(index))
	visuals_tab.add_child(opt_size)

	var limb_label = Label.new()
	limb_label.text = "Destroyed Limbs"
	visuals_tab.add_child(limb_label)
	var opt_limb = OptionButton.new()
	for n in SaveManager.BROKEN_LIMB_STYLE_NAMES:
		opt_limb.add_item(n)
	opt_limb.selected = SaveManager.broken_limb_style
	opt_limb.item_selected.connect(func(index): SaveManager.set_broken_limb_style(index))
	visuals_tab.add_child(opt_limb)

	var render_mode_label = Label.new()
	render_mode_label.text = "Projectile Render Mode"
	visuals_tab.add_child(render_mode_label)

	var render_mode_hint = Label.new()
	render_mode_hint.text = "Only affects the experimental Batch Renderer in the Garage Test Range for now - not live combat."
	render_mode_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	render_mode_hint.modulate = Color(0.7, 0.7, 0.7)
	visuals_tab.add_child(render_mode_hint)

	opt_render_mode = OptionButton.new()
	opt_render_mode.add_item("Flat (Default)")
	opt_render_mode.add_item("Pie Chart")
	opt_render_mode.add_item("Shape Blend")
	opt_render_mode.add_item("Starburst")
	opt_render_mode.add_item("Rings")
	opt_render_mode.selected = SaveManager.batch_render_mode
	opt_render_mode.item_selected.connect(func(index): SaveManager.set_batch_render_mode(index))
	visuals_tab.add_child(opt_render_mode)

	# Live-combat cutover (2026-08-11: "switch to batch for main gameplay,
	# but be able to enable the legacy system"). Default ON since 2026-10-05.
	var batch_combat_hint = Label.new()
	batch_combat_hint.text = "Fast projectile renderer for real combat (default). Turn off to use the legacy per-shot renderer, which is slower with many mixed elements."
	batch_combat_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	batch_combat_hint.modulate = Color(0.7, 0.7, 0.7)
	visuals_tab.add_child(batch_combat_hint)

	check_batch_combat = CheckButton.new()
	check_batch_combat.text = "Use Batch Renderer in Combat"
	check_batch_combat.button_pressed = SaveManager.batch_renderer_in_combat
	check_batch_combat.toggled.connect(func(pressed): SaveManager.set_batch_renderer_in_combat(pressed))
	visuals_tab.add_child(check_batch_combat)

	# Fullscreen (borderless). Also bound to F11 / Alt+Enter anywhere in the game.
	var fullscreen_hint = Label.new()
	fullscreen_hint.text = "Borderless fullscreen for extra screen space. Also toggled anywhere with F11 or Alt+Enter."
	fullscreen_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	fullscreen_hint.modulate = Color(0.7, 0.7, 0.7)
	visuals_tab.add_child(fullscreen_hint)

	var check_fullscreen = CheckButton.new()
	check_fullscreen.text = "Fullscreen (F11)"
	check_fullscreen.button_pressed = SaveManager.fullscreen
	check_fullscreen.toggled.connect(func(pressed): SaveManager.set_fullscreen(pressed))
	# Keep the checkbox honest when F11 flips it while this menu is open.
	SaveManager.fullscreen_changed.connect(check_fullscreen.set_pressed_no_signal) # method Callable: auto-disconnects when freed
	visuals_tab.add_child(check_fullscreen)

	# Systems status graph (bottom-right schematic of weapons, actuators, jumpjets, links). F10 toggles it too.
	var graph_hint = Label.new()
	graph_hint.text = "Small green schematic in the bottom-right showing which of your weapons, actuators, jumpjets and links are working. Also toggled with F10."
	graph_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	graph_hint.modulate = Color(0.7, 0.7, 0.7)
	visuals_tab.add_child(graph_hint)

	var check_graph = CheckButton.new()
	check_graph.text = "Show systems status graph (F10)"
	check_graph.button_pressed = SaveManager.show_status_graph
	check_graph.toggled.connect(func(pressed): SaveManager.set_status_graph(pressed))
	SaveManager.status_graph_changed.connect(check_graph.set_pressed_no_signal) # method Callable: auto-disconnects when freed
	visuals_tab.add_child(check_graph)

	# PROFILE TAB
	var profile_tab = VBoxContainer.new()
	profile_tab.name = "Profile"
	tab_container.add_child(profile_tab)

	var pilot_label = Label.new()
	pilot_label.text = "Pilot Name"
	profile_tab.add_child(pilot_label)

	var pilot_hint = Label.new()
	pilot_hint.text = "Used to attribute AI profiles you share via the War Room's export/import - shown there, not advertised elsewhere."
	pilot_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	pilot_hint.modulate = Color(0.7, 0.7, 0.7)
	profile_tab.add_child(pilot_hint)

	edit_pilot_name = LineEdit.new()
	edit_pilot_name.max_length = 24
	edit_pilot_name.text_submitted.connect(func(_t): SaveManager.set_pilot_name(edit_pilot_name.text))
	edit_pilot_name.focus_exited.connect(func(): SaveManager.set_pilot_name(edit_pilot_name.text))
	profile_tab.add_child(edit_pilot_name)

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
	if edit_pilot_name:
		edit_pilot_name.text = SaveManager.pilot_name

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
