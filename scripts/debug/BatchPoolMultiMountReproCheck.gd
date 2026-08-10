extends Node

# Phase 0 of the batch-pool full-parity plan (2026-08-10): reproduce a live
# playtest report - the batch renderer dealt zero damage against the dummy
# with a real multi-mount loadout, not caught by any of the existing
# BatchPool*Check.gd files because every one of them calls pool.spawn()
# directly with hand-picked ratios. None of them drive a REAL Mech through
# the actual mount-listing/fire chain (_populate_mounts -> _fire_selected ->
# _fire_via_batch_pool) the way the live report did - that's the coverage
# gap this check fills.
#
# Reuses TestRangeCheck.gd's proven deterministic multi-mount construction
# (a real Core with N active faces feeding N real Weapon Mounts, no solver
# RNG) but with the batch toggle ON instead of off, and extended to 3
# mounts to better match "a real multi-mount loadout."
#
# STATUS (2026-08-10): this check PASSES - a real 3-mount RARE loadout, and
# separately a real 3-mount MYTHIC loadout mixing a Weapon Mount + Missile
# Rack + Weapon Mount, both landed real damage through the batch toggle in
# ad-hoc variants of this test. The live playtest report has NOT been
# reproduced yet by any configuration tried so far. One real (separate,
# minor) issue surfaced along the way, not related to the zero-damage
# report: every mount in a multi-mount volley spawns its batch shot from
# the SAME position (the source Mech's global_position) rather than each
# mount's own muzzle offset - get_muzzle_position() isn't returning
# per-mount positions in this harness. Worth a live repro session with the
# ACTUAL reported build (rarity/routing/bank-shot state this synthetic
# harness doesn't capture) before spending more time guessing blindly here.

const MechScript = preload("res://scripts/entities/Mech.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")
const WeaponMountTileScript = preload("res://scripts/tiles/WeaponMountTile.gd")
const GarageTestRangeScript = preload("res://scripts/ui/GarageTestRange.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _strip_to_torso(mech: Node):
	for slot in mech.components.keys().duplicate():
		if slot != HexTile.BodySlot.TORSO:
			mech.unequip_component(slot)

func _ready():
	var world = Node2D.new()
	add_child(world)

	var player = MechScript.new()
	player.is_player = true
	world.add_child(player)
	player.set_physics_process(false)

	# 3 real, independently-armed mounts off one Core (East/SE/SW faces) -
	# deterministic, no solver RNG, same construction TestRangeCheck.gd
	# already proves produces real precalculated_weapons.
	var torso = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.RARE)
	torso.generate_shape()
	var core = CoreTileScript.new()
	core.rarity = HexTile.Rarity.RARE
	var active: Array[int] = [0, 1, 2]
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
	var mount_c = WeaponMountTileScript.new()
	mount_c.rarity = HexTile.Rarity.RARE
	mount_c.body_slot = HexTile.BodySlot.TORSO
	torso.hex_grid.add_tile(HexCoord.new(-1, 1), mount_c)

	player.equip_component(torso)
	_strip_to_torso(player)
	player._recalculate_grid()
	_check("3 real mounts armed (precalculated_weapons.size() == 3)",
		player.precalculated_weapons.size() == 3)
	if player.precalculated_weapons.size() != 3:
		get_tree().quit(1)
		return

	var range_popup = GarageTestRangeScript.new()
	range_popup.setup(player)
	add_child(range_popup)

	_check("batch toggle exists and starts off", range_popup._batch_toggle != null and not range_popup._batch_toggle.button_pressed)
	range_popup._batch_toggle.button_pressed = true

	_check("all 3 mounts start checked", range_popup._mount_rows.size() == 3 and
		range_popup._mount_rows[0].checkbox.button_pressed and
		range_popup._mount_rows[1].checkbox.button_pressed and
		range_popup._mount_rows[2].checkbox.button_pressed)

	range_popup._fire_selected()
	_check("firing 3 checked mounts through the batch toggle spawns 3 live batch-pool shots",
		range_popup._batch_pool.live_count() == 3)

	var dummy = range_popup._dummy
	var waited = 0.0
	while waited < 3.0 and dummy.hp >= dummy.max_hp:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	var dealt = dummy.max_hp - dummy.hp
	_check("the dummy actually took damage from the 3-mount batch-pool volley (dealt=%.1f after %.2fs)" % [dealt, waited],
		dealt > 0.0)

	if failures > 0:
		# Bisect: fire mounts one at a time to isolate which combination fails.
		range_popup._reset_dummy_stats()
		for solo_idx in range(3):
			range_popup._set_all_checked(false)
			range_popup._solo_row(solo_idx)
			var before = dummy.hp
			range_popup._fire_selected()
			var solo_waited = 0.0
			while solo_waited < 2.0 and dummy.hp >= before:
				await get_tree().create_timer(0.25).timeout
				solo_waited += 0.25
			print("[bisect] solo mount %d alone: dealt %.1f damage after %.2fs" % [solo_idx, before - dummy.hp, solo_waited])
			range_popup._reset_dummy_stats()

	if failures == 0:
		print("PASS: a real 3-mount loadout fired through the batch-pool toggle spawns the right shot count and lands real damage")
	get_tree().quit(0 if failures == 0 else 1)
