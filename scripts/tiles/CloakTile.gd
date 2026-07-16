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
	return 4.5 # a stealth generator - moderately complex hardware

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	if packet.magnitude <= 0.0 or not packet.is_active: return []

	packet.is_active = false # Consume energy
	stored_energy += packet.magnitude * (1.0 + rarity * 0.5)

	return []

func get_cloak_energy() -> float:
	var e = stored_energy
	stored_energy = 0.0
	return e

# How many seconds a full charge lasts cloaked, and how many seconds it takes
# to fully recharge from empty. Better rarity = holds the cloak longer and
# recovers faster, same tiering convention as ShieldGeneratorTile's recharge_delay.
func get_cloak_duration() -> float:
	match rarity:
		Rarity.MYTHIC: return 8.0
		Rarity.LEGENDARY: return 6.0
		Rarity.RARE: return 4.5
		Rarity.UNCOMMON: return 3.5
		_: return 2.5

func get_recharge_time() -> float:
	match rarity:
		Rarity.MYTHIC: return 3.0
		Rarity.LEGENDARY: return 4.0
		Rarity.RARE: return 5.5
		Rarity.UNCOMMON: return 7.0
		_: return 9.0
