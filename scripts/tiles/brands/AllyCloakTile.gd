class_name AllyCloakTile
extends CloakTile

# Corporate Sponsorships (task #17): Umbra Systems' signature tile. Design
# locked with Natalia:
#   - Cloaks any allies within a shared radius, not just the owning mech
#     (see CloakSystem.gd's _share_cloak_with_allies()) - a quarter of a
#     Jammer Module's own pulse-radius formula ((220+rarity*60)*1.7*0.25),
#     since that's the established "field radius" reference point already
#     in the game.
#   - Cloak (C) is a toggle instead of hold-to-cloak.
#   - "Craziness": you can fire while cloaked without breaking cloak (stays
#     hidden, keeps the ambush multiplier - see the two _break_cloak() call
#     sites in Mech.gd's _shoot/weapon-charge ticking, both now gated on
#     `not umbra_stealth_fire`).
# All three of the above are wired via Mech.umbra_share_radius/
# umbra_toggle_mode/umbra_stealth_fire, set in
# Mech._collect_weapon_mounts_and_tile_capabilities() when it finds a
# Cloak Generator tile with brand_id == "cloak" (this tile, once
# BrandTileFactory rolls it for a boss/sponsor drop).
#
# tile_type stays "Cloak Generator" (inherited, not overridden) - the
# capacity scan above keys off that exact string.

func _init():
	super._init()

func get_weight() -> float:
	return TileStatsRegistry.get_stat("AllyCloakTile", "weight", 4.5)

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	if packet.magnitude <= 0.0 or not packet.is_active: return []
	packet.is_active = false
	stored_energy += packet.magnitude * (1.0 + rarity * TileStatsRegistry.get_stat("AllyCloakTile", "energy_storage_rarity_coeff", 0.5))
	return []

func get_cloak_duration() -> float:
	return TileStatsRegistry.get_stat_by_rarity("AllyCloakTile", "cloak_duration_by_rarity", rarity, [2.5, 3.5, 4.5, 6.0, 8.0])

func get_recharge_time() -> float:
	return TileStatsRegistry.get_stat_by_rarity("AllyCloakTile", "recharge_time_by_rarity", rarity, [9.0, 7.0, 5.5, 4.0, 3.0])

func get_ally_share_radius() -> float:
	return TileStatsRegistry.get_stat("AllyCloakTile", "share_radius_base", 93.5) + rarity * TileStatsRegistry.get_stat("AllyCloakTile", "share_radius_rarity_coeff", 25.5)
