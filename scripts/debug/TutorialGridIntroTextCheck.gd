extends Node

# Playtest report: "The tutorial isn't explaining what to do other than
# just highlighting the grid - not even text running to explain the
# strange orange rectangle." Reproduces the "grid_intro" step (the first
# spotlight-only step, anchored to "tutorial:grid_panel", requires_garage)
# against a realistic stub - mirrors TutorialGuidedBuildIntegrationCheck.gd's
# harness pattern - and inspects whether the instruction panel/text
# actually ends up visible on screen, not just whether the highlight box
# (highlight_border) shows.

const TutorialManagerScript = preload("res://scripts/ui/TutorialManager.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

class GarageStub:
	extends Control

class MainStub:
	extends Node
	var garage_ui = null
	func _open_garage():
		garage_ui = GarageStub.new()

func _ready():
	SaveManager.tutorial_completed = false
	# Headless default viewport is tiny (64x64) - force a realistic window
	# size so on-screen-position checks below mean something (a panel that's
	# "in bounds" of a 64x64 test viewport proves nothing about a real
	# 1920x1080 game window).
	get_tree().root.size = Vector2i(1920, 1080)

	var main_stub = MainStub.new()
	add_child(main_stub)

	# The real grid_panel Control (GarageUIBuilder.gd:99 registers this same
	# group on the actual Garage's grid area) - sized/positioned like a
	# realistic on-screen panel, added to the tree so is_visible_in_tree()
	# is true, matching a real running game.
	var grid_panel = Control.new()
	add_child(grid_panel)
	grid_panel.position = Vector2(20, 120)
	grid_panel.size = Vector2(1000, 800)
	grid_panel.add_to_group("tutorial:grid_panel")

	var tm = TutorialManagerScript.new()
	main_stub.add_child(tm)
	await get_tree().process_frame
	tm._load_steps()
	if not tm.root:
		tm._build_ui()
	tm.is_active = true
	tm._goto_step(0)

	_check("steps loaded from the real tutorial.json", not tm.steps.is_empty())

	var target_index = -1
	for i in range(tm.steps.size()):
		if str(tm.steps[i].get("id", "")) == "grid_intro":
			target_index = i
			break
	_check("tutorial.json contains 'grid_intro'", target_index >= 0)
	if target_index < 0:
		get_tree().quit(1)
		return

	tm._goto_step(target_index)
	# _goto_step -> _render_dialogue_step -> _update_spotlight, all
	# synchronous - but _update_spotlight's dirty-check compares against
	# _last_spotlight_sig from BEFORE this step, so give it one real frame
	# the way the live game would, then force a second pass in case the
	# very first _process() this frame is what actually resolves the anchor.
	await get_tree().process_frame
	tm._update_spotlight()

	_check("_ensure_in_garage actually opened the garage (garage_ui set)", main_stub.garage_ui != null)
	_check("text_label.text is the real grid_intro copy, not empty", tm.text_label.text == str(tm.steps[target_index]["text"]))
	_check("panel.visible is true (not stuck waiting for the anchor)", tm.panel.visible)
	_check("corner_hint.visible is false (no fallback text shown instead)", not tm.corner_hint.visible)
	_check("highlight_border is visible (the spotlight rectangle itself)", tm.highlight_border.visible)

	# The bug report is specifically that the highlight shows but no text
	# does - so also check the panel's actual computed on-screen rect isn't
	# degenerate (zero size / off-screen), which visible=true alone doesn't
	# rule out if _reposition_panel's math is wrong.
	await get_tree().process_frame # let the VBoxContainer layout settle
	var panel_rect = tm.panel.get_global_rect()
	_check("panel has non-zero on-screen size (%s)" % panel_rect, panel_rect.size.x > 10 and panel_rect.size.y > 10)
	var viewport_rect = tm.get_viewport().get_visible_rect()
	_check("panel is actually within the viewport, not positioned off-screen (%s vs viewport %s)" % [panel_rect, viewport_rect],
		viewport_rect.intersects(panel_rect))
	_check("text_label itself is visible in the tree (not hidden by an ancestor)", tm.text_label.is_visible_in_tree())

	if failures == 0:
		print("PASS: grid_intro step shows real instruction text alongside the spotlight, not just the bare highlight")
	get_tree().quit(0 if failures == 0 else 1)
