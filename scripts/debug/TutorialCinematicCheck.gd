extends Node

# Regression harness for: "Evan cinematics should be used for most of the
# tutorial phases." TutorialManager steps with "type": "cinematic" run a
# real CutscenePlayer instead of the plain spotlight/text panel, and fall
# back to the plain panel if the referenced cutscene file is missing -
# unlike the optional between-wave cutscenes, a tutorial step is mandatory
# content and must never silently vanish.

const TutorialManagerScript = preload("res://scripts/ui/TutorialManager.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var saved_completed = SaveManager.tutorial_completed
	SaveManager.tutorial_completed = false

	var tm = TutorialManagerScript.new()
	add_child(tm)
	tm._process(0.016) # drive one tick manually (same pattern as CutsceneCheck.gd's _drive) rather than depending on frame-scheduling timing

	_check("real tutorial.json's step 0 ('welcome') is a cinematic step",
		tm.steps.size() > 0 and str(tm.steps[0].get("type", "")) == "cinematic")

	_check("TutorialManager._ready() started on step 0 and launched the cinematic",
		tm.step_index == 0 and tm._active_cutscene != null and is_instance_valid(tm._active_cutscene))

	_check("the menu's own panel/spotlight stay hidden while the cutscene plays",
		not tm.panel.visible)

	_check("escape_button is hidden while a cutscene plays (no overlapping skip affordances)",
		not tm.escape_button.visible)

	# Finishing the cutscene must advance the outer tutorial exactly like a
	# manual Next click would - skip() is the same path a player's Esc uses.
	var cutscene = tm._active_cutscene
	cutscene.skip()
	_check("cutscene.skip() advances TutorialManager to the next step (1, grid_intro) and clears _active_cutscene",
		tm.step_index == 1 and tm._active_cutscene == null)
	# step 1 (grid_intro) anchors to a real Garage UI group that doesn't
	# exist in this bare test scene, so it correctly shows corner_hint
	# instead of the full panel (see _update_spotlight's "waiting_for_screen"
	# path) - already covered by TutorialAnchorsCheck.gd; nothing further to
	# assert here beyond _active_cutscene already being cleared above.

	tm.queue_free()
	await get_tree().process_frame

	# --- Fallback: a cinematic step whose cutscene file doesn't exist must
	# degrade to the plain text panel, not skip/vanish silently. Let the
	# real _ready() run first (needs to be in the tree before _goto_step can
	# call get_viewport()/get_tree() safely), skip its real welcome
	# cinematic, THEN swap in the fallback-test step. -----------------------
	var tm2 = TutorialManagerScript.new()
	add_child(tm2)
	await get_tree().process_frame
	if tm2._active_cutscene:
		tm2._active_cutscene.skip()

	tm2.steps = [
		{"id": "missing_cutscene_test", "type": "cinematic", "cutscene": "does_not_exist_at_all.json",
			"text": "Fallback text should show.", "anchor": "", "wait_for": "manual"},
	]
	tm2._goto_step(0)

	_check("a missing cutscene file falls back to the plain text panel instead of vanishing",
		tm2._active_cutscene == null and tm2.panel.visible and tm2.text_label.text == "Fallback text should show.")
	_check("the fallback panel's Next button is usable (not stuck waiting on a cutscene that never started)",
		tm2.next_button.visible)

	tm2.queue_free()

	SaveManager.tutorial_completed = saved_completed

	if failures == 0:
		print("PASS: cinematic tutorial steps run a real CutscenePlayer, advance the sequence on finish, and fall back safely if the file is missing")
	get_tree().quit(0 if failures == 0 else 1)
