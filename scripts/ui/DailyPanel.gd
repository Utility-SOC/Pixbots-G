extends CanvasLayer

# Daily Run: today's seed (derived from the UTC date, so it needs no server),
# plus run-card import/export. See docs/DAILY_SEED.md.

const RunCard = preload("res://scripts/pvp/RunCard.gd")
const MetaProgress = preload("res://scripts/core/MetaProgress.gd")
const LeaderboardClient = preload("res://scripts/core/LeaderboardClient.gd")

var _status: Label
var _list: VBoxContainer
var _today: Dictionary

func _ready():
	layer = 120
	_today = RunCard.daily_params(RunCard.today_string())
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(580, 0)
	center.add_child(panel)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title = Label.new()
	title.text = "DAILY RUN"
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)
	var info = Label.new()
	info.text = "%s   |   map: %s, layout: %s   |   seed %d\nYour best today: wave %d" % [_today["date"], _today["map_type"], _today["layout"], _today["seed"], MetaProgress.daily_best(_today["date"])]
	box.add_child(info)
	var lb = Label.new()
	lb.text = "Leaderboard: " + ("online" if LeaderboardClient.is_available() else "not available yet - runs are compared by sharing run cards.")
	lb.modulate = Color(0.7, 0.7, 0.75)
	box.add_child(lb)

	var play = Button.new()
	play.text = "Play today's run"
	play.pressed.connect(func(): _launch(_today))
	box.add_child(play)
	var export_btn = Button.new()
	export_btn.text = "Export today's run card (PNG)"
	export_btn.pressed.connect(_export_today)
	box.add_child(export_btn)
	var import_lbl = Label.new()
	import_lbl.text = "Run cards in user://run_cards/ :"
	box.add_child(import_lbl)
	_list = VBoxContainer.new()
	box.add_child(_list)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	var close = Button.new()
	close.text = "Close"
	close.pressed.connect(queue_free)
	box.add_child(close)
	_refresh_cards()

func _launch(card: Dictionary) -> void:
	SaveManager.pending_run_card = card
	SaveManager.current_game_mode = "endless"
	get_tree().change_scene_to_file("res://main.tscn")

func _export_today() -> void:
	var result = {}
	if MetaProgress.daily_best(_today["date"]) > 0:
		result = {"wave": MetaProgress.daily_best(_today["date"]), "seconds": 0, "kills": 0}
	var card = RunCard.build(_today, SaveManager.pilot_name if "pilot_name" in SaveManager else "", {}, result)
	var path = RunCard.export_card(card)
	_status.text = ("Saved %s" % ProjectSettings.globalize_path(path)) if path != "" else "Could not write the card."
	_refresh_cards()

func _refresh_cards() -> void:
	for c in _list.get_children():
		c.queue_free()
	var cards = RunCard.list_cards()
	if cards.is_empty():
		var none = Label.new()
		none.text = "  (none yet - drop friends' run card PNGs there)"
		none.modulate = Color(0.6, 0.6, 0.65)
		_list.add_child(none)
	for entry in cards:
		var c: Dictionary = entry["card"]
		var row = HBoxContainer.new()
		_list.add_child(row)
		var lbl = Label.new()
		var res = ""
		if c.has("result"):
			res = "  (wave %d)" % int(c["result"]["wave"])
		lbl.text = "%s: %s / %s%s %s" % [c["mode"], c["map_type"], c["layout"], res, ("by " + c["pilot"]) if c["pilot"] != "" else ""]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var btn = Button.new()
		btn.text = "Play"
		btn.pressed.connect(func(): _launch(c))
		row.add_child(btn)
