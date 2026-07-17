extends Node

# Regression harness for "this worked last time - I died, loaded the saved
# build, and the energy won't route properly now": Energy Intake tiles were
# never included in _serialize_tile/_deserialize_tile's active_faces
# allowlist (only Splitter/Core Reactor/Microcore save it), so a saved/
# named loadout always deserialized the intake back to ComponentLinkTile's
# class-level default (direction 0, East) - EnergyIntakeOrientationCheck.gd
# already proved that default is wrong for shapes like the Left Arm.
# SaveManager._deserialize_component() now re-derives the intake's
# orientation from the actual restored shape instead of relying on
# (never-saved) serialized data. Only calls the pure in-memory
# _serialize_component/_deserialize_component helpers - never save_game/
# load_game, which would touch the real user:// save directory.

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const SaveManagerScript = preload("res://scripts/core/SaveManager.gd")

var failures = 0

func _fail(msg: String):
	push_error("FAIL: " + msg)
	failures += 1

func _round_trip_check(component: ComponentEquipment, label: String, save_mgr):
	var original_intake = component.hex_grid.get_tile(HexCoord.new(0, 0))
	if not original_intake or original_intake.tile_type != "Energy Intake":
		_fail("%s: setup problem, no Energy Intake at (0,0)" % label)
		return
	var original_faces = original_intake.active_faces.duplicate()

	var saved_data = save_mgr._serialize_component(component)
	# Confirm the bug's actual root cause is still true: active_faces is NOT
	# part of what got saved for an Energy Intake (unlike Splitter/Core
	# Reactor/Microcore) - if this ever starts failing, the fix below might
	# be redundant, but it's still correct either way.
	var intake_data = null
	for tdata in saved_data.get("tiles", []):
		if tdata.get("tile_type", "") == "Energy Intake":
			intake_data = tdata
	if intake_data and intake_data.has("active_faces"):
		print("note: %s - Energy Intake active_faces is now part of saved data (fine, orientation is still re-derived defensively)" % label)

	var restored = save_mgr._deserialize_component(saved_data)
	var restored_intake = restored.hex_grid.get_tile(HexCoord.new(0, 0))
	if not restored_intake or restored_intake.tile_type != "Energy Intake":
		_fail("%s: deserialized component has no Energy Intake at (0,0)" % label)
		return

	if restored_intake.active_faces.is_empty():
		_fail("%s: restored intake active_faces is empty after round trip" % label)
	elif restored_intake.active_faces == [0] and not original_faces.has(0):
		_fail("%s: restored intake reverted to the broken [0] default (original was %s)" % [label, str(original_faces)])
	else:
		print("ok: %s intake survives save/load round trip: %s -> %s" % [label, str(original_faces), str(restored_intake.active_faces)])

func _ready():
	var save_mgr = SaveManagerScript.new()
	add_child(save_mgr)

	_round_trip_check(ComponentEquipmentScript.create_starter_arm(true), "L. Arm", save_mgr)
	_round_trip_check(ComponentEquipmentScript.create_starter_head(), "Head", save_mgr)
	_round_trip_check(ComponentEquipmentScript.create_shield_backpack(), "Shield Backpack", save_mgr)

	if failures == 0:
		print("PASS: Energy Intake orientation survives a save/load round trip")
	get_tree().quit(0 if failures == 0 else 1)
