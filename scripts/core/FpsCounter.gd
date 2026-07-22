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
# Second line: a physics/script-process time breakdown plus live entity
# counts, so the NEXT time framerate tanks in a real session we get
# trustworthy numbers correlated with what's actually on screen, instead of
# another video or a guess. (A synthetic headless stress-test harness was
# tried first - scripts/debug/ProjectileBroadphaseProfileDiagnostic.gd - but its
# own timing methodology proved unreliable: wall-clock across awaited
# physics frames just measures engine frame-pacing, and summing
# Performance.TIME_PHYSICS_PROCESS across those same awaits produced
# self-contradicting numbers. The one trustworthy signal it DID surface -
# PHYSICS_2D_ACTIVE_OBJECTS/COLLISION_PAIRS staying near zero even with 60
# mechs + 300 projectiles live - argues against Area2D broadphase being the
# bottleneck, but real in-session numbers beat a shaky synthetic one.)
var breakdown_label: Label
# Third line: real rendering metrics (draw calls, objects, primitives) -
# task #14's "draw batching" scope needs its OWN direct evidence, same
# lesson as the physics/process breakdown above: don't touch rendering
# code on a guess. These are Godot's actual render-server counters, not an
# inferred/timing-based proxy, so they're trustworthy the instant they're
# read - no synthetic-harness pitfalls to worry about here.
var render_label: Label
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

	breakdown_label = Label.new()
	breakdown_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	breakdown_label.position = Vector2(-220, 26)
	breakdown_label.custom_minimum_size = Vector2(216, 0)
	breakdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	breakdown_label.add_theme_font_size_override("font_size", 12)
	breakdown_label.add_theme_constant_override("outline_size", 3)
	breakdown_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	breakdown_label.modulate = Color(0.85, 0.85, 0.85)
	add_child(breakdown_label)

	render_label = Label.new()
	render_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	render_label.position = Vector2(-220, 44)
	render_label.custom_minimum_size = Vector2(216, 0)
	render_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	render_label.add_theme_font_size_override("font_size", 12)
	render_label.add_theme_constant_override("outline_size", 3)
	render_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	render_label.modulate = Color(0.75, 0.85, 0.95)
	add_child(render_label)

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

	var physics_ms = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var process_ms = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var proj_count = ProjectileManager.live_count() if ProjectileManager else 0
	var enemy_count = EntityCache.get_group("enemy").size() if EntityCache else 0
	var collision_pairs = Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)
	breakdown_label.text = "phys %.1fms  proc %.1fms  |  %d shots  %d enemies  %d pairs" % [
		physics_ms, process_ms, proj_count, enemy_count, collision_pairs
	]

	var draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var objects = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var primitives = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	render_label.text = "%d draws  %d objs  %.0fk verts" % [draw_calls, objects, primitives / 1000.0]

func _unhandled_input(event: InputEvent):
	# F3: the common cross-game convention for a debug/perf overlay toggle.
	# Deliberately a raw physical-keycode check, not a new InputMap action -
	# this is a dev/QA utility, not a bindable gameplay action that should
	# show up in a future "remap controls" list.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F3:
			visible = not visible
			get_viewport().set_input_as_handled()
