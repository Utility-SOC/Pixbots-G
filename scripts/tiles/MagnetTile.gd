class_name MagnetTile
extends HexTile

var current_magnetic_power: float = 0.0

# Mythic-only ability: filter what the magnet actually pulls, so a Mythic
# Magnet can be set to ignore Common/Uncommon chaff and only reel in
# Legendary+ drops. -1 means "no filter, attract everything" (the default,
# and the only meaningful state below Mythic rarity).
@export var min_attract_rarity: int = -1

# MYTHIC ability: flip the field. Attract (default) pulls loot inward as
# usual; Repel turns the field into a projectile REFLECTOR - enemy shots
# entering the radius flip ownership and fly back out hunting enemies
# (see the magnet block in Mech._physics_process). Loot attraction keeps
# working in both modes.
@export var repel_mode: bool = false

func toggle_repel_mode():
	if rarity == Rarity.MYTHIC:
		repel_mode = not repel_mode

func cycle_min_attract_rarity():
	if rarity != Rarity.MYTHIC:
		return
	# -1 (any) -> COMMON -> UNCOMMON -> RARE -> LEGENDARY -> MYTHIC -> back to -1
	min_attract_rarity += 1
	if min_attract_rarity > Rarity.MYTHIC:
		min_attract_rarity = -1

func _init():
	tile_type = "Magnet"
	category = TileCategory.OUTPUT
	base_color = Color(0.6, 0.2, 0.8) # Purple

func get_weight() -> float:
	return TileStatsRegistry.get_stat("MagnetTile", "weight", 5.0) # substantial electromagnet hardware

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	var p = packet.copy()
	# Power determines the pull strength
	current_magnetic_power += p.magnitude

	if p.has_synergy(EnergyPacket.SynergyType.LIGHTNING):
		current_magnetic_power *= TileStatsRegistry.get_stat("MagnetTile", "lightning_bonus_mult", 1.5) # Lightning boosts magnetism

	p.is_active = false
	p.magnitude = 0.0
	return [p]

func get_magnetic_power() -> float:
	var power = current_magnetic_power
	current_magnetic_power = 0.0 # reset for next tick

	power *= TileStatsRegistry.get_stat_by_rarity("MagnetTile", "power_mult_by_rarity", rarity, [1.0, 1.2, 1.5, 2.0, 3.0])

	return power

# Only Mythic magnets actually get to filter - a Common/Uncommon/etc. tile
# with min_attract_rarity set (shouldn't normally happen) is ignored here.
func get_min_attract_rarity() -> int:
	if rarity == Rarity.MYTHIC:
		return min_attract_rarity
	return -1
