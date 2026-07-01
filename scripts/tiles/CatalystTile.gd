class_name CatalystTile
extends HexTile

@export var target_synergy: EnergyPacket.SynergyType = EnergyPacket.SynergyType.FIRE
@export var efficiency: float = 1.2

func _init():
	tile_type = "Catalyst"
	category = TileCategory.CONVERTER

func cycle_synergy():
	target_synergy = (target_synergy + 1) % 10

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null) -> Array[EnergyPacket]:
	if packet.magnitude <= 0.0: return [packet]
	
	var total_consumed = 0.0
	for syn in packet.synergies.keys():
		total_consumed += packet.synergies[syn]
		
	packet.synergies.clear()
	
	var output_amount = total_consumed * efficiency * _get_power_multiplier()
	packet.magnitude = 0.0
	packet.add_synergy(target_synergy, output_amount)
	
	return [packet]

func _get_power_multiplier() -> float:
	var mult = 1.0
	if rarity == Rarity.UNCOMMON: mult = 1.2
	elif rarity == Rarity.RARE: mult = 1.5
	elif rarity == Rarity.LEGENDARY: mult = 3.0
	return mult * (1.0 + (level - 1) * 0.1)
