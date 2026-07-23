extends Node

# Regression harness for the "unify menu keys" backlog item (Status.md):
# WarRoomMenu used to be the one menu in the game checking raw
# event.physical_keycode == KEY_TAB/KEY_ESCAPE directly instead of going
# through an InputMap action like every other menu (PauseMenu/SettingsMenu
# both gate on "ui_cancel"). Verifies the runtime-registered "toggle_war_room"
# action actually fires for the physical key it's bound to, and that the
# built-in "ui_cancel" action (bound to Escape by default) does too - the
# two actions WarRoomMenu._input() now checks instead of raw keycodes.
#
# Registration now lives in WarRoomMenu._ready() ITSELF (not Main.gd) -
# playtest caught that a War Room opened from the Main Menu scene (where
# Main.gd never runs) had no toggle_war_room action at all, so Tab
# silently did nothing while Esc worked. This check instantiates the real
# WarRoomMenu to prove ITS _ready() does the registering, wherever it's
# spawned from.

func _ready():
	var failures = 0

	# WarRoomMenu._ready() must register the action itself - no
	# pre-registration mirror here anymore, that would mask a regression.
	var wr = load("res://scripts/ui/WarRoomMenu.gd").new()
	add_child(wr)

	if not InputMap.has_action("toggle_war_room"):
		push_error("FAIL: instantiating WarRoomMenu did not register toggle_war_room")
		failures += 1
	else:
		var tab_event = InputEventKey.new()
		tab_event.physical_keycode = KEY_TAB
		tab_event.pressed = true
		if not tab_event.is_action_pressed("toggle_war_room"):
			push_error("FAIL: Tab keypress doesn't fire toggle_war_room")
			failures += 1
		else:
			print("1) toggle_war_room action registered and fires for Tab")

	if not InputMap.has_action("ui_cancel"):
		push_error("FAIL: built-in ui_cancel action is missing entirely")
		failures += 1
	else:
		var esc_event = InputEventKey.new()
		esc_event.keycode = KEY_ESCAPE # ui_cancel's default binding uses keycode, not physical_keycode
		esc_event.pressed = true
		if not esc_event.is_action_pressed("ui_cancel"):
			push_error("FAIL: Escape keypress doesn't fire ui_cancel")
			failures += 1
		else:
			print("2) built-in ui_cancel fires for Escape (what WarRoomMenu/PauseMenu/SettingsMenu all now share)")

	if failures == 0:
		print("PASS: menu keys unified through real InputMap actions")
	get_tree().quit(0 if failures == 0 else 1)
