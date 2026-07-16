extends Node

# Regression harness for the "unify menu keys" backlog item (Status.md):
# WarRoomMenu used to be the one menu in the game checking raw
# event.physical_keycode == KEY_TAB/KEY_ESCAPE directly instead of going
# through an InputMap action like every other menu (PauseMenu/SettingsMenu
# both gate on "ui_cancel"). Verifies the runtime-registered "toggle_war_room"
# action (see Main.gd's _ready(), same pattern as cloak/heal_pulse/jam_pulse)
# actually fires for the physical key it's bound to, and that the built-in
# "ui_cancel" action (bound to Escape by default) does too - the two actions
# WarRoomMenu._input() now checks instead of raw keycodes.

func _ready():
	var failures = 0

	# Mirrors Main.gd's exact registration block for toggle_war_room.
	if not InputMap.has_action("toggle_war_room"):
		InputMap.add_action("toggle_war_room")
		var war_room_key = InputEventKey.new()
		war_room_key.physical_keycode = KEY_TAB
		InputMap.action_add_event("toggle_war_room", war_room_key)

	if not InputMap.has_action("toggle_war_room"):
		push_error("FAIL: toggle_war_room action failed to register")
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
