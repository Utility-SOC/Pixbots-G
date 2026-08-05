class_name SmokeGrenadeTile
extends HexTile

# Backpack "Smoke Grenade" tile. Mirrors CloakTile.gd's pattern exactly: it
# just accumulates energy routed to it during the hex-grid simulation
# (Mech._recalculate_grid), and Mech reads get_smoke_energy() once per
# recalculation to size a runtime charge pool. Unlike Cloak (a continuous
# drain while active), Smoke Grenade is a single-charge consumable - see
# Mech.try_drop_smoke_grenade(): a drop only fires once smoke_charge is
# full, drains it to 0, and it refills over get_recharge_time() seconds.

func _init():
	super._init("Smoke Grenade", HexTile.TileCategory.OUTPUT)
	base_color = Color(0.55, 0.55, 0.5) # dull olive-grey, reads as ordnance not electronics

var stored_energy: float = 0.0

func get_weight() -> float:
	return TileStatsRegistry.get_stat("SmokeGrenadeTile", "weight", 3.5) # a launcher + canister rack, lighter than a full generator

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	if packet.magnitude <= 0.0 or not packet.is_active: return []

	packet.is_active = false # Consume energy
	stored_energy += packet.magnitude * (1.0 + rarity * TileStatsRegistry.get_stat("SmokeGrenadeTile", "energy_storage_rarity_coeff", 0.5))

	return []

func get_smoke_energy() -> float:
	var e = stored_energy
	stored_energy = 0.0
	return e

# Seconds to fully refill after a drop. Better rarity recovers faster, same
# tiering convention as CloakTile's get_recharge_time().
func get_recharge_time() -> float:
	return TileStatsRegistry.get_stat_by_rarity("SmokeGrenadeTile", "recharge_time_by_rarity", rarity, [10.0, 8.5, 7.0, 5.5, 4.0])

# Cloud radius and how long it lingers - better rarity gets a bigger, more
# persistent cloud, same tiering shape as everything else here. Rare tier
# bumped to ~320 per the user, after trying it in-game - other tiers scaled
# up proportionally around that new midpoint (was [160, 190, 220, 260, 310]).
func get_smoke_radius() -> float:
	return TileStatsRegistry.get_stat_by_rarity("SmokeGrenadeTile", "smoke_radius_by_rarity", rarity, [230.0, 280.0, 320.0, 380.0, 450.0])

func get_smoke_duration() -> float:
	return TileStatsRegistry.get_stat_by_rarity("SmokeGrenadeTile", "smoke_duration_by_rarity", rarity, [4.0, 5.0, 6.0, 7.5, 9.0])
