extends Node

# Regression check for: user, 2026-08-13 - "how do I choose what [my Prime
# Circuit is] infusing?" - a real, confirmed bug, not user error.
#
# PrimeCircuitTile.gd (Prime Circuits' Mythic Corporate Sponsorship tile -
# an Amplifier + Elemental Infuser + Resonator combined into one hex) has a
# fully working secondary_synergy field plus cycle_synergy()/
# cycle_synergy_backward() methods - the exact same mechanism a standalone
# Elemental Infuser tile uses. But GarageTileConfigPopup.on_tile_clicked's
# dispatch that opens the "Configure Synergy" popup only checked
# tile_type == "Elemental Infuser"/"Catalyst"/"Structural Strut" - never
# "Prime Circuit" - so clicking a placed Prime Circuit tile in the Garage
# never opened any way to actually change what it infuses. The mechanic
# was real and simulated correctly; it just had no UI control anywhere.
#
# Same safe construction pattern PopupClickOutsideCheck.gd already
# established for GarageTileConfigPopup testing.

const GarageMenuScript = preload("res://scripts/ui/GarageMenu.gd")
const GarageTileConfigPopupScript = preload("res://scripts/ui/GarageTileConfigPopup.gd")
const PrimeCircuitTileScript = preload("res://scripts/tiles/brands/PrimeCircuitTile.gd")

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

	var tile = PrimeCircuitTileScript.new()
	tile.rarity = HexTile.Rarity.MYTHIC
	_check("a fresh Prime Circuit starts unconfigured (secondary_synergy == RAW, pure pass-through)",
		tile.secondary_synergy == EnergyPacket.SynergyType.RAW)

	var before_children = garage.get_child_count()
	helper.on_tile_clicked(tile)
	_check("clicking a placed Prime Circuit tile now opens a real config popup (it silently did nothing before this fix)",
		garage.get_child_count() > before_children)

	var popup = garage.get_child(garage.get_child_count() - 1)
	_check("the opened popup is a PopupPanel", popup is PopupPanel)

	# Find the Synergy button the same way a player would interact with it -
	# walk the popup's own children rather than assuming a fixed index, so
	# this doesn't silently break if GarageTileConfigPopup's layout changes.
	var synergy_btn: Button = null
	if popup is PopupPanel:
		for child in popup.get_children():
			for grandchild in child.get_children():
				if grandchild is Button and str(grandchild.text).begins_with("Synergy:"):
					synergy_btn = grandchild
	_check("the popup contains a real 'Synergy: ...' button, same as the standalone Elemental Infuser's own popup",
		synergy_btn != null)

	if synergy_btn:
		var fake_click = InputEventMouseButton.new()
		fake_click.button_index = MOUSE_BUTTON_LEFT
		fake_click.pressed = true
		synergy_btn.gui_input.emit(fake_click)
		_check("left-clicking the Synergy button actually cycles secondary_synergy off of RAW - the real, previously-unreachable control",
			tile.secondary_synergy != EnergyPacket.SynergyType.RAW)

		var after_first_cycle = tile.secondary_synergy
		var fake_right_click = InputEventMouseButton.new()
		fake_right_click.button_index = MOUSE_BUTTON_RIGHT
		fake_right_click.pressed = true
		synergy_btn.gui_input.emit(fake_right_click)
		_check("right-clicking cycles backward to a different value (same forward/backward convention as Elemental Infuser's own popup)",
			tile.secondary_synergy != after_first_cycle)

	if failures == 0:
		print("PASS: Prime Circuit's config popup is now reachable in the Garage, exposing the same working Synergy-cycling control the tile already had in simulation")
	get_tree().quit(0 if failures == 0 else 1)
