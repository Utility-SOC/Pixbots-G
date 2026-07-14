extends Node

# Regression harness for the named, unlimited build/part save slots
# (SaveManager.save_named_loadout & friends). Round-trips a full build and
# a single part through user://loadouts/ and verifies listing, slot-type
# scoping, and the delete guard.
#
# user:// IS the real save directory - every file this check writes uses a
# __check__ name and is deleted before exit, pass or fail.

const MechScript = preload("res://scripts/entities/Mech.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const WeaponMountTileScript = preload("res://scripts/tiles/WeaponMountTile.gd")

const BUILD_NAME = "__check__ full build"
const PART_NAME = "__check__ torso part"

func _cleanup():
	for entry in SaveManager.list_named_loadouts():
		if str(entry.name).begins_with("__check__"):
			SaveManager.delete_named_loadout(entry.path)
	for slot_type in HexTile.BodySlot.values():
		for entry in SaveManager.list_named_components(slot_type):
			if str(entry.name).begins_with("__check__"):
				SaveManager.delete_named_loadout(entry.path)

func _ready():
	var failures = 0
	var world = Node2D.new()
	add_child(world)
	_cleanup() # a previous crashed run may have left files behind

	# --- mech A: default kit plus one extra torso mount to fingerprint it ---
	var mech_a = MechScript.new()
	mech_a.is_player = true
	world.add_child(mech_a)
	mech_a.set_physics_process(false)
	var torso_a = mech_a.components[HexTile.BodySlot.TORSO]
	var mount = WeaponMountTileScript.new()
	mount.rarity = HexTile.Rarity.RARE
	mount.body_slot = HexTile.BodySlot.TORSO
	var mount_hex = ComponentEquipmentScript._first_free_hex(torso_a, [HexCoord.new(0, 0)])
	torso_a.hex_grid.add_tile(mount_hex, mount)
	var slots_a = mech_a.components.keys()
	slots_a.sort()

	# 1. Save + list a named full build.
	if not SaveManager.save_named_loadout(BUILD_NAME, mech_a):
		push_error("FAIL: save_named_loadout returned false")
		failures += 1
	var found_path = ""
	for entry in SaveManager.list_named_loadouts():
		if entry.name == BUILD_NAME:
			found_path = entry.path
	if found_path == "":
		push_error("FAIL: saved build missing from list_named_loadouts")
		failures += 1
	else:
		print("1) named build saved and listed: ", found_path)

	# 2. Load it onto a second mech - same slots, fingerprint mount present.
	var mech_b = MechScript.new()
	mech_b.is_player = true
	world.add_child(mech_b)
	mech_b.set_physics_process(false)
	if not SaveManager.load_loadout_file(found_path, mech_b):
		push_error("FAIL: load_loadout_file returned false")
		failures += 1
	var slots_b = mech_b.components.keys()
	slots_b.sort()
	var torso_b = mech_b.components.get(HexTile.BodySlot.TORSO)
	var mount_back = torso_b and torso_b.hex_grid.has_tile(mount_hex) and torso_b.hex_grid.get_tile(mount_hex).tile_type == mount.tile_type
	if slots_b != slots_a or not mount_back:
		push_error("FAIL: round-tripped build differs (slots %s vs %s, mount_back=%s)" % [str(slots_b), str(slots_a), str(mount_back)])
		failures += 1
	else:
		print("2) full build round-trip intact (%d slots, fingerprint mount back)" % slots_b.size())

	# 3. Part slots: save the torso, confirm it lists ONLY under torso.
	if not SaveManager.save_named_component(PART_NAME, torso_a):
		push_error("FAIL: save_named_component returned false")
		failures += 1
	var part_path = ""
	for entry in SaveManager.list_named_components(HexTile.BodySlot.TORSO):
		if entry.name == PART_NAME:
			part_path = entry.path
	var leaked = false
	for entry in SaveManager.list_named_components(HexTile.BodySlot.HEAD):
		if entry.name == PART_NAME:
			leaked = true
	if part_path == "" or leaked:
		push_error("FAIL: part listing wrong (torso hit=%s, leaked into head list=%s)" % [part_path != "", leaked])
		failures += 1
	else:
		print("3) part saved, scoped to its own slot type")

	# 4. Loading with the WRONG slot type must refuse; right one round-trips.
	if SaveManager.load_named_component(part_path, HexTile.BodySlot.HEAD) != null:
		push_error("FAIL: torso part loaded as a head")
		failures += 1
	var part_back = SaveManager.load_named_component(part_path, HexTile.BodySlot.TORSO)
	if part_back == null or not (part_back.hex_grid.has_tile(mount_hex) and part_back.hex_grid.get_tile(mount_hex).tile_type == mount.tile_type):
		push_error("FAIL: part round-trip lost the fingerprint mount")
		failures += 1
	else:
		print("4) slot-type guard holds; part round-trip intact")
		part_back.queue_free()

	# 5. Delete works inside the loadouts dir, refuses outside it.
	if not SaveManager.delete_named_loadout(found_path) or FileAccess.file_exists(found_path):
		push_error("FAIL: delete_named_loadout didn't remove the build file")
		failures += 1
	elif SaveManager.delete_named_loadout("user://save_autosave.json"):
		push_error("FAIL: delete guard let a non-loadout path through")
		failures += 1
	else:
		print("5) delete works, guard refuses foreign paths")

	_cleanup()
	if failures == 0:
		print("PASS: named build/part slots - save, list, load, scope, delete all honest")
	get_tree().quit(0 if failures == 0 else 1)
