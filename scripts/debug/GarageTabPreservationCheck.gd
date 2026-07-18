extends Node

# Regression harness for: "I cannot upgrade any components except the
# torso - I pop to the torso every time I try to upgrade anything else."
#
# Root cause: TileActionMenu.upgrade_part()/extract_modifier()/
# infuse_chip() (and Swap Component) all call GarageMenu._refresh_
# component_ui() afterward, which calls _populate_component_tabs() -
# which unconditionally selected tab 0 (always Torso, per slot_order)
# once it finished rebuilding the tab strip. The upgrade itself applied
# correctly to whatever was actually active; the VIEW then snapped back
# to Torso right after, making it look like only Torso could ever be
# upgraded. _populate_component_tabs() now restores whatever was
# selected before the rebuild instead.

const GarageMenuScript = preload("res://scripts/ui/GarageMenu.gd")
const GarageGridRendererScript = preload("res://scripts/ui/GarageGridRenderer.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var torso = ComponentEquipmentScript.create_starter_torso()
	var l_arm = ComponentEquipmentScript.create_starter_arm(true)

	var garage = GarageMenuScript.new()
	add_child(garage)
	garage.mech_components = {HexTile.BodySlot.TORSO: torso, HexTile.BodySlot.ARM_L: l_arm}
	garage.component_tabs = TabBar.new()
	garage.add_child(garage.component_tabs)
	garage.grid_renderer = GarageGridRendererScript.new()
	garage.add_child(garage.grid_renderer)
	garage.stats_label = Label.new()
	garage.add_child(garage.stats_label)

	# Initial population (mirrors _ready()'s call) - lands on tab 0 (Torso),
	# same as a fresh Garage open always should.
	garage._populate_component_tabs()
	_check("fresh population defaults to Torso (tab 0)", garage.active_component.slot_type == HexTile.BodySlot.TORSO)

	# Switch to the Left Arm, exactly like clicking its tab or its diagram slot.
	var arm_tab_index = -1
	for i in range(garage.component_tabs.get_tab_count()):
		if garage.component_tabs.get_tab_metadata(i) == HexTile.BodySlot.ARM_L:
			arm_tab_index = i
	garage.component_tabs.current_tab = arm_tab_index
	garage._on_tab_changed(arm_tab_index)
	_check("switching to the Left Arm tab actually selects it", garage.active_component.slot_type == HexTile.BodySlot.ARM_L)

	# The exact call every Upgrade/Extract/Infuse/Swap action makes afterward.
	garage._refresh_component_ui()

	_check("after _refresh_component_ui() (upgrade/extract/infuse's follow-up call), the view STAYS on the Left Arm",
		garage.active_component.slot_type == HexTile.BodySlot.ARM_L)
	_check("the TabBar's own visual selection matches (not just the backing state)",
		garage.component_tabs.get_tab_metadata(garage.component_tabs.current_tab) == HexTile.BodySlot.ARM_L)

	if failures == 0:
		print("PASS: upgrading/extracting/infusing a non-torso component no longer snaps the view back to Torso")
	get_tree().quit(0 if failures == 0 else 1)
