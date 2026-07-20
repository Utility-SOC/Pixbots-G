extends CanvasLayer

# Always-on-top FPS/frame-time overlay (per the user: "add a framerate
# counter so I don't have to use video to show this in the future"). An
# autoload, not wired into any one screen's HUD, so it's visible everywhere
# - Main Menu, Garage, combat, War Room - without needing separate wiring
# per screen the way wave_label/timer_label etc. are Main.gd-only.
#
# Shows FPS AND frame time in milliseconds - FPS alone flattens out at low
# framerates (30 vs 20 vs 15 fps all just read as "bad"), while ms scales
# linearly and is what actually explains "why": a Garage freeze spiking to
# 500ms is instantly legible as a real stall, not just a vague low number.
# Color-coded so a single screenshot (no video needed) tells the story:
# green = fine, yellow = notice, red = a real problem.

var label: Label
var _frame_times: Array[float] = []
const SMOOTH_WINDOW = 20 # rolling average - raw per-frame jitter is noisy

func _ready():
	layer = 999 # above everything - HUD (5), War Room (99), Debug Menu (100)
	process_mode = Node.PROCESS_MODE_ALWAYS

	label = Label.new()
	label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	label.position = Vector2(-140, 4)
	label.custom_minimum_size = Vector2(136, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	add_child(label)

func _process(delta: float):
	if not visible:
		return
	_frame_times.append(delta)
	if _frame_times.size() > SMOOTH_WINDOW:
		_frame_times.pop_front()
	var avg_delta = 0.0
	for d in _frame_times:
		avg_delta += d
	avg_delta /= _frame_times.size()

	var fps = Engine.get_frames_per_second()
	var ms = avg_delta * 1000.0
	label.text = "%d fps  %.1f ms" % [fps, ms]

	# 60fps target -> 16.7ms. Yellow past a dropped-frame-or-two budget,
	# red once it's a genuinely visible stutter.
	if ms > 50.0:
		label.modulate = Color(1.0, 0.3, 0.3)
	elif ms > 20.0:
		label.modulate = Color(1.0, 0.85, 0.2)
	else:
		label.modulate = Color(0.4, 1.0, 0.5)

func _unhandled_input(event: InputEvent):
	# F3: the common cross-game convention for a debug/perf overlay toggle.
	# Deliberately a raw physical-keycode check, not a new InputMap action -
	# this is a dev/QA utility, not a bindable gameplay action that should
	# show up in a future "remap controls" list.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F3:
			visible = not visible
			get_viewport().set_input_as_handled()
