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

	var popup = PopupPanel.new()
	popup.add_child(Label.new())
	helper._show_popup(popup, Vector2(250, 100))

	_check("_show_popup actually adds the popup under the garage", popup.get_parent() == garage)
	_check("focus_exited is connected (the outside-click-closes wiring)",
		popup.focus_exited.get_connections().size() > 0)
	_check("popup starts visible", popup.visible)

	# Emitting focus_exited is exactly what a genuine click elsewhere
	# produces on a real Window - drive it and confirm the full chain fires.
	popup.focus_exited.emit()
	_check("emitting focus_exited hides the popup", not popup.visible)

	await get_tree().process_frame
	_check("hiding the popup (via popup_hide) frees it, same as Esc/any other dismissal",
		not is_instance_valid(popup))

	garage.queue_free()
	if failures == 0:
		print("PASS: every Garage tile-config popup closes when focus moves elsewhere (click outside grid+popup)")
	get_tree().quit(0 if failures == 0 else 1)
