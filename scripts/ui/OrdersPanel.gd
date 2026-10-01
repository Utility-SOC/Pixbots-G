extends VBoxContainer

# Bottom-left HUD feed of enemy radio chatter (see OrdersLog). Shows the last
# few lines, fading as they age. Non-interactive.

const MAX_LINES = 4
const LINE_LIFE = 9.0
const FADE = 2.5

const KIND_COLORS = {
	"plan": Color(0.75, 0.85, 1.0), "commit": Color(1.0, 0.85, 0.45), "replan": Color(0.85, 0.75, 1.0),
	"casualty": Color(1.0, 0.6, 0.5), "wipe": Color(0.6, 1.0, 0.65),
}

var _log = null
var _age: Dictionary = {}

func _init():
	process_mode = Node.PROCESS_MODE_ALWAYS # runs while the Garage has the tree paused
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 2)

func bind(orders) -> void:
	if _log == orders:
		return
	if _log and _log.line_emitted.is_connected(_on_line):
		_log.line_emitted.disconnect(_on_line)
	_log = orders
	if _log:
		_log.line_emitted.connect(_on_line)

func _on_line(entry: Dictionary) -> void:
	var l = Label.new()
	l.text = entry["text"]
	l.modulate = KIND_COLORS.get(entry["kind"], Color.WHITE)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	add_child(l)
	_age[l] = 0.0
	while get_child_count() > MAX_LINES:
		var old = get_child(0)
		_age.erase(old)
		remove_child(old)
		old.queue_free()

func _process(delta: float) -> void:
	var main = get_tree().current_scene
	visible = main == null or not is_instance_valid(main.get("garage_ui")) # no chatter over the Garage
	for l in get_children():
		_age[l] = float(_age.get(l, 0.0)) + delta
		var a = _age[l]
		var base: Color = l.modulate
		base.a = clamp((LINE_LIFE - a) / FADE, 0.0, 1.0)
		l.modulate = base
		if a >= LINE_LIFE:
			_age.erase(l)
			remove_child(l)
			l.queue_free()
