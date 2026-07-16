class_name AmplifierTile
extends HexTile

@export var amplification: float = TileStatsRegistry.get_stat("AmplifierTile", "amplification", 1.2)

# MYTHIC ability: focus the amplification. 0 = balanced (normal behavior),
# 1 = pure damage (extra magnitude), 2 = AoE focus (slightly less magnitude
# but pumps packet.aoe_bonus -> bigger projectile + blast radius in
# Projectile.gd). Garage popup toggle; ignored below Mythic.
@export_enum("Balanced", "Pure Damage", "AoE Focus") var mythic_focus: int = 0

func cycle_mythic_focus():
	if rarity == Rarity.MYTHIC:
		mythic_focus = (mythic_focus + 1) % 3

func _init():
	tile_type = "Amplifier"
	category = TileCategory.PROCESSOR

func get_weight() -> float:
	return TileStatsRegistry.get_stat("AmplifierTile", "weight", 6.0) # heavy - a lot of hardware to boost a packet this much

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	var mult = amplification * _get_power_multiplier()
	if rarity == Rarity.MYTHIC:
		match mythic_focus:
			1: mult *= TileStatsRegistry.get_stat("AmplifierTile", "mythic_pure_damage_mult", 1.75) # everything into the payload
			2:
				mult *= TileStatsRegistry.get_stat("AmplifierTile", "mythic_aoe_power_mult", 0.8) # trade raw power for area
				packet.aoe_bonus += TileStatsRegistry.get_stat("AmplifierTile", "mythic_aoe_bonus_add", 1.0)
	packet.amplify(mult)
	return [packet]

