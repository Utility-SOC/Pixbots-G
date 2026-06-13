class_name AccumulatorTile
extends HexTile

@export var capacity: float = 100.0
@export var stored_energy: float = 0.0
@export var auto_release: bool = true

func _init():
	tile_type = "Accumulator"
	category = TileCategory.STORAGE

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null) -> Array[EnergyPacket]:
	var cap_scaled = capacity * _get_power_multiplier()
	
	var store_amount = min(packet.magnitude, cap_scaled - stored_energy)
	stored_energy += store_amount
	
	if auto_release and stored_energy >= cap_scaled:
		var burst = packet.copy()
		burst.magnitude = stored_energy
		burst.amplify(1.5) # Bonus for accumulating
		stored_energy = 0.0
		return [burst]
	
	packet.is_active = false
	packet.magnitude = 0.0
	return []

func _get_power_multiplier() -> float:
	var mult = 1.0
	if rarity == Rarity.UNCOMMON: mult = 1.2
	elif rarity == Rarity.RARE: mult = 1.5
	elif rarity == Rarity.LEGENDARY: mult = 3.0
	return mult * (1.0 + (level - 1) * 0.1)
