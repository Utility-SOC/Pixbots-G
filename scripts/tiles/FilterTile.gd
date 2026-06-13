class_name FilterTile
extends HexTile

@export var from_synergy: EnergyPacket.SynergyType = EnergyPacket.SynergyType.RAW
@export var to_synergy: EnergyPacket.SynergyType = EnergyPacket.SynergyType.FIRE
@export var conversion_rate: float = 0.5

func _init():
	tile_type = "Filter"
	category = TileCategory.CONVERTER

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null) -> Array[EnergyPacket]:
	packet.convert_synergy(from_synergy, to_synergy, conversion_rate)
	return [packet]
