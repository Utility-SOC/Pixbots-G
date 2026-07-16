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

	if failures == 0:
		print("PASS: test range - checklist isolation (single/group/all/none), real projectiles, real hits")
	get_tree().quit(0 if failures == 0 else 1)
