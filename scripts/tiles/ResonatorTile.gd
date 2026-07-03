class_name ResonatorTile
extends HexTile

@export var boost_per_remnant: float = 1.3
var _remnant_magnitudes: Dictionary = {}

func _init():
	tile_type = "Resonator"
	category = TileCategory.PROCESSOR

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null) -> Array[EnergyPacket]:
	# Simplified remnant logic for Godot translation
	var mult = 1.0
	if _remnant_magnitudes.size() > 0:
		for k in _remnant_magnitudes:
			packet.add_synergy(k, _remnant_magnitudes[k] * 0.8)
			_remnant_magnitudes[k] *= 0.2 # consume most of it
		mult = boost_per_remnant * _get_power_multiplier()
		packet.amplify(mult)
		
	# Leave a remnant
	for syn in packet.synergies:
		_remnant_magnitudes[syn] = packet.synergies[syn] * 0.15
		
	return [packet]

func _get_power_multiplier() -> float:
	var mult = 1.0
	if rarity == Rarity.UNCOMMON: mult = 1.2
	elif rarity == Rarity.RARE: mult = 1.5
	elif rarity == Rarity.LEGENDARY: mult = 3.0
	elif rarity == Rarity.MYTHIC: mult = 5.0
	return mult * (1.0 + (level - 1) * 0.1)
