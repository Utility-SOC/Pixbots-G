extends Node

# Licensing/disclosure follow-up: DISCLOSURES.md documents obligations
# (Godot Engine MIT notice, godot-rust MPL-2.0 disclosure) but nothing in
# the actual game surfaced them to players. This verifies the Main Menu's
# "Credits & Licenses" button opens a panel that actually names both.

const MainMenuScript = preload("res://scripts/ui/MainMenu.gd")
const CreditsPanelScript = preload("res://scripts/ui/CreditsPanel.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var menu = MainMenuScript.new()
	add_child(menu)

	var credits_btn = null
	for child in _all_descendants(menu):
		if child is Button and child.text == "Credits & Licenses":
			credits_btn = child
			break
	_check("Main Menu has a 'Credits & Licenses' button", credits_btn != null)

	if credits_btn:
		credits_btn.pressed.emit()

	var panel = null
	for child in menu.get_children():
		if child.get_script() == CreditsPanelScript:
			panel = child
			break
	_check("pressing the button opens a CreditsPanel", panel != null)

	if panel:
		_check("credits mention Godot Engine (MIT)", "Godot Engine" in panel.CREDITS_TEXT and "MIT" in panel.CREDITS_TEXT)
		_check("credits mention godot-rust/gdext (MPL-2.0)", "godot-rust" in panel.CREDITS_TEXT and "MPL-2.0" in panel.CREDITS_TEXT)

		var close_btn = null
		for child in _all_descendants(panel):
			if child is Button and child.text == "Close":
				close_btn = child
				break
		_check("panel has a Close button", close_btn != null)
		if close_btn:
			close_btn.pressed.emit()
			await get_tree().process_frame
			_check("Close button frees the panel", not is_instance_valid(panel))

	if failures == 0:
		print("PASS: Main Menu surfaces Godot Engine + godot-rust license disclosures to players")
	get_tree().quit(0 if failures == 0 else 1)

func _all_descendants(node: Node) -> Array:
	var result = []
	for child in node.get_children():
		result.append(child)
		result.append_array(_all_descendants(child))
	return result
