class_name FilterTile
extends HexTile

@export var allowed_synergy: EnergyPacket.SynergyType = EnergyPacket.SynergyType.FIRE
@export var raw_return_rate: float = 0.5

func _init():
	tile_type = "Filter"
	category = TileCategory.CONVERTER

func get_weight() -> float:
	return 2.0 # a simple, light processor

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null) -> Array[EnergyPacket]:
	var new_synergies = {}
	var removed_mag = 0.0
	
	for k in packet.synergies:
		if k == allowed_synergy or k == EnergyPacket.SynergyType.RAW:
			new_synergies[k] = packet.synergies[k]
		else:
			removed_mag += packet.synergies[k]
			
	if removed_mag > 0:
		new_synergies[EnergyPacket.SynergyType.RAW] = new_synergies.get(EnergyPacket.SynergyType.RAW, 0.0) + (removed_mag * raw_return_rate)
		
	packet.synergies = new_synergies
	packet.magnitude = packet.total_synergy_magnitude()
	return [packet]
