extends Control

# Frank's Challenges picker (main menu): each scenario with its rule, your best time, and a Start button.

func _ready():
	var bg = ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.15, 0.95)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	center.add_child(vbox)
	var title = Label.new()
	title.text = "FRANK'S CHALLENGES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)
	var sub_lbl = Label.new()
	sub_lbl.text = "Your most recent save's build, a scripted fight, and a rule that breaks the usual way of winning."
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub_lbl)
	for c in FrankChallenges.CHALLENGES:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var info = Label.new()
		var best = SaveManager.challenge_record(str(c["id"]))
		info.text = "%s  (%s, wave-%d enemies)  %s\n%s" % [c["title"], c["map"], int(c["wave"]), ("best %ds" % int(best)) if best >= 0.0 else "not cleared", c["brief"]]
		info.custom_minimum_size = Vector2(620, 0)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD
		row.add_child(info)
		var btn = Button.new()
		btn.text = "Start"
		btn.custom_minimum_size = Vector2(100, 44)
		btn.pressed.connect(func(): _launch(str(c["id"])))
		row.add_child(btn)
		vbox.add_child(row)
	var back = Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(200, 40)
	back.pressed.connect(func(): queue_free())
	vbox.add_child(back)

func _launch(id: String) -> void:
	var saves = SaveManager.get_save_files()
	SaveManager.save_to_load = "autosave" if "autosave" in saves else (saves[0] if not saves.is_empty() else "")
	SaveManager.pending_challenge = id
	SaveManager.current_game_mode = "challenge"
	var c = FrankChallenges.find(id)
	SaveManager.pending_run_card = {"map_type": str(c["map"]), "layout": "auto", "seed": 0, "era": "prewar"}
	get_tree().change_scene_to_file("res://main.tscn")
