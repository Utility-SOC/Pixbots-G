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
	var counter = get_tree().root.get_node_or_null("FpsCounter")
	_check("FpsCounter autoload is present in the tree", counter != null)
	if not counter:
		get_tree().quit(1)
		return

	_check("FpsCounter draws above every other layer (999)", counter.layer == 999)
	_check("FpsCounter is visible by default", counter.visible)
	_check("FpsCounter has a real Label child", counter.label != null and counter.label is Label)
	_check("FpsCounter has a real breakdown_label child", counter.breakdown_label != null and counter.breakdown_label is Label)

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

	if failures == 0:
		print("PASS: FpsCounter autoload shows live FPS/frame-time on every screen, toggleable with F3")
	get_tree().quit(0 if failures == 0 else 1)
