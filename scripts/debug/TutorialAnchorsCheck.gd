extends Node

# Regression harness for the deepened Garage onboarding (component tabs,
# tile configuration, Test Range) - per the user: "you have to know how the
# game works... for it to be playable," scoped down to "deepen the Garage
# steps" specifically. Verifies tutorial.json still parses, every step has
# the required fields, and every named anchor actually corresponds to a
# real "tutorial:<name>" group tag somewhere in the Garage UI source -
# guards against a step silently pointing at a spotlight that can never
# resolve (TutorialManager just... never highlights anything, with no error).

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var f = FileAccess.open("res://tutorial.json", FileAccess.READ)
	_check("tutorial.json exists and opened", f != null)
	if f == null:
		get_tree().quit(1)
		return
	var text = f.get_as_text()
	f.close()

	var parsed = JSON.parse_string(text)
	_check("tutorial.json is valid JSON", parsed != null)
	if parsed == null:
		get_tree().quit(1)
		return

	var steps = parsed.get("steps", [])
	_check("has at least as many steps as before this pass (14, was 10)", steps.size() >= 14)

	var ids = {}
	var required_fields = ["id", "text", "anchor", "wait_for"]
	for s in steps:
		for field in required_fields:
			_check("step '%s' has field '%s'" % [s.get("id", "?"), field], s.has(field))
		var id = s.get("id", "")
		_check("step id '%s' is unique" % id, not ids.has(id))
		ids[id] = true

	# The new steps this pass specifically added.
	for expected_id in ["component_tabs", "test_range", "guided_build_torso_run", "switch_to_arm", "guided_build_arm_run"]:
		_check("new step '%s' is present" % expected_id, ids.has(expected_id))

	# The two guided_build steps must actually be typed as such, and target
	# the right body slots.
	var by_id = {}
	for s in steps:
		by_id[s.get("id", "")] = s
	_check("guided_build_torso_run has type 'guided_build' targeting TORSO",
		by_id.get("guided_build_torso_run", {}).get("type", "") == "guided_build" and
		by_id.get("guided_build_torso_run", {}).get("slot", "") == "TORSO")
	_check("guided_build_arm_run has type 'guided_build' targeting ARM_L",
		by_id.get("guided_build_arm_run", {}).get("type", "") == "guided_build" and
		by_id.get("guided_build_arm_run", {}).get("slot", "") == "ARM_L")

	# Cross-check every non-empty anchor against real "tutorial:<name>"
	# group tags declared in the Garage UI source (grep-equivalent: read the
	# builder file and confirm the exact string literal appears).
	var builder_source = FileAccess.get_file_as_string("res://scripts/ui/GarageUIBuilder.gd")
	for s in steps:
		var anchor: String = s.get("anchor", "")
		if anchor == "":
			continue
		_check("anchor '%s' (step '%s') has a matching add_to_group() call in GarageUIBuilder.gd" % [anchor, s.get("id", "?")],
			builder_source.contains('"%s"' % anchor))

	if failures == 0:
		print("PASS: tutorial.json is well-formed and every anchor resolves to a real UI group")
	get_tree().quit(0 if failures == 0 else 1)
