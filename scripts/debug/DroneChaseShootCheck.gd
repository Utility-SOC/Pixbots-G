extends Node

# Repro/regression harness for Natalia's play report: "companion drone sits
# idle - doesn't chase or shoot." Spawns a real player Mech wearing a Drone
# Bay backpack, deploys its drone via DroneBayTile.spawn_drones_for (the
# exact path Main._spawn_drones_if_needed uses), plants an enemy Mech well
# inside TARGET_SEARCH_RADIUS, then lets the engine run for real (drone
# weapon shots with step > 0 spawn via Timer nodes, so manual _physics_process
# ticking would never see them) and reports:
#   1. did the drone's grid sim produce any weapons (precalculated_weapons)?
#   2. does the rescan acquire the enemy as _current_target?
#   3. does it actually fire (Projectile appears in the world)?
#   4. does the follow-orbit pull it back toward its owner?

const MechScript = preload("res://scripts/entities/Mech.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const DroneBayTileScript = preload("res://scripts/tiles/DroneBayTile.gd")

const RUN_SECONDS = 6.0

var world: Node2D
var player: Node
var drone: Node
var enemy: Node
var projectile_seen := false
var target_acquired_ever := false
var max_owner_distance := 0.0
var elapsed := 0.0

func _ready():
	world = Node2D.new()
	add_child(world)

	player = MechScript.new()
	player.is_player = true
	world.add_child(player)

	var pack = ComponentEquipmentScript.create_drone_backpack(HexTile.Rarity.RARE)
	player.equip_component(pack)
	# The player mech shouldn't think for itself during the check (no input,
	# no AI) - it's just the drone's anchor and side marker.
	player.set_physics_process(false)

	enemy = MechScript.new()
	enemy.is_player = false
	enemy.combat_role = "brawler"
	world.add_child(enemy)
	# 700px out: beyond the OLD orbit-only engagement envelope (~480px search
	# from a 90px owner orbit), so this also regression-tests the sortie
	# behavior - the old code never acquired or fired at this range at all.
	enemy.global_position = player.global_position + Vector2(700, 0)
	# A stationary target: in the "enemy" group with a valid position is all
	# the drone's rescan needs - its AI staying off keeps the check focused.
	enemy.set_physics_process(false)

	var drones = DroneBayTileScript.spawn_drones_for(player, world)
	if drones.is_empty():
		push_error("FAIL: spawn_drones_for produced no drone from a Drone Bay backpack")
		get_tree().quit(1)
		return
	drone = drones[0]
	drone.global_position = player.global_position + Vector2(500, 0) # displaced; follow should pull it back

	print("drone.precalculated_weapons: ", drone.precalculated_weapons.size(),
		" (expect >= 1)  fire_rate: ", drone.fire_rate)

func _physics_process(delta: float):
	if not drone:
		return
	elapsed += delta
	if not projectile_seen:
		for child in world.get_children():
			if child is Projectile:
				projectile_seen = true
	if is_instance_valid(drone._current_target):
		target_acquired_ever = true
	# Ignore the artificial 500px starting displacement (first ~second).
	if elapsed > 1.5:
		max_owner_distance = max(max_owner_distance, drone.global_position.distance_to(player.global_position))
	if elapsed < RUN_SECONDS:
		return
	set_physics_process(false)

	print("target acquired at some point: ", target_acquired_ever, " (expect true)")
	print("enemy still alive at end: ", is_instance_valid(enemy) and not enemy.is_dead,
		" (false here just means the drone killed it - also a pass)")
	var follow_dist = drone.global_position.distance_to(player.global_position)
	print("follow distance after %.0fs: %.0f (expect near FOLLOW_DISTANCE=%.0f once target is dead, started displaced 500)" % [RUN_SECONDS, follow_dist, drone.FOLLOW_DISTANCE])
	print("max owner distance while engaging: %.0f (expect <= LEASH_DISTANCE=%.0f + small lerp overshoot)" % [max_owner_distance, drone.LEASH_DISTANCE])
	print("projectile fired: ", projectile_seen, " (expect true)")

	# --- Save/load round trip: a persisted Drone Bay must still produce an
	# armed drone (drone_loadout serializes through _serialize_component; an
	# empty-but-non-null loadout would spawn an unarmed drone silently).
	var pack_data = SaveManager._serialize_component(player.components[HexTile.BodySlot.BACKPACK])
	var loaded_pack = SaveManager._deserialize_component(pack_data)
	var loaded_bays = DroneBayTileScript.find_all_in_backpack(loaded_pack)
	var roundtrip_armed = false
	if loaded_bays.is_empty():
		push_error("FAIL: Drone Bay tile lost in component save/load round trip")
	else:
		var player2 = MechScript.new()
		player2.is_player = true
		world.add_child(player2)
		player2.set_physics_process(false)
		player2.equip_component(loaded_pack)
		var drones2 = DroneBayTileScript.spawn_drones_for(player2, world)
		if drones2.is_empty():
			push_error("FAIL: no drone spawned from save/loaded Drone Bay")
		else:
			roundtrip_armed = not drones2[0].precalculated_weapons.is_empty()
			print("save/loaded drone precalculated_weapons: ", drones2[0].precalculated_weapons.size(), " (expect >= 1)")

	var ok = not drone.precalculated_weapons.is_empty() \
		and target_acquired_ever \
		and projectile_seen \
		and follow_dist < 250.0 \
		and max_owner_distance <= drone.LEASH_DISTANCE + 60.0 \
		and roundtrip_armed
	if ok:
		print("PASS: drone follows, targets, shoots, and survives save/load armed")
	else:
		push_error("FAIL: see lines above")
	get_tree().quit(0 if ok else 1)
