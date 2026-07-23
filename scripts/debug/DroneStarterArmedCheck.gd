extends Node

# Regression harness for the randomly-unarmed starter drone: create_starter_
# drone() used to place its starter Weapon Mount at the first free hex of a
# PROCEDURALLY ROLLED shape, with the Core stamped later (at equip) facing
# its default East - on unlucky shape rolls the core's packet could never
# reach the mount, spawning a drone with zero armed weapons (surfaced as
# intermittent DroneChaseShootCheck flakiness: "drone.precalculated_weapons:
# 0 (expect >= 1)"). The mount is now placed adjacent to the core with the
# core pre-placed aiming straight at it. 20 fresh rolls per rarity tier
# must all arm.

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	for rarity in [HexTile.Rarity.COMMON, HexTile.Rarity.RARE, HexTile.Rarity.MYTHIC]:
		var armed = 0
		var trials = 20
		for i in range(trials):
			var mech = MechScript.new()
			mech.is_player = false
			mech.combat_role = "drone"
			add_child(mech)
			# Replace the auto-equipped starter body with JUST the drone
			# loadout, mirroring how Drone._ready equips it.
			for slot in mech.components.keys().duplicate():
				var old = mech.unequip_component(slot)
				if old:
					old.queue_free()
			mech.equip_component(ComponentEquipmentScript.create_starter_drone(rarity))
			mech._recalculate_grid()
			if mech.precalculated_weapons.size() > 0:
				armed += 1
			mech.queue_free()
		_check("rarity %d: all %d fresh starter-drone rolls spawn ARMED (got %d/%d)" % [rarity, trials, armed, trials],
			armed == trials)

	if failures == 0:
		print("PASS: starter drones are armed on every shape roll - no more RNG dead guns")
	get_tree().quit(0 if failures == 0 else 1)
