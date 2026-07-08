extends CanvasLayer

# First-run onboarding: a JSON-driven sequence of steps (res://tutorial.json),
# each optionally spotlighting a live UI element while dimming the rest of
# the screen, showing an instruction panel, and advancing either on a manual
# "Next" click or on a named event fired via notify() from wherever the
# taught action actually happens (a tile placed, a button pressed, etc).
#
# Steps live in JSON (not code) for the same reason squad templates and AI
# profiles do - see config/default_squads.json and MODDING.md - so the
# sequence can be edited or replaced without touching GDScript.
#
# Anchors are resolved by GROUP NAME, not node path: the UI this needs to
# point at (Garage panels/buttons) is built dynamically in code with no
# stable path, so any Control that should be spotlightable just calls
# add_to_group("tutorial:<name>") once wherever it's created (see
# GarageMenu.gd's grid_panel/inventory_panel/sim_button for the pattern).
# The anchor is re-resolved every frame rather than cached at step-start, so
# a step can be queued up (e.g. "place a tile") before the Garage is even
# open yet - the game starts the player straight into combat, and the
# Garage only opens later via extraction or death (see Main._open_garage) -
# and the spotlight will pick the element up correctly once it exists.
#
# Any other script can drive step advancement with one line:
#   var tm = get_tree().get_first_node_in_group("tutorial_manager")
#   if tm: tm.notify("event:something_happened")

const TUTORIAL_JSON_PATH = "res://tutorial.json"
const SAVE_FLAG_PATH = "user://tutorial_completed.flag"

const COL_HIGHLIGHT = Color(1.0, 0.85, 0.4)

var steps: Array = []
var step_index: int = -1
var is_active: bool = false

var root: Control
var dim_full: ColorRect
var dim_top: ColorRect
var dim_bottom: ColorRect
var dim_left: ColorRect
var dim_right: ColorRect
var highlight_border: Control
var panel: PanelContainer

# Dirty-check state for _update_spotlight(), which used to re-resolve the
# anchor and rebuild all 4 dim-rect positions/sizes + queue_redraw() every
# single frame regardless of whether anything changed. Overlay only appears
# during onboarding and the anchor is almost always static frame-to-frame
# (nothing on screen is animating it), so this was pure waste. Now the
# layout math + redraw only runs when the resolved state actually differs
# from last frame.
var _last_spotlight_sig: String = ""
var _last_target_rect: Rect2 = Rect2()
var text_label: Label
var hint_label: Label
var next_button: Button
var skip_button: Button
var corner_hint: Label

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 150 # above War Room (99) and Debug Menu (100) - can guide over either
	add_to_group("tutorial_manager")

	# SaveManager.tutorial_completed is the per-save-slot bit (set by
	# _finish() below, restored by SaveManager.load_game() whenever a save
	# is loaded). The legacy flag file is still honored as a fallback so
	# players who already dismissed the tutorial before this bit existed
	# don't see it replay on their next launch.
	if SaveManager.tutorial_completed or FileAccess.file_exists(SAVE_FLAG_PATH):
		SaveManager.tutorial_completed = true
		return # already completed - stays dormant (see restart_tutorial() to replay)

	_load_steps()
	if steps.is_empty():
		return

	_build_ui()
	is_active = true
	_goto_step(0)

func _load_steps():
	steps = []
	var file = FileAccess.open(TUTORIAL_JSON_PATH, FileAccess.READ)
	if not file:
		return
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	var data = json.data
	if data is Dictionary and data.has("steps") and data["steps"] is Array:
		steps = data["steps"]

# Public hook - see file header. Advances the current step if its wait_for
# matches the fired event exactly (e.g. "event:simulate_pressed" or
# "tile_placed:Weapon Mount"; "tile_placed:any" matches every placement).
func notify(event: String):
	if not is_active or step_index < 0 or step_index >= steps.size():
		return
	var step = steps[step_index]
	if str(step.get("wait_for", "manual")) == event:
		_advance()

