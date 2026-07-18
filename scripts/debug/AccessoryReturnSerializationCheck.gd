extends Node

# Regression harness for a second, distinct cause of "stuff is just
# bypassing the left arm link": Accessory Return tiles (the torso-side
# router that receives energy returned from the Head/Backpack, player-
# configurable via the exact same face-toggle popup as Splitter - see
# GarageTileConfigPopup.gd's dispatch: tile_type == "Splitter" or
# "Accessory Return") never had their active_faces captured by
# SaveManager._serialize_tile() at all. Every load silently reset a
# player-configured Accessory Return back to the class default
# active_faces=[0] (East only), discarding whatever routing direction(s)
# they'd actually set up - which could easily be the specific link in a
# chain that fed power toward the left side of the torso.
#
# Also checks the has()-guard on the deserialize side: an old, pre-fix save
# has no "active_faces" key for Accessory Return, and must fall back to the
# tile's freshly-constructed default instead of being wiped to a fully
# empty array (worse than the original bug - process_energy's
# split_count==0 branch just passes the packet through unmodified).

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const SaveManagerScript = preload("res://scripts/core/SaveManager.gd")

var failures = 0

func _check(label: String, actual, expected):
	if actual != expected:
		push_error("FAIL: %s - got %s, expected %s" % [label, actual, expected])
		failures += 1
	else:
		print("ok: %s = %s" % [label, actual])

func _find_accessory_return(comp):
	for tile in comp.hex_grid.get_all_tiles():
		if tile.tile_type == "Accessory Return":
			return tile
	return null

func _ready():
	var save_mgr = SaveManagerScript.new()
	add_child(save_mgr)

	# --- 1. Player-configured active_faces survives a save/load round trip ---
	var torso = ComponentEquipmentScript.create_starter_torso()
	var acc_return = _find_accessory_return(torso)
	var custom_faces: Array[int] = [2, 3]
	acc_return.active_faces = custom_faces

	var saved = save_mgr._serialize_component(torso)
	var acc_data = null
	for tdata in saved["tiles"]:
		if tdata.get("tile_type", "") == "Accessory Return":
			acc_data = tdata
	_check("serialized data now includes active_faces for Accessory Return", acc_data.has("active_faces"), true)

	var restored = save_mgr._deserialize_component(saved)
	var restored_acc = _find_accessory_return(restored)
	_check("restored Accessory Return keeps the player-configured active_faces (not reset to [0])",
		restored_acc.active_faces, custom_faces)

	# --- 2. Old-save fallback: no active_faces key -> keep the class default, not empty ---
	var legacy_data = acc_data.duplicate()
	legacy_data.erase("active_faces")
	var legacy_restored_data = saved.duplicate(true)
	for tdata in legacy_restored_data["tiles"]:
		if tdata.get("tile_type", "") == "Accessory Return":
			tdata.erase("active_faces")
	var legacy_restored = save_mgr._deserialize_component(legacy_restored_data)
	var legacy_acc = _find_accessory_return(legacy_restored)
	_check("a pre-fix save (no active_faces key) falls back to the class default [0], not an empty array",
		legacy_acc.active_faces, [0])

	if failures == 0:
		print("PASS: Accessory Return active_faces survives save/load, with a safe legacy-save fallback")
	get_tree().quit(0 if failures == 0 else 1)
