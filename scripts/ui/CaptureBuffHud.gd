class_name CaptureBuffHud
extends Control

# A small strip under the wave and timer labels listing the player's active capture buffs with time left (CaptureBuffs).
# Hidden when there are none. Polls four times a second; draws coloured chips with a label and a seconds counter.

const REFRESH = 0.25
const CHIP = Vector2(210, 24)

var main: Node = null
var _t: float = 0.0
var _rows: Array = [] # [{type, left}]

func _ready():
	position = Vector2(20, 96)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func _process(delta: float):
	_t -= delta
	if _t > 0.0:
		return
	_t = REFRESH
	refresh(main.player if main != null and "player" in main else null)

# Rebuilds the rows from a mech's capture_buffs (split out so tests can call it directly).
func refresh(mech) -> void:
	_rows.clear()
	if mech != null and is_instance_valid(mech) and "capture_buffs" in mech:
		for k in CaptureBuffs.TYPES:
			if mech.capture_buffs.has(k):
				_rows.append({"type": k, "left": float(mech.capture_buffs[k])})
	visible = not _rows.is_empty()
	queue_redraw()

func rows() -> Array:
	return _rows

func _draw():
	var font = ThemeDB.fallback_font
	for i in range(_rows.size()):
		var r: Dictionary = _rows[i]
		var col: Color = CaptureBuffs.COLORS[r["type"]]
		var y = float(i) * (CHIP.y + 4.0)
		draw_rect(Rect2(0, y, CHIP.x, CHIP.y), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(0, y, 8, CHIP.y), col)
		var frac = clampf(float(r["left"]) / CaptureBuffs.DURATION, 0.0, 1.0)
		draw_rect(Rect2(8, y + CHIP.y - 4, (CHIP.x - 8) * frac, 4), Color(col.r, col.g, col.b, 0.8))
		draw_string(font, Vector2(14, y + 16), "%s  %ds" % [CaptureBuffs.LABELS[r["type"]], int(ceil(float(r["left"])))], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1))
