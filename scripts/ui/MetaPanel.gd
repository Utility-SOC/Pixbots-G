extends CanvasLayer

# Corp Perks: spend Research Points (MetaProgress) on permanent salvage perks.

const MetaProgress = preload("res://scripts/core/MetaProgress.gd")

var _list: VBoxContainer
var _rp_label: Label

func _ready():
	layer = 120
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title = Label.new()
	title.text = "CORP PERKS"
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)
	_rp_label = Label.new()
	box.add_child(_rp_label)
	var hint = Label.new()
	hint.text = "Research Points come from reaching a new best wave and from boss kills.\nPerks only improve salvage luck - never combat stats."
	hint.modulate = Color(0.7, 0.7, 0.75)
	box.add_child(hint)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	box.add_child(_list)
	var close = Button.new()
	close.text = "Close"
	close.pressed.connect(queue_free)
	box.add_child(close)
	_refresh()

func _refresh() -> void:
	_rp_label.text = "Research Points: %d    (best wave: %d)" % [MetaProgress.rp(), MetaProgress.best_wave()]
	for c in _list.get_children():
		c.queue_free()
	for id in MetaProgress.PERKS:
		var info = MetaProgress.PERKS[id]
		var row = HBoxContainer.new()
		_list.add_child(row)
		var lbl = Label.new()
		lbl.text = "%s  [%d/%d]  -  %s" % [info["name"], MetaProgress.perk_level(id), MetaProgress.MAX_LEVEL, info["desc"]]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(lbl)
		var btn = Button.new()
		var cost = MetaProgress.next_cost(id)
		btn.text = "MAX" if cost < 0 else "Buy (%d RP)" % cost
		btn.disabled = not MetaProgress.can_buy(id)
		btn.pressed.connect(func():
			MetaProgress.buy(id)
			_refresh())
		row.add_child(btn)
