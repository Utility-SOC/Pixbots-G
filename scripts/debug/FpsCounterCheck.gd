extends Node

# Regression harness for: "could you add a framerate counter so I don't
# have to use video to show this in the future?" FpsCounter is a
# project.godot autoload (visible on every screen, not wired into any one
# HUD), so it's already present as a real sibling of this check's own root
# by the time _ready() runs - verifies it initialized correctly, updates
# its label from real frame data, and F3 toggles visibility.

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# Headless default viewport is tiny (64x64) - the drag-clamp test below
	# needs a realistic size, otherwise a small drag delta gets clamped
	# against the tiny viewport and looks like a bug that isn't one.
	get_tree().root.size = Vector2i(1920, 1080)
	var counter = get_tree().root.get_node_or_null("FpsCounter")
	_check("FpsCounter autoload is present in the tree", counter != null)
	if not counter:
		get_tree().quit(1)
		return

	_check("FpsCounter draws above every other layer (999)", counter.layer == 999)
	_check("FpsCounter is visible by default", counter.visible)
	_check("FpsCounter has a real Label child", counter.label != null and counter.label is Label)
	_check("FpsCounter has a real breakdown_label child", counter.breakdown_label != null and counter.breakdown_label is Label)
	_check("FpsCounter has a real render_label child", counter.render_label != null and counter.render_label is Label)

	# Let a couple of real frames tick so _process actually populates text.
	await get_tree().process_frame
	await get_tree().process_frame
	_check("label text was populated from real frame data (contains 'fps')",
		counter.label.text.contains("fps"))
	_check("label text also shows frame time in ms", counter.label.text.contains("ms"))
	_check("breakdown label shows a physics/process time split (contains 'phys' and 'proc')",
		counter.breakdown_label.text.contains("phys") and counter.breakdown_label.text.contains("proc"))
	_check("breakdown label shows live shot/enemy counts (contains 'shots' and 'enemies')",
		counter.breakdown_label.text.contains("shots") and counter.breakdown_label.text.contains("enemies"))
	# Headless has no real RenderingDevice (dummy driver), so the actual
	# numbers are meaningless here - just confirm the line populates in the
	# expected shape. Real counts only mean something in a windowed session.
	_check("render label shows draw call/object/vertex counts (contains 'draws', 'objs', 'verts')",
		counter.render_label.text.contains("draws") and counter.render_label.text.contains("objs") and counter.render_label.text.contains("verts"))

	# F3 toggle.
	var was_visible = counter.visible
	var f3_event = InputEventKey.new()
	f3_event.physical_keycode = KEY_F3
	f3_event.pressed = true
	counter._unhandled_input(f3_event)
	_check("F3 toggles visibility off", counter.visible != was_visible)
	counter._unhandled_input(f3_event)
	_check("F3 toggles visibility back on", counter.visible == was_visible)

	# When hidden, _process should skip updating (no wasted work while off).
	counter.visible = false
	var text_before = counter.label.text
	await get_tree().process_frame
	_check("no label updates while hidden (early-out in _process)", counter.label.text == text_before)
	counter.visible = true # restore for the rest of the real session

	# --- Drag-to-move (playtest report: fixed top-left position overlapped
	# the Garage's component tab row) ---
	var start_pos = counter.panel.position
	var mouse_within_panel = counter.panel.get_global_rect().position + Vector2(10, 5)
	var down = InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = mouse_within_panel
	counter._unhandled_input(down)
	_check("mouse-down inside the panel starts a drag", counter._dragging)

	var motion = InputEventMouseMotion.new()
	motion.position = mouse_within_panel + Vector2(150, 80)
	counter._unhandled_input(motion)
	_check("dragging actually moves the panel", counter.panel.position != start_pos)
	_check("panel moved by roughly the mouse delta (150, 80)",
		(counter.panel.position - start_pos).distance_to(Vector2(150, 80)) < 1.0)

	var up = InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = motion.position
	counter._unhandled_input(up)
	_check("mouse-up ends the drag", not counter._dragging)

	# Off-screen clamp: drag far past the viewport edge, position should
	# clamp back to visible bounds instead of vanishing off-screen forever.
	counter._unhandled_input(down) # start a fresh drag from the same spot
	var far_motion = InputEventMouseMotion.new()
	far_motion.position = Vector2(-5000, -5000)
	counter._unhandled_input(far_motion)
	var vp_size = counter.get_viewport().get_visible_rect().size
	_check("dragging past the viewport edge clamps in bounds, doesn't vanish off-screen",
		counter.panel.position.x >= 0.0 and counter.panel.position.y >= 0.0)
	counter._unhandled_input(up)

	# --- Position persistence: round-trip against a SCRATCH file, never
	# the real SaveManager.SETTINGS_PATH (user:// is the real save dir). ---
	var scratch_path = "C:/Users/Utility/AppData/Local/Temp/claude/fps_overlay_test_scratch.cfg"
	if FileAccess.file_exists(scratch_path):
		DirAccess.remove_absolute(scratch_path)
	counter.panel.position = Vector2(321, 654)
	counter._save_position(scratch_path)
	_check("position round-trips through save/load", counter._load_position(scratch_path) == Vector2(321, 654))
	_check("a missing/fresh settings file falls back to DEFAULT_POSITION",
		counter._load_position("C:/Users/Utility/AppData/Local/Temp/claude/does_not_exist.cfg") == counter.DEFAULT_POSITION)
	if FileAccess.file_exists(scratch_path):
		DirAccess.remove_absolute(scratch_path)

	if failures == 0:
		print("PASS: FpsCounter autoload shows live FPS/frame-time on every screen, toggleable with F3")
	get_tree().quit(0 if failures == 0 else 1)