func _build_ui():
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	dim_full = _make_dim_rect()
	dim_top = _make_dim_rect()
	dim_bottom = _make_dim_rect()
	dim_left = _make_dim_rect()
	dim_right = _make_dim_rect()

	highlight_border = Control.new()
	highlight_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	highlight_border.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(highlight_border)
	highlight_border.draw.connect(_draw_highlight_border)

	panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.97)
	style.border_color = COL_HIGHLIGHT
	style.set_border_width_all(2)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	# Vertical position is NOT set here with a fixed guess anymore - it used
	# to be position -= Vector2(320, 110), which assumed a ~110px-tall panel.
	# Longer step text (3 wrapped lines, e.g. grid_intro) makes the panel
	# taller than that, and since both anchors pin to the bottom edge, the
	# extra height overflowed past the visible screen instead of growing
	# upward - see _reposition_panel(), called after every text change once
	# the real post-layout size is known.
	panel.custom_minimum_size = Vector2(640, 0)
	root.add_child(panel)

	var vbox = VBoxContainer.new()
	panel.add_child(vbox)

	text_label = Label.new()
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.custom_minimum_size = Vector2(608, 0)
	text_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(text_label)

	hint_label = Label.new()
	hint_label.modulate = Color(0.7, 0.75, 0.8)
	hint_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(hint_label)

	var btn_row = HBoxContainer.new()
	vbox.add_child(btn_row)

	next_button = Button.new()
	next_button.text = "Next"
	next_button.pressed.connect(_advance)
	btn_row.add_child(next_button)

	skip_button = Button.new()
	skip_button.text = "Skip Tutorial"
	skip_button.pressed.connect(_finish)
	btn_row.add_child(skip_button)

	# Shown instead of the full panel when the current step's anchor isn't
	# on screen yet (e.g. a Garage step queued up while still out in
	# combat) - a small non-blocking corner note rather than dimming
	# gameplay the player can't act on yet.
	corner_hint = Label.new()
	corner_hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	corner_hint.position = Vector2(-420, 16)
	corner_hint.custom_minimum_size = Vector2(400, 0)
	corner_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	corner_hint.add_theme_font_size_override("font_size", 13)
	corner_hint.modulate = Color(1.0, 0.9, 0.6, 0.9)
	root.add_child(corner_hint)

func _make_dim_rect() -> ColorRect:
	var r = ColorRect.new()
	r.color = Color(0.0, 0.0, 0.0, 0.65)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(r)
	return r

func _process(_delta):
	if is_active:
		_update_spotlight()

func _goto_step(idx: int):
	step_index = idx
	if idx >= steps.size():
		_finish()
		return
	var step = steps[idx]
	if step.get("requires_garage", false):
		_ensure_in_garage()
	text_label.text = str(step.get("text", ""))
	var wait_for = str(step.get("wait_for", "manual"))
	next_button.visible = (wait_for == "manual")
	hint_label.visible = (wait_for != "manual")
	if wait_for.begins_with("tile_placed:"):
		hint_label.text = "(do this in the Garage to continue)"
	elif wait_for.begins_with("event:"):
		hint_label.text = "(do this to continue)"
	_update_spotlight()
	_reposition_panel()

# The panel's height varies with how many lines the current step's text
# wraps to (1 line for short steps, 3+ for grid_intro/done) - it needs a
# real post-layout size to position correctly, which isn't available until
# a frame after the text/VBoxContainer actually resize. Both of panel's
# anchors are pinned to the bottom edge (PRESET_CENTER_BOTTOM), so position
# here is plain local offset from that anchor point, not "the panel's rect" -
# this keeps the panel's bottom edge a fixed margin above the screen bottom
# no matter how tall it grows, instead of the old hardcoded -110 guess that
# only fit a single line of text and let anything taller run off-screen.
const PANEL_BOTTOM_MARGIN = 20.0
func _reposition_panel():
	await get_tree().process_frame
	if not is_instance_valid(panel):
		return
	panel.position = Vector2(-panel.size.x / 2.0, -panel.size.y - PANEL_BOTTOM_MARGIN)

# Steps flagged "requires_garage" (grid_intro/place_any_tile/simulate - all
# three teach Garage-only UI) used to just passively wait for their anchor
# group to appear, which never happens if the player is still out in the
# live game world (the game starts you straight into combat, same as the
# file header describes) - the panel/corner-hint would sit there dimming a
# scene with nothing to spotlight. Actively pop the player into the Garage
# here, mirroring the exact call DebugMenu's "Teleport to Garage" button and
# ExtractionMarker use, instead of only ever reacting to it.
func _ensure_in_garage():
	var main = get_parent()
	if main and main.get("garage_ui") == null and main.has_method("_open_garage"):
		main._open_garage()

