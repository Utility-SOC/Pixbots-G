extends Node

# Regression check for: "it is hard to know what is a head, a foot, or an
# arm with it labelled like this" (2026-08-10 screenshot - a squad's Torso/
# Arm/Head tabs read "Boss 1 Dr...", "Boss 2 Dr...", "Salvaged ...", each
# truncated to the equipped component's own loot-origin name instead of
# which body slot it actually filled; only the two tabs whose loot never
# got replaced - default component_names happen to equal their slot name
# by convention - read correctly, which is what made the bug easy to miss).
#
# Root cause: GarageMenu._populate_component_tabs() used comp.component_
# name (whatever the equipped loot happens to be named) as the tab's
# TITLE. Fixed to always use the canonical _slot_display_name(slot)
# instead - the loot's own name is still surfaced as the tab's tooltip
# rather than dropped.

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
	torso.component_name = "Boss 1 Drone Wreckage" # a real loot-origin name, unrelated to "Torso"
	var l_arm = ComponentEquipmentScript.create_starter_arm(true)
	l_arm.component_name = "Salvaged Uncommon Plating"
	var r_leg = ComponentEquipmentScript.create_starter_leg(false)
	# r_leg keeps its default component_name ("R. Leg") - this is the case
	# that made the original bug easy to miss, since it happened to read
	# correctly even though it was using the wrong field.

	var garage = GarageMenuScript.new()
	add_child(garage)
	garage.mech_components = {
		HexTile.BodySlot.TORSO: torso,
		HexTile.BodySlot.ARM_L: l_arm,
		HexTile.BodySlot.LEG_R: r_leg,
	}
	garage.component_tabs = TabBar.new()
	garage.add_child(garage.component_tabs)
	garage.grid_renderer = GarageGridRendererScript.new()
	garage.add_child(garage.grid_renderer)
	garage.stats_label = Label.new()
	garage.add_child(garage.stats_label)

	garage._populate_component_tabs()

	var torso_idx = -1
	var arm_idx = -1
	var leg_idx = -1
	for i in range(garage.component_tabs.get_tab_count()):
		var meta = garage.component_tabs.get_tab_metadata(i)
		if meta == HexTile.BodySlot.TORSO: torso_idx = i
		elif meta == HexTile.BodySlot.ARM_L: arm_idx = i
		elif meta == HexTile.BodySlot.LEG_R: leg_idx = i

	_check("a Torso tab exists", torso_idx >= 0)
	_check("a looted Torso's tab TITLE is the canonical slot name, not its loot name",
		garage.component_tabs.get_tab_title(torso_idx) == GarageMenuScript._slot_display_name(HexTile.BodySlot.TORSO))
	_check("the looted Torso's own name is still available as the tab's tooltip",
		garage.component_tabs.get_tab_tooltip(torso_idx) == "Boss 1 Drone Wreckage")

	_check("a Left Arm tab exists", arm_idx >= 0)
	_check("a looted Left Arm's tab TITLE is the canonical slot name, not its loot name",
		garage.component_tabs.get_tab_title(arm_idx) == GarageMenuScript._slot_display_name(HexTile.BodySlot.ARM_L))
	_check("the looted Left Arm's own name is still available as the tab's tooltip",
		garage.component_tabs.get_tab_tooltip(arm_idx) == "Salvaged Uncommon Plating")

	_check("a Right Leg tab exists", leg_idx >= 0)
	_check("a Right Leg whose loot name coincidentally matched its slot still shows the canonical slot name",
		garage.component_tabs.get_tab_title(leg_idx) == GarageMenuScript._slot_display_name(HexTile.BodySlot.LEG_R))

	if failures == 0:
		print("PASS: component tabs always show the canonical body-slot name, regardless of what loot is equipped there, with the loot's own name preserved as a tooltip")
	get_tree().quit(0 if failures == 0 else 1)
