class_name AccumulatorTile
extends HexTile

@export var charge_multiplier: float = 3.0 # How many times longer it takes to fire
@export var damage_boost: float = 4.5 # The multiplier applied to the magnitude when fired

func _init():
	tile_type = "Accumulator"
	category = TileCategory.STORAGE

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null) -> Array[EnergyPacket]:
	var mult = _get_power_multiplier()
	
	packet.charge_required *= (charge_multiplier / mult) # Higher rarity = less charge time needed for same boost
	packet.amplify(damage_boost * mult)
	
	return [packet]

func _get_power_multiplier() -> float:
	var mult = 1.0
	if rarity == Rarity.UNCOMMON: mult = 1.2
	elif rarity == Rarity.RARE: mult = 1.5
	elif rarity == Rarity.LEGENDARY: mult = 3.0
	return mult * (1.0 + (level - 1) * 0.1)