func _advance():
	_goto_step(step_index + 1)

func _finish():
	is_active = false
	SaveManager.tutorial_completed = true
	var f = FileAccess.open(SAVE_FLAG_PATH, FileAccess.WRITE)
	if f:
		f.store_string("done")
		f.close()
	if root:
		root.queue_free()

# Lets a settings/debug menu re-trigger the flow later without the player
# having to find and delete the save flag file by hand.
func restart_tutorial():
	SaveManager.tutorial_completed = false
	if FileAccess.file_exists(SAVE_FLAG_PATH):
		DirAccess.remove_absolute(SAVE_FLAG_PATH)
	_load_steps()
	if steps.is_empty():
		return
	if not root:
		_build_ui()
	is_active = true
	_goto_step(0)

func _current_step() -> Dictionary:
	if step_index < 0 or step_index >= steps.size():
		return {}
	return steps[step_index]

func _update_spotlight():
	var step = _current_step()
	if step.is_empty():
		return

	var anchor_name = str(step.get("anchor", ""))
	var anchor: Control = null
	if anchor_name != "":
		var found = get_tree().get_first_node_in_group(anchor_name)
		if found is Control and found.is_visible_in_tree():
			anchor = found

	var waiting_for_screen = anchor_name != "" and anchor == null
	var anchor_rect = anchor.get_global_rect() if anchor else Rect2()
	var sig = "%d|%s|%s" % [step_index, waiting_for_screen, anchor_rect]
	if sig == _last_spotlight_sig:
		return # nothing changed since last frame - skip the layout/redraw work
	_last_spotlight_sig = sig

	panel.visible = not waiting_for_screen
	corner_hint.visible = waiting_for_screen
	if waiting_for_screen:
		corner_hint.text = str(step.get("text", ""))
		_hide_spotlight()
		return

	if not anchor:
		# Narrative step with no anchor at all - dim everything, no cutout.
		_show_full_dim()
		return

	_show_spotlight_on(anchor)

func _hide_spotlight():
	dim_full.visible = false
	dim_top.visible = false
	dim_bottom.visible = false
	dim_left.visible = false
	dim_right.visible = false
	highlight_border.visible = false

func _show_full_dim():
	var full_rect = get_viewport().get_visible_rect()
	dim_full.visible = true
	dim_full.position = Vector2.ZERO
	dim_full.size = full_rect.size
	dim_top.visible = false
	dim_bottom.visible = false
	dim_left.visible = false
	dim_right.visible = false
	highlight_border.visible = false

func _show_spotlight_on(anchor: Control):
	var full_rect = get_viewport().get_visible_rect()
	dim_full.visible = false

	var target_rect = anchor.get_global_rect().grow(6.0)

	dim_top.visible = true
	dim_top.position = Vector2(0, 0)
	dim_top.size = Vector2(full_rect.size.x, max(0.0, target_rect.position.y))

	dim_bottom.visible = true
	dim_bottom.position = Vector2(0, target_rect.position.y + target_rect.size.y)
	dim_bottom.size = Vector2(full_rect.size.x, max(0.0, full_rect.size.y - (target_rect.position.y + target_rect.size.y)))

	dim_left.visible = true
	dim_left.position = Vector2(0, target_rect.position.y)
	dim_left.size = Vector2(max(0.0, target_rect.position.x), target_rect.size.y)

	dim_right.visible = true
	dim_right.position = Vector2(target_rect.position.x + target_rect.size.x, target_rect.position.y)
	dim_right.size = Vector2(max(0.0, full_rect.size.x - (target_rect.position.x + target_rect.size.x)), target_rect.size.y)

	highlight_border.visible = true
	highlight_border.set_meta("_target_rect", target_rect)
	highlight_border.queue_redraw()

func _draw_highlight_border():
	if not highlight_border.has_meta("_target_rect"):
		return
	var r: Rect2 = highlight_border.get_meta("_target_rect")
	highlight_border.draw_rect(r, COL_HIGHLIGHT, false, 3.0)
