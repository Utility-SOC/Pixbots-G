class_name MagnetTile
extends HexTile

var current_magnetic_power: float = 0.0

func _init():
	tile_type = "Magnet"
	category = TileCategory.OUTPUT
	base_color = Color(0.6, 0.2, 0.8) # Purple

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null) -> Array[EnergyPacket]:
	var p = packet.copy()
	# Power determines the pull strength
	current_magnetic_power += p.magnitude
	
	if p.has_synergy(EnergyPacket.SynergyType.LIGHTNING):
		current_magnetic_power *= 1.5 # Lightning boosts magnetism
		
	p.is_active = false
	p.magnitude = 0.0
	return [p]

func get_magnetic_power() -> float:
	var power = current_magnetic_power
	current_magnetic_power = 0.0 # reset for next tick
	
	# Scale by rarity
	if rarity == Rarity.UNCOMMON: power *= 1.2
	elif rarity == Rarity.RARE: power *= 1.5
	elif rarity == Rarity.LEGENDARY: power *= 2.0
	
	return power
