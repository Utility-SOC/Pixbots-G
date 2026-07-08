extends CanvasLayer

# Set by GlobalPauseHandler.gd (whichever node opened this - see its own
# comment) when the Garage was already open at the time Esc was pressed.
# The Garage keeps get_tree().paused = true the whole time it's up, so
# "Resume" here must NOT unpause - that would let gameplay run behind the
# still-open Garage screen. It should just close the Pause overlay and drop
# the player back into the Garage exactly as they left it.
var opened_from_garage: bool = false

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS # Keep running while tree is paused
	add_to_group("pause_menu") # lets GlobalPauseHandler avoid stacking a second one

	var panel = Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.modulate = Color(1, 1, 1, 0.8) # Semi-transparent background
	add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(vbox)
	
	var title = Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	vbox.add_child(title)
	
	var settings_btn = Button.new()
	settings_btn.text = "Settings"
	settings_btn.pressed.connect(_on_settings_pressed)
	vbox.add_child(settings_btn)
	
	var btn_resume = Button.new()
	btn_resume.text = "Resume"
	btn_resume.pressed.connect(_on_resume)
	vbox.add_child(btn_resume)
	
	var btn_save = Button.new()
	btn_save.text = "Save Game"
	btn_save.pressed.connect(_on_save)
	vbox.add_child(btn_save)
	
	var btn_load = Button.new()
	btn_load.text = "Load Game"
	btn_load.pressed.connect(_on_load)
	vbox.add_child(btn_load)
	
	var btn_main = Button.new()
	btn_main.text = "Main Menu"
	btn_main.pressed.connect(_on_main_menu)
	vbox.add_child(btn_main)
	
	var btn_quit = Button.new()
	btn_quit.text = "Quit to Desktop"
	btn_quit.pressed.connect(_on_quit)
	vbox.add_child(btn_quit)

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		var settings = get_node_or_null("SettingsMenu")
		if settings:
			settings.queue_free()
		else:
			_on_resume()

func _on_resume():
	if not opened_from_garage:
		get_tree().paused = false
	queue_free()

func _on_save():
	var popup = PopupPanel.new()
	var vbox = VBoxContainer.new()
	popup.add_child(vbox)
	
	var label = Label.new()
	label.text = "Enter Save Name:"
	vbox.add_child(label)
	
	var line = LineEdit.new()
	line.text = "save1"
	vbox.add_child(line)
	
	var btn = Button.new()
	btn.text = "Save"
	btn.pressed.connect(func():
		var main = get_parent()
		if main and "player" in main and main.player:
			SaveManager.save_game(line.text, main.player, main.player_inventory)
		popup.queue_free()
	)
	vbox.add_child(btn)
	
	add_child(popup)
	popup.popup_centered(Vector2(300, 150))

func _on_load():
	var popup = PopupPanel.new()
	var vbox = VBoxContainer.new()
	popup.add_child(vbox)
	
	var label = Label.new()
	label.text = "Select Save to Load:"
	vbox.add_child(label)
	
	var list = ItemList.new()
	var saves = SaveManager.get_save_files()
	for s in saves:
		list.add_item(s)
	list.custom_minimum_size = Vector2(250, 200)
	vbox.add_child(list)
	
	var btn = Button.new()
	btn.text = "Load Selected"
	btn.pressed.connect(func():
		var selected = list.get_selected_items()
		if selected.size() > 0:
			var save_name = list.get_item_text(selected[0])
			SaveManager.save_to_load = save_name
			get_tree().paused = false
			get_tree().change_scene_to_file("res://main.tscn")
	)
	vbox.add_child(btn)
	
	var cancel = Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func(): popup.queue_free())
	vbox.add_child(cancel)
	
	add_child(popup)
	popup.popup_centered(Vector2(300, 300))

func _on_settings_pressed():
	var settings = load("res://scripts/ui/SettingsMenu.gd").new()
	settings.name = "SettingsMenu"
	add_child(settings)

func _on_main_menu():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://MainMenu.tscn")

func _on_quit():
	get_tree().quit()

