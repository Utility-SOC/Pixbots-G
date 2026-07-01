class_name InfuserTile
extends HexTile

var secondary_synergy: EnergyPacket.SynergyType = EnergyPacket.SynergyType.POISON
var power_infusion: float = 2.0

func _init():
	super._init("Elemental Infuser", HexTile.TileCategory.PROCESSOR)

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null) -> Array[EnergyPacket]:
	# Convert a proportion of the RAW energy to this synergy
	# This ensures subsequent different infusers are additive (they all pull from RAW)
	var conversion_rate = 0.4 + (rarity * 0.15) + ((level - 1) * 0.05)
	conversion_rate = min(conversion_rate, 1.0)
	packet.convert_synergy(EnergyPacket.SynergyType.RAW, secondary_synergy, conversion_rate)
	
	# Add secondary synergy without removing primary
	var infusion_amount = power_infusion * (1.0 + rarity * 0.5) * (1.0 + (level - 1) * 0.1)
	packet.add_synergy(secondary_synergy, infusion_amount)
	
	# Pass straight through
	packet.direction = (entry_direction + 3) % 6
	return [packet]

func cycle_synergy():
	secondary_synergy = (secondary_synergy + 1) % EnergyPacket.SynergyType.size()
	if secondary_synergy == 0:
		secondary_synergy = 1

func cycle_synergy_backward():
	secondary_synergy -= 1
	if secondary_synergy <= 0:
		secondary_synergy = EnergyPacket.SynergyType.size() - 1
