class_name CatalystTile
extends HexTile

@export var input_synergies: Array[EnergyPacket.SynergyType] = []
@export var output_synergy: EnergyPacket.SynergyType = EnergyPacket.SynergyType.RAW
@export var efficiency: float = 1.2

func _init():
	tile_type = "Catalyst"
	category = TileCategory.CONVERTER

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null) -> Array[EnergyPacket]:
	if input_synergies.is_empty(): return [packet]
	
	var has_all = true
	for syn in input_synergies:
		if not packet.has_synergy(syn, 0.1):
			has_all = false
			break
			
	if has_all:
		var total_consumed = 0.0
		for syn in input_synergies:
			if packet.synergies.has(syn):
				total_consumed += packet.synergies[syn] * 0.5
				packet.synergies[syn] *= 0.5
		
		var output_amount = total_consumed * efficiency * _get_power_multiplier()
		packet.add_synergy(output_synergy, output_amount)
		
	return [packet]

func _get_power_multiplier() -> float:
	var mult = 1.0
	if rarity == Rarity.UNCOMMON: mult = 1.2
	elif rarity == Rarity.RARE: mult = 1.5
	elif rarity == Rarity.LEGENDARY: mult = 3.0
	return mult * (1.0 + (level - 1) * 0.1)
