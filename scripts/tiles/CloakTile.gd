class_name CloakTile
extends HexTile

# Backpack "Cloak Generator" tile. Mirrors the ShieldGeneratorTile pattern:
# it just accumulates energy routed to it during the hex-grid simulation
# (Mech._recalculate_grid), and Mech reads get_cloak_energy() once per
# recalculation to size a runtime charge pool. The actual charge/drain while
# playing is handled by CloakSystem.tick() every physics frame (see
# Mech.gd's cloak_system field), the same way shield_hp regenerates
# independently of the routing simulation.

func _init():
	super._init("Cloak Generator", HexTile.TileCategory.OUTPUT)
	base_color = Color(0.5, 0.2, 0.7)

var stored_energy: float = 0.0

func get_weight() -> float:
	return TileStatsRegistry.get_stat("CloakTile", "weight", 4.5) # a stealth generator - moderately complex hardware

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	if packet.magnitude <= 0.0 or not packet.is_active: return []

	packet.is_active = false # Consume energy
	stored_energy += packet.magnitude * (1.0 + rarity * TileStatsRegistry.get_stat("CloakTile", "energy_storage_rarity_coeff", 0.5))

	return []

func get_cloak_energy() -> float:
	var e = stored_energy
	stored_energy = 0.0
	return e

# How many seconds a full charge lasts cloaked, and how many seconds it takes
# to fully recharge from empty. Better rarity = holds the cloak longer and
# recovers faster, same tiering convention as ShieldGeneratorTile's recharge_delay.
func get_cloak_duration() -> float:
	return TileStatsRegistry.get_stat_by_rarity("CloakTile", "cloak_duration_by_rarity", rarity, [2.5, 3.5, 4.5, 6.0, 8.0])

func get_recharge_time() -> float:
	return TileStatsRegistry.get_stat_by_rarity("CloakTile", "recharge_time_by_rarity", rarity, [9.0, 7.0, 5.5, 4.0, 3.0])
