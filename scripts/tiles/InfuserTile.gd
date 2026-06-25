class_name InfuserTile
extends HexTile

var secondary_synergy: EnergyPacket.SynergyType = EnergyPacket.SynergyType.POISON
var power_infusion: float = 2.0

func _init():
	super._init("Elemental Infuser", HexTile.TileCategory.PROCESSOR)

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null) -> Array[EnergyPacket]:
	# Add secondary synergy without removing primary
	packet.add_synergy(secondary_synergy, power_infusion)
	
	# Pass straight through
	packet.direction = (entry_direction + 3) % 6
	return [packet]

func cycle_synergy():
	secondary_synergy = (secondary_synergy + 1) % 8
	if secondary_synergy == 0:
		secondary_synergy = 1

func cycle_synergy_backward():
	secondary_synergy -= 1
	if secondary_synergy <= 0:
		secondary_synergy = 7
