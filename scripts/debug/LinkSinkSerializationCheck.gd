extends Node

# Regression harness for the ROOT CAUSE of the "stuff is just bypassing the
# left arm link" playtest report: ComponentLinkTile._init() always
# overwrites tile_type away from its initial "Component Link" value (to
# "Left Arm Link"/"Energy Intake"/etc.) before returning, so no instance
# ever actually has tile_type == "Component Link". Two places keyed on that
# exact (unreachable) string:
#   1. SaveManager._serialize_tile() never captured target_slot/is_fixed for
#      the torso's 5 arm/leg/head Link sink tiles (or Energy Intake) - only
#      Actuator [wrong tile class entirely]/Torso Return/Backpack Link were
#      individually listed by name. On load, target_slot silently defaulted
#      to NONE, which flips ComponentLinkTile.process_energy() from "sink,
#      capture for transfer to the limb" to "router, forward via
#      active_faces" - the tile LOOKS right (tile_type is a separately-saved
#      flat field, so the label was never wrong) but stops actually
#      delivering power to the limb at all.
#   2. ComponentEquipment.update_link_positions() (repositions Link sinks
#      when a torso's shape changes, e.g. a manual-hex/rarity upgrade) never
#      matched anything - a fully silent no-op that also wiped fixed_sinks
#      down to just the Core on every call.
# Both are now gated on the ComponentLinkTile script type instead of the
# impossible string.

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const SaveManagerScript = preload("res://scripts/core/SaveManager.gd")

var failures = 0

func _check(label: String, actual, expected):
	if actual != expected:
		push_error("FAIL: %s - got %s, expected %s" % [label, actual, expected])
		failures += 1
	else:
		print("ok: %s = %s" % [label, actual])

func _ready():
	# --- 1. Save/load round trip preserves target_slot/is_fixed ---
	var save_mgr = SaveManagerScript.new()
	add_child(save_mgr)

	var torso = ComponentEquipmentScript.create_starter_torso()
	var saved = save_mgr._serialize_component(torso)

	var l_arm_data = null
	for tdata in saved["tiles"]:
		if tdata.get("tile_type", "") == "Left Arm Link":
			l_arm_data = tdata
	_check("serialized 'Left Arm Link' includes target_slot", l_arm_data.has("target_slot"), true)
	_check("serialized 'Left Arm Link' target_slot value", int(l_arm_data.get("target_slot", -1)), HexTile.BodySlot.ARM_L)
	_check("serialized 'Left Arm Link' is_fixed value", bool(l_arm_data.get("is_fixed", false)), true)

	var restored = save_mgr._deserialize_component(saved)
	var restored_link = null
	for t in restored.hex_grid.get_all_tiles():
		if t.tile_type == "Left Arm Link":
			restored_link = t
	_check("restored 'Left Arm Link' keeps target_slot == ARM_L (not reset to NONE)",
		restored_link.get("target_slot"), HexTile.BodySlot.ARM_L)
	_check("restored 'Left Arm Link' keeps is_fixed == true",
		restored_link.get("is_fixed"), true)

	# The actual functional consequence: a sink (target_slot != NONE) must
	# NOT behave like a router (get_exit_directions returns [] for a sink,
	# vs. active_faces for a router).
	_check("restored 'Left Arm Link' still behaves as a terminal sink, not a router",
		restored_link.get_exit_directions().is_empty(), true)

	# --- 2. update_link_positions() actually repositions sinks now ---
	var torso2 = ComponentEquipmentScript.create_starter_torso()
	torso2.rarity = HexTile.Rarity.LEGENDARY
	torso2.generate_shape() # bigger shape at Legendary -> different min_q/max_q/etc.
	torso2.update_link_positions()

	var min_q = 0
	for h in torso2.valid_hexes:
		if h.q < min_q: min_q = h.q
	var repositioned_l_arm = torso2.hex_grid.get_tile(HexCoord.new(min_q, 0))
	_check("update_link_positions() actually moved 'Left Arm Link' to the new shape's min_q edge",
		repositioned_l_arm != null and repositioned_l_arm.tile_type == "Left Arm Link", true)
	_check("update_link_positions() rebuilt fixed_sinks with more than just the Core",
		torso2.fixed_sinks.size() > 1, true)

	if failures == 0:
		print("PASS: ComponentLinkTile sink tiles survive save/load and update_link_positions() actually repositions them")
	get_tree().quit(0 if failures == 0 else 1)
