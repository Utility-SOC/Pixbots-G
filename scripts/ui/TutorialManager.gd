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

# Hand-over-hand guided build (per the user: "it needs to show where, and
# how the hexes will work by walking the user through a good/optimized
# build... fully hand over hand") - a step with "type": "guided_build" and
# a "slot" (BodySlot name string, e.g. "TORSO"/"ARM_L") hands control to a
# GuidedBuildRunner instead of showing static text. See GuidedBuildPlanner.
# gd's header for how the plan itself gets computed (reuses AutoEquipSolver
# against a throwaway clone, never the player's real state) and
# GuidedBuildRunner.gd for how each individual micro-step is driven.
const GuidedBuildRunnerScript = preload("res://scripts/ui/GuidedBuildRunner.gd")
var guided_build_runner = null
var _guided_build_started_for_index: int = -1

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
# Always-visible escape hatch: the panel's Skip button is hidden whenever
# the panel is (anchor-waiting, guided-build-not-ready), which used to trap
# the player - a guided-build step that couldn't start (wrong tab / garage
# timing) left only a text corner note with no controls at all ("getting
# stuck on that screen, unclear how to advance"). This button is a direct
# child of root, shown whenever the tutorial is active, and can never be
# hidden by the panel/spotlight logic. It skips the CURRENT step (one click
# = unstick), so a player can always claw forward one step at a time even
# if a single step's trigger never fires.
var escape_button: Button

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 150 # above War Room (99) and Debug Menu (100) - can guide over either
	add_to_group("tutorial_manager")

	# SaveManager.tutorial_completed is the per-save-slot bit (set by
	# _finish() below, restored by SaveManager.load_game() whenever a save
	# is loaded, reset on New Game). Per the user: "could it force me to do
	# the tutorial every time I start a new game unless I click skip?" -
	# so this is now the ONLY gate. The old machine-wide flag file
	# (user://tutorial_completed.flag) is deliberately no longer honored:
	# it made the tutorial one-time-ever per machine, which is exactly the
	# behavior being replaced. Every NEW game runs the tutorial (Skip is
	# always one click away, and skipping auto-equips a functional bot -
	# see _on_skip); a LOADED save that already completed/skipped it stays
	# dormant via the restored per-save bit.
	if SaveManager.tutorial_completed:
		return # already completed in THIS save - see restart_tutorial() to replay

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
	skip_button.pressed.connect(_on_skip)
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

	# Persistent unstick control - see the field comment. Anchored just under
	# the corner hint, always reachable while the tutorial runs.
	escape_button = Button.new()
	escape_button.text = "Skip this step →"
	escape_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	escape_button.position = Vector2(-180, 92)
	escape_button.tooltip_text = "Advance the tutorial if a step won't continue. (Skip Tutorial in the panel exits the whole thing.)"
	escape_button.pressed.connect(_on_escape_pressed)
	root.add_child(escape_button)

func _make_dim_rect() -> ColorRect:
	var r = ColorRect.new()
	r.color = Color(0.0, 0.0, 0.0, 0.65)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(r)
	return r

func _process(_delta):
	if not is_active:
		if escape_button:
			escape_button.visible = false
		return
	if escape_button:
		escape_button.visible = true # never hidden by panel/spotlight state
	if str(_current_step().get("type", "")) == "guided_build":
		_update_guided_build()
	else:
		_update_spotlight()

# Persistent unstick: advance the current step regardless of whatever
# trigger it was waiting on. If this was a guided_build step mid-plan, drop
# the runner so the next step starts clean. Never trapped again.
func _on_escape_pressed():
	guided_build_runner = null
	_guided_build_started_for_index = -1
	_advance()

func _goto_step(idx: int):
	step_index = idx
	if idx >= steps.size():
		_finish()
		return
	var step = steps[idx]
	if step.get("requires_garage", false):
		_ensure_in_garage()

	if str(step.get("type", "")) == "guided_build":
		# Text/spotlight/button visibility are all driven dynamically per
		# micro-step from here on - see _update_guided_build().
		guided_build_runner = null
		_guided_build_started_for_index = -1
		next_button.visible = false
		hint_label.visible = true
		hint_label.text = "(do this in the Garage to continue)"
		_reposition_panel()
		return

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

# Hand-over-hand guided build (see the GuidedBuildRunnerScript field
# comment up top). Lazily starts the runner once the target component
# actually exists (mirrors _update_spotlight's own "waiting_for_screen"
# pattern for a step whose Garage anchor isn't on screen yet), then polls
# it every frame: re-point the spotlight/instruction at whatever the
# runner currently wants, or advance the outer tutorial step once the
# whole plan is satisfied.
func _start_guided_build(step: Dictionary) -> bool:
	var main = get_parent()
	if not main or main.get("garage_ui") == null:
		return false
	var garage = main.garage_ui
	if not garage.grid_renderer or not garage.grid_renderer.is_visible_in_tree():
		return false
	var HexTileCls = load("res://scripts/core/HexTile.gd")
	var slot_name = str(step.get("slot", "TORSO"))
	var slot = HexTileCls.BodySlot.get(slot_name, HexTileCls.BodySlot.TORSO)
	if not garage.mech_components.has(slot):
		return false
	var component = garage.mech_components[slot]
	# Wait for the player to actually be looking at THIS component's tab -
	# grid_renderer only draws whichever one is currently active, so
	# spotlighting a hex before the tab switch would highlight the wrong
	# position on whatever's on screen right now.
	if garage.active_component != component:
		return false
	guided_build_runner = GuidedBuildRunnerScript.new()
	guided_build_runner.start(component, garage.inventory)
	_guided_build_started_for_index = step_index
	return true

