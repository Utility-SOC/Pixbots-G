class_name AmplifierTile
extends HexTile

@export var amplification: float = 1.2

func _init():
	tile_type = "Amplifier"
	category = TileCategory.PROCESSOR

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null) -> Array[EnergyPacket]:
	var mult = amplification * _get_power_multiplier()
	packet.amplify(mult)
	return [packet]

func _get_power_multiplier() -> float:
	var mult = 1.0
	if rarity == Rarity.UNCOMMON: mult = 1.2
	elif rarity == Rarity.RARE: mult = 1.5
	elif rarity == Rarity.LEGENDARY: mult = 3.0
	elif rarity == Rarity.MYTHIC: mult = 5.0
	return mult * (1.0 + (level - 1) * 0.1)
