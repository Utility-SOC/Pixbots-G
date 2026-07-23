extends Node

# Regression harness for: "you should be able to click outside of the hex
# grid, as well as outside of the current hex grid popup windows (like the
# menu to adjust a splitter) - if I click somewhere that is neither the hex
# grid, or the popup window, it should close that popup window."
#
# GarageTileConfigPopup._show_popup() wires every one of its 11 tile-config
# popups (Core Reactor, Splitter/Accessory Return, Catalyst, Microcore,
# Weapon Mount/Jumpjet/Amplifier/Conduit/Shield/Actuator, Jammer Module,
# Magnet, Drone Bay, Accumulator, Filter, Infuser) to Window.focus_exited ->
# hide() -> popup_hide -> queue_free(). Can't simulate a real mouse click
# moving focus in headless mode, but focus_exited is a real Window signal -
# this verifies the wiring is actually connected and that emitting it
# (exactly what a genuine outside click does) drives the popup through its
# full close-and-free sequence.
#
# ALSO covers the regression this same wiring caused once Accumulator's
# config popup got its own OptionButtons (trigger key / auto-dump): opening
# an OptionButton's internal dropdown (itself a child Window/PopupMenu)
# fires focus_exited on the PARENT popup too - the original synchronous
# hide() closed the whole Accumulator popup before the player could ever
# pick an option ("I can no longer click anything in the accumulator
# menu"). The fix defers the hide by a frame and only actually closes if
# none of the popup's own children currently have a visible popup of their
# own - see cases 2/3 below for the direct test of that logic.

const GarageMenuScript = preload("res://scripts/ui/GarageMenu.gd")
const GarageTileConfigPopupScript = preload("res://scripts/ui/GarageTileConfigPopup.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var garage = GarageMenuScript.new()
	add_child(garage)
	var helper = GarageTileConfigPopupScript.new(garage)

	# --- 1. Plain popup (no child dropdown) closes on a genuine outside click ---
	var popup = PopupPanel.new()
	popup.add_child(Label.new())
	helper._show_popup(popup, Vector2(250, 100))

	_check("_show_popup actually adds the popup under the garage", popup.get_parent() == garage)
	_check("focus_exited is connected (the outside-click-closes wiring)",
		popup.focus_exited.get_connections().size() > 0)
	_check("popup starts visible", popup.visible)

	# Emitting focus_exited is exactly what a genuine click elsewhere
	# produces on a real Window - drive it and confirm the full chain fires.
	# The hide is now deferred a frame (see _show_popup's own comment), but
	# hide() -> popup_hide -> queue_free() all resolve within that SAME
	# awaited frame (queue_free's actual deletion isn't a further frame
	# behind it) - so one await is enough, and the only safe thing to check
	# afterward is the end state (freed), not an intermediate .visible read,
	# since the node may already be gone.
	popup.focus_exited.emit()
	await get_tree().process_frame
	_check("emitting focus_exited (no child popup open) closes and frees the popup",
		not is_instance_valid(popup))

	# --- 2. A popup with a visible child Window (an open OptionButton
	# dropdown, stood in for directly since headless mode can't actually
	# click one open) does NOT close on focus_exited - this is the exact
	# bug: opening the dropdown itself fires focus_exited on the parent. ---
	var popup2 = PopupPanel.new()
	var opt = OptionButton.new()
	opt.add_item("A")
	opt.add_item("B")
	popup2.add_child(opt)
	helper._show_popup(popup2, Vector2(250, 100))

	var dropdown = opt.get_popup()
	dropdown.visible = true # simulates the dropdown being open, as a real click would leave it

	popup2.focus_exited.emit()
	await get_tree().process_frame
	_check("popup stays open while its own OptionButton dropdown is visible (the actual bug)",
		popup2.visible)

	# --- 3. Once the dropdown closes (selection made / cancelled), the SAME
	# popup closes normally on the next real outside click. ---
	dropdown.visible = false
	popup2.focus_exited.emit()
	await get_tree().process_frame
	_check("the same popup closes and frees normally once its dropdown is no longer visible",
		not is_instance_valid(popup2))

	garage.queue_free()
	await get_tree().process_frame
	if failures == 0:
		print("PASS: Garage tile-config popups close on a genuine outside click, but not while one of their own child dropdowns (OptionButton, etc.) is open")
	get_tree().quit(0 if failures == 0 else 1)
