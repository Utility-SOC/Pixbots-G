class_name TableSettingScreen
extends CanvasLayer

# "Setting the table...": the loading card shown while a battlefield regenerates (the big maps take several seconds on weak GPUs).
# Shop-tables backdrop, a line in the Shopkeeper's voice, animated dots. Added above everything and always processing, so it
# keeps drawing while the tree is paused. Use TableSettingScreen.show_over(host) then `await` two frames before the heavy work.

const LINES = [
	"Setting the table...",
	"Unfolding the felt...",
	"Arranging the terrain...",
	"Dusting off the scenery...",
]

var _label: Label
var _t: float = 0.0
var _base: String = ""

static func show_over(host: Node) -> TableSettingScreen:
	var s = TableSettingScreen.new()
	host.add_child(s)
	return s

func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ShopBackdrop.frame("tables", 0.45))
	_base = LINES[randi() % LINES.size()].trim_suffix("...")
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_label.add_theme_font_size_override("font_size", 36)
	_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
	_label.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02))
	_label.add_theme_constant_override("outline_size", 8)
	_label.text = _base
	add_child(_label)

func _process(delta: float) -> void:
	_t += delta
	_label.text = _base + ".".repeat(int(_t * 3.0) % 4)

func finish() -> void:
	queue_free()
