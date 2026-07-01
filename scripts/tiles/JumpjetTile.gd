class_name JumpjetTile
extends HexTile

@export var speed_boost_mult: float = 1.5

func _init():
	tile_type = "Jumpjet"
	category = TileCategory.OUTPUT

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null) -> Array[EnergyPacket]:
	if packet.magnitude <= 0.0 or not packet.is_active: return []
	
	packet.is_active = false
	
	if grid and grid.get_parent():
		var mech = grid.get_parent()
		if mech and "slot_type" in mech:
			mech = mech.get_parent()
			
		if mech and "current_move_speed" in mech and "base_move_speed" in mech:
			# Apply continuous speed boost while energy is flowing
			mech.base_move_speed += packet.magnitude * speed_boost_mult * _get_power_multiplier()
			mech.current_move_speed = mech.base_move_speed
			
			if not "jumpjet_energy" in mech:
				mech.set("jumpjet_energy", EnergyPacket.new(0.0, null))
				mech.get("jumpjet_energy").synergies.clear()
				
			var j_energy = mech.get("jumpjet_energy")
			if j_energy:
				j_energy.merge(packet)
			
			if "ignore_terrain" in mech:
				mech.ignore_terrain = true
			if "jumpjet_rarity" in mech:
				mech.jumpjet_rarity = max(mech.jumpjet_rarity, rarity)
				
	return []

func _get_power_multiplier() -> float:
	var mult = 1.0
	if rarity == Rarity.UNCOMMON: mult = 1.2
	elif rarity == Rarity.RARE: mult = 1.5
	elif rarity == Rarity.LEGENDARY: mult = 3.0
	return mult * (1.0 + (level - 1) * 0.1)