func _update_guided_build():
	var step = _current_step()
	if step.is_empty():
		return

	if _guided_build_started_for_index != step_index:
		if not _start_guided_build(step):
			# Not ready yet (Garage not open, wrong tab, or this component
			# doesn't exist). Give an ACTIONABLE note - the raw step text
			# ("Building the Torso...") told a stuck player nothing about
			# WHY it wasn't moving. The persistent "Skip this step" button
			# (see _build_ui) is also visible the whole time as a backstop.
			panel.visible = false
			corner_hint.visible = true
			var slot_label = str(step.get("slot", "TORSO")).capitalize().replace("_", " ")
			corner_hint.text = "Open the Garage and click the %s tab to keep going.\n(Stuck? Use \"Skip this step →\" top-right.)" % slot_label
			_hide_spotlight()
			return

	panel.visible = true
	corner_hint.visible = false

	if guided_build_runner.check_and_advance():
		guided_build_runner = null
		_advance()
		return

	var new_text = guided_build_runner.current_instruction()
	if text_label.text != new_text:
		text_label.text = new_text
		_reposition_panel()

	var main = get_parent()
	var garage = main.garage_ui
	_show_spotlight_on_hex(garage.grid_renderer, guided_build_runner.current_hex())

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
	# Per-save bit only - the old machine-wide flag file is no longer
	# written (or honored, see _ready): the tutorial now runs on every new
	# game by design, so persisting "done" beyond this save would defeat it.
	SaveManager.tutorial_completed = true
	if root:
		root.queue_free()

# Skip path (per the user: "clicking skip equips the bot well enough - not
# WELL, but functional - the player can adjust it after that"): before the
# normal finish, run the real Auto-Equip solver over every equipped
# component with the player's actual starting inventory, so a skipping
# player deploys with routed, firing weapons instead of a bare Core and an
# empty grid. Natural completion deliberately does NOT do this - by then
# the player hand-built their grid through the guided steps, and silently
# rearranging it would trash their own work.
func _on_skip():
	# DISMISS FIRST. Skip must ALWAYS work - the auto-equip below is a
	# convenience, not a gate, and an error inside it must never leave the
	# player trapped in the tutorial ("the tutorial can't be skipped"). By
	# the time _apply_skip_equip runs, the tutorial is already gone.
	is_active = false
	SaveManager.tutorial_completed = true
	if root:
		root.queue_free()
		root = null
	_apply_skip_equip()

func _apply_skip_equip():
	var main = get_parent()
	if not main or main.get("player") == null:
		return
	var player = main.player
	if not ("components" in player):
		return
	if not ("player_inventory" in main):
		return
	var inventory: Array = main.player_inventory
	var solver = load("res://scripts/core/AutoEquipSolver.gd").new()
	for slot in player.components.keys():
		var comp = player.components[slot]
		if comp and comp.hex_grid:
			var solved = solver.solve(comp, inventory)
			# NEVER let a null/failed solve wipe the inventory - that emptied
			# the player's whole tile bin ("the component inventory is
			# empty"). Keep the prior inventory on any non-Array result.
			if solved is Array:
				inventory = solved
	main.player_inventory = inventory
	player.is_grid_dirty = true
	if player.has_method("_recalculate_grid"):
		player._recalculate_grid()

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
	_show_spotlight_on_rect(anchor.get_global_rect().grow(6.0))

# Same cutout as _show_spotlight_on, but for a hex cell inside a
# GarageGridRenderer instead of a whole registered Control - used by the
# guided-build walkthrough (see GuidedBuildRunner.gd) to point at the exact
# hex the player needs to act on next. _hex_to_pixel already folds in the
# renderer's current pan/zoom (see that function's own comment), so this
# only needs to add the renderer's own screen-space origin on top.
func _show_spotlight_on_hex(grid_renderer: Control, hex: HexCoord):
	var local_pos: Vector2 = grid_renderer._hex_to_pixel(hex)
	var global_pos: Vector2 = grid_renderer.get_global_transform() * local_pos
	var half_size: float = grid_renderer.hex_size * grid_renderer.zoom
	var target_rect = Rect2(global_pos - Vector2(half_size, half_size), Vector2(half_size, half_size) * 2.0)
	_show_spotlight_on_rect(target_rect)

func _show_spotlight_on_rect(target_rect: Rect2):
	var full_rect = get_viewport().get_visible_rect()
	dim_full.visible = false

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
