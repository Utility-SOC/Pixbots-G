extends Node

# Regression harness for the Garage Test Range (GarageTestRange.gd): a
# solver-armed mech's mounts must list with their real packet data, a
# test-fire must spawn a real projectile in the range's private world, and
# the dummy must actually take damage from it (real flight, real hit).

const MechScript = preload("res://scripts/entities/Mech.gd")
const SolverProfileScript = preload("res://scripts/ai/SolverProfile.gd")
const GarageTestRangeScript = preload("res://scripts/ui/GarageTestRange.gd")

func _ready():
	var failures = 0
	var world = Node2D.new()
	add_child(world)

	# A real armed mech via the same solver pipeline the demo builds use.
	var player = MechScript.new()
	player.is_player = true
	player.base_rarity = HexTile.Rarity.UNCOMMON
	player.combat_role = "brawler"
	player.spawn_profile = SolverProfileScript.new("TestRange", EnergyPacket.SynergyType.RAW)
	world.add_child(player)
	player.set_physics_process(false)
	player.build_loadout_for_role("brawler")
	player._recalculate_grid()
	if player.precalculated_weapons.is_empty():
		push_error("FAIL: solver build produced no armed mounts - can't test the range")
		get_tree().quit(1)
		return

	var range_popup = GarageTestRangeScript.new()
	range_popup.setup(player)
	add_child(range_popup) # _ready builds the SubViewport world + rig + dummy

	# 1. Mount list reflects the real precalculated weapons.
	var listed = range_popup._mount_select.item_count
	if listed != player.precalculated_weapons.size():
		push_error("FAIL: listed %d mounts, mech has %d armed entries" % [listed, player.precalculated_weapons.size()])
		failures += 1
	else:
		print("1) mount list: %d armed entries listed" % listed)

	# 2. Dummy exists, absurd HP, execution-exempt role.
	var dummy = range_popup._dummy
	if not is_instance_valid(dummy) or dummy.hp < 1e11 or dummy.combat_role != "commander":
		push_error("FAIL: dummy misconfigured")
		failures += 1
	else:
		print("2) dummy standing by (", dummy.hp, " hp, execution-exempt)")

	# 3. Fire and let the real projectile fly (private physics world).
	range_popup._fire_once()
	var proj_found = false
	for c in range_popup._world_root.get_children():
		if c.is_in_group("projectile"):
			proj_found = true
	if not proj_found or range_popup._shots_fired != 1:
		push_error("FAIL: FIRE didn't spawn a projectile in the range world")
		failures += 1
	else:
		print("3) FIRE: real projectile spawned in the range's own world")

	# 4. Real flight, real hit: within 3 seconds the dummy took damage.
	var waited = 0.0
	while waited < 3.0 and dummy.hp >= dummy.max_hp:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	var dealt = dummy.max_hp - dummy.hp
	if dealt <= 0.0:
		push_error("FAIL: projectile never connected with the dummy (3s)")
		failures += 1
	else:
		print("4) dummy took %.0f damage after %.2fs of real flight" % [dealt, waited])

	# 5. Reset restores the dummy.
	range_popup._reset_dummy_stats()
	if dummy.hp != dummy.max_hp or range_popup._shots_fired != 0:
		push_error("FAIL: reset didn't restore the dummy")
		failures += 1
	else:
		print("5) reset restores the dummy and the counters")

	if failures == 0:
		print("PASS: test range - real mounts, real projectiles, real hits, private world")
	get_tree().quit(0 if failures == 0 else 1)
