extends Node

# Regression harness for the Garage Test Range (GarageTestRange.gd): mounts
# must list as a checklist (not a single-pick dropdown), default to all
# checked, support Solo/All/None, and FIRE must fire exactly whichever
# mounts are checked - alone, in a chosen group, or the full build - as
# real projectiles landing on a real dummy in the range's private world.

const MechScript = preload("res://scripts/entities/Mech.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")
const WeaponMountTileScript = preload("res://scripts/tiles/WeaponMountTile.gd")
const GarageTestRangeScript = preload("res://scripts/ui/GarageTestRange.gd")

func _strip_to_torso(mech: Node):
	for slot in mech.components.keys().duplicate():
		if slot != HexTile.BodySlot.TORSO:
			mech.unequip_component(slot)

func _count_projectiles(world: Node) -> int:
	var n = 0
	for c in world.get_children():
		if c.is_in_group("projectile"):
			n += 1
	return n

func _ready():
	var failures = 0
	var world = Node2D.new()
	add_child(world)

	# A deterministic 2-mount torso: Core(0,0) [RARE, faces East + SE] feeds
	# a Weapon Mount at each - two genuinely independent armed mounts to
	# test isolation/grouping against, no solver RNG involved.
	var player = MechScript.new()
	player.is_player = true
	world.add_child(player)
	player.set_physics_process(false)

	var torso = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.RARE)
	torso.generate_shape()
	var core = CoreTileScript.new()
	core.rarity = HexTile.Rarity.RARE
	var active: Array[int] = [0, 1]
	core.active_faces = active
	torso.hex_grid.add_tile(HexCoord.new(0, 0), core)
	var mount_a = WeaponMountTileScript.new()
	mount_a.rarity = HexTile.Rarity.RARE
	mount_a.body_slot = HexTile.BodySlot.TORSO
	torso.hex_grid.add_tile(HexCoord.new(1, 0), mount_a)
	var mount_b = WeaponMountTileScript.new()
	mount_b.rarity = HexTile.Rarity.RARE
	mount_b.body_slot = HexTile.BodySlot.TORSO
	torso.hex_grid.add_tile(HexCoord.new(0, 1), mount_b)

	player.equip_component(torso)
	_strip_to_torso(player) # drop the auto-equipped default arms/legs/head - only the torso's 2 mounts should matter
	player._recalculate_grid()
	if player.precalculated_weapons.size() != 2:
		push_error("FAIL: expected exactly 2 armed mounts, got %d" % player.precalculated_weapons.size())
		get_tree().quit(1)
		return

	var range_popup = GarageTestRangeScript.new()
	range_popup.setup(player)
	add_child(range_popup) # _ready builds the SubViewport world + rig + dummy + mount checklist

	# 1. Checklist reflects the real precalculated weapons, all checked by default.
	if range_popup._mount_rows.size() != 2:
		push_error("FAIL: checklist has %d rows, expected 2" % range_popup._mount_rows.size())
		failures += 1
	elif not (range_popup._mount_rows[0].checkbox.button_pressed and range_popup._mount_rows[1].checkbox.button_pressed):
		push_error("FAIL: mounts should default to checked (full-volley out of the box)")
		failures += 1
	else:
		print("1) checklist: 2 rows, both checked by default")

	# 2. Dummy exists, absurd HP, execution-exempt role.
	var dummy = range_popup._dummy
	if not is_instance_valid(dummy) or dummy.hp < 1e11 or dummy.combat_role != "commander":
		push_error("FAIL: dummy misconfigured")
		failures += 1
	else:
		print("2) dummy standing by (", dummy.hp, " hp, execution-exempt)")

	# 3. FIRE with both checked fires 2 shots in 1 volley.
	range_popup._fire_selected()
	var proj_after_both = _count_projectiles(range_popup._world_root)
	if proj_after_both != 2 or range_popup._shots_fired != 2 or range_popup._volleys_fired != 1:
		push_error("FAIL: firing both checked mounts gave %d projectiles, shots=%d volleys=%d (expected 2/2/1)" % [proj_after_both, range_popup._shots_fired, range_popup._volleys_fired])
		failures += 1
	else:
		print("3) both mounts checked: FIRE spawns 2 projectiles in 1 volley")

	# 4. Solo isolates to exactly one mount.
	range_popup._solo_row(0)
	if range_popup._mount_rows[0].checkbox.button_pressed != true or range_popup._mount_rows[1].checkbox.button_pressed != false:
		push_error("FAIL: Solo(0) didn't isolate to just row 0")
		failures += 1
	else:
		range_popup._fire_selected()
		var proj_after_solo = _count_projectiles(range_popup._world_root)
		if proj_after_solo != proj_after_both + 1:
			push_error("FAIL: solo-fire spawned %d new projectiles, expected exactly 1" % (proj_after_solo - proj_after_both))
			failures += 1
		else:
			print("4) Solo isolates to exactly one mount - FIRE spawns exactly 1 projectile")

	# 5. None means FIRE does nothing.
	range_popup._set_all_checked(false)
	var proj_before_none = _count_projectiles(range_popup._world_root)
	var volleys_before_none = range_popup._volleys_fired
	range_popup._fire_selected()
	if _count_projectiles(range_popup._world_root) != proj_before_none or range_popup._volleys_fired != volleys_before_none:
		push_error("FAIL: FIRE with nothing checked should be a no-op")
		failures += 1
	else:
		print("5) nothing checked: FIRE is a no-op")

	# 6. All re-checks everything.
	range_popup._set_all_checked(true)
	if not (range_popup._mount_rows[0].checkbox.button_pressed and range_popup._mount_rows[1].checkbox.button_pressed):
		push_error("FAIL: All didn't re-check every mount")
		failures += 1
	else:
		print("6) All re-checks every mount")

	# 7. Real flight, real hit: within 3 seconds the dummy took damage.
	var waited = 0.0
	while waited < 3.0 and dummy.hp >= dummy.max_hp:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	var dealt = dummy.max_hp - dummy.hp
	if dealt <= 0.0:
		push_error("FAIL: no projectile ever connected with the dummy (3s)")
		failures += 1
	else:
		print("7) dummy took %.0f damage after %.2fs of real flight" % [dealt, waited])

	# 8. Reset restores the dummy and both counters.
	range_popup._reset_dummy_stats()
	if dummy.hp != dummy.max_hp or range_popup._shots_fired != 0 or range_popup._volleys_fired != 0:
		push_error("FAIL: reset didn't restore the dummy/counters")
		failures += 1
	else:
		print("8) reset restores the dummy and both shot/volley counters")

	# 9. Search filter (playtest: "I want a search box... let me filter the
	# emitters/projectiles to just right arm, or just torso, or whatever,
	# or like - torso+lightning"). Both mounts here are TORSO/RAW (no
	# element set on the packet, so it reads as RAW) - a filter for "torso"
	# should keep both, a filter for a body slot that doesn't exist here
	# ("head") should hide both, and clearing the filter must restore both.
	range_popup._search_box.text = "torso"
	range_popup._apply_search_filter()
	if not (range_popup._mount_rows[0].row.visible and range_popup._mount_rows[1].row.visible):
		push_error("FAIL: filtering for 'torso' should keep both torso-slot rows visible")
		failures += 1
	else:
		print("9) filter 'torso' keeps both matching rows visible")

	range_popup._search_box.text = "head"
	range_popup._apply_search_filter()
	if range_popup._mount_rows[0].row.visible or range_popup._mount_rows[1].row.visible:
		push_error("FAIL: filtering for 'head' should hide both torso-only rows")
		failures += 1
	else:
		print("10) filter 'head' hides every non-matching row")

	# 11. All/None only touch currently-visible (filtered) rows - filter to
	# nothing, None should leave the (already-checked-from-step-6) rows
	# untouched since neither is visible to act on.
	var checked_before_filtered_none = [range_popup._mount_rows[0].checkbox.button_pressed, range_popup._mount_rows[1].checkbox.button_pressed]
	range_popup._set_all_checked(false)
	if [range_popup._mount_rows[0].checkbox.button_pressed, range_popup._mount_rows[1].checkbox.button_pressed] != checked_before_filtered_none:
		push_error("FAIL: None while everything is filtered-out shouldn't change any checkbox")
		failures += 1
	else:
		print("11) All/None only act on currently-visible (filtered) rows")

	range_popup._search_box.text = ""
	range_popup._apply_search_filter()
	if not (range_popup._mount_rows[0].row.visible and range_popup._mount_rows[1].row.visible):
		push_error("FAIL: clearing the filter should restore every row's visibility")
		failures += 1
	else:
		print("12) clearing the filter restores full visibility")

	# 13-17: Drones in the range (playtest: "I also want drones in the test
	# area"). Give the same player a Backpack with one Drone Bay tile - its
	# loadout is null, so DroneBayTile.get_or_build_loadout() (called by the
	# spawn_drones_for helper GarageTestRange reuses) lazily builds a real
	# create_starter_drone() loadout, which guarantees an armed Weapon Mount
	# by construction (see that function's own comment on avoiding
	# "randomly UNARMED drone" flakiness) - deterministic, no solver RNG.
	var backpack = ComponentEquipmentScript.new(HexTile.BodySlot.BACKPACK, HexTile.Rarity.RARE)
	backpack.generate_shape()
	var bay = load("res://scripts/tiles/DroneBayTile.gd").new()
	bay.rarity = HexTile.Rarity.RARE
	bay.body_slot = HexTile.BodySlot.BACKPACK
	backpack.hex_grid.add_tile(backpack.valid_hexes[0], bay)
	player.equip_component(backpack)
	player._recalculate_grid()

	var range_popup_2 = GarageTestRangeScript.new()
	range_popup_2.setup(player)
	add_child(range_popup_2)

	if range_popup_2._drones.size() != 1:
		push_error("FAIL: expected exactly 1 drone spawned for 1 Drone Bay, got %d" % range_popup_2._drones.size())
		failures += 1
	else:
		print("13) one Drone Bay tile spawns exactly one live Drone in the range")

	var drone = range_popup_2._drones[0] if range_popup_2._drones.size() == 1 else null
	if not drone or drone.is_physics_processing():
		push_error("FAIL: spawned drone should be frozen (no autonomous chase/orbit) in the range")
		failures += 1
	else:
		print("14) spawned drone is frozen, not chasing/orbiting on its own")

	var drone_row_idx = -1
	for i in range(range_popup_2._mount_rows.size()):
		if range_popup_2._mount_rows[i].source == drone:
			drone_row_idx = i
			break
	if drone_row_idx == -1:
		push_error("FAIL: no checklist row is sourced from the spawned drone")
		failures += 1
	elif not range_popup_2._mount_rows[drone_row_idx].checkbox.text.begins_with("Drone 1:"):
		push_error("FAIL: drone row isn't labeled 'Drone 1: ...' (got '%s')" % range_popup_2._mount_rows[drone_row_idx].checkbox.text)
		failures += 1
	else:
		print("15) drone's weapon is listed in the checklist, labeled 'Drone 1: ...'")

	if drone_row_idx != -1:
		range_popup_2._solo_row(drone_row_idx)
		var before = _count_projectiles(range_popup_2._world_root)
		range_popup_2._fire_selected()
		var fired: Node = null
		for c in range_popup_2._world_root.get_children():
			if c.is_in_group("projectile"):
				fired = c
		if _count_projectiles(range_popup_2._world_root) != before + 1 or not fired or fired.source_mech != drone:
			push_error("FAIL: solo-firing the drone's mount should spawn exactly 1 projectile sourced from the drone itself")
			failures += 1
		else:
			print("16) solo-firing the drone's mount fires a real projectile sourced from the drone, not the rig")

	# 17. Closing the range must not corrupt the REAL Drone Bay tile's
	# persistent loadout - Drone._exit_tree() is responsible for detaching
	# drone_loadout_source before the drone node frees (see that function's
	# own comment on why this matters for save-state integrity).
	range_popup_2.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	if bay.drone_loadout == null or not is_instance_valid(bay.drone_loadout) or bay.drone_loadout.get_parent() != null:
		push_error("FAIL: closing the range corrupted the Drone Bay's real persistent loadout")
		failures += 1
	else:
		print("17) closing the range leaves the Drone Bay's real loadout intact and unparented")

	if failures == 0:
		print("PASS: test range - checklist isolation (single/group/all/none), search filter, drones, real projectiles, real hits")
	get_tree().quit(0 if failures == 0 else 1)
