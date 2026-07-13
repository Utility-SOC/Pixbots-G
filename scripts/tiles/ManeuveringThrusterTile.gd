class_name ManeuveringThrusterTile
extends HexTile

# Agility upgrade (Utility-SOC: "some upgrade tile that will make my mech
# more agile - maneuvering thrusters? - that would make it easier to kill
# my inertia and make the whole thing more responsive at high speeds").
# PlayerController.gd already has real inertia (velocity chases target_vel
# via move_toward at a fixed `accel` scalar, not an instant snap) and that
# scalar is already precedent-modified by an equipped tile the exact same
# way JumpjetTile bumps jumpjet_rarity - this follows that pattern, feeding
# mech.thruster_accel_bonus instead.

func _init():
	tile_type = "Maneuvering Thruster"
	category = TileCategory.OUTPUT

func get_weight() -> float:
	return 5.0 # gimbal/reaction-wheel hardware - lighter than a full jumpjet stack

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	if packet.magnitude <= 0.0 or not packet.is_active: return []

	packet.is_active = false

	if grid and grid.get_parent():
		var mech = grid.get_parent()
		if mech and "slot_type" in mech:
			mech = mech.get_parent()

		if mech and "thruster_accel_bonus" in mech:
			mech.thruster_accel_bonus = max(mech.thruster_accel_bonus, rarity)

	return []
