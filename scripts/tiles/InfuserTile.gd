class_name InfuserTile
extends HexTile

# Defaults to RAW (design ruling): a fresh infuser is an inert pass-through
# until the player picks its element - see the RAW guard in process_energy.
var secondary_synergy: EnergyPacket.SynergyType = EnergyPacket.SynergyType.RAW
var power_infusion: float = 2.0

func _init():
	super._init("Elemental Infuser", HexTile.TileCategory.PROCESSOR)

func get_weight() -> float:
	return 4.0 # moderate - an elemental conversion processor

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null) -> Array[EnergyPacket]:
	# RAW = unconfigured: pure pass-through. Without this guard the
	# add_synergy below would mint free RAW magnitude out of nothing.
	if secondary_synergy == EnergyPacket.SynergyType.RAW:
		packet.direction = (entry_direction + 3) % 6
		return [packet]

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

# RAW is part of the cycle now (the inert/default state you can return
# to), so both directions are a plain wrap.
func cycle_synergy():
	secondary_synergy = (secondary_synergy + 1) % EnergyPacket.SynergyType.size()

func cycle_synergy_backward():
	secondary_synergy = (secondary_synergy + EnergyPacket.SynergyType.size() - 1) % EnergyPacket.SynergyType.size()
