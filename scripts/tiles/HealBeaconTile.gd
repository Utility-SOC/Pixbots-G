class_name HealBeaconTile
extends HexTile

# Support-role backpack tile. Accumulates energy during grid simulation like
# ShieldGeneratorTile/CloakTile; Mech reads get_heal_energy() once per
# _recalculate_grid() to size the pulse, then Mech._emit_heal_pulse() heals
# nearby squadmates (group "enemy") periodically at runtime.

func _init():
	super._init("Heal Beacon", HexTile.TileCategory.OUTPUT)
	base_color = Color(0.2, 0.9, 0.5)

var stored_energy: float = 0.0

func get_weight() -> float:
	return 4.5 # a med-bay beacon emitter, moderately complex hardware

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	if packet.magnitude <= 0.0 or not packet.is_active: return []

	packet.is_active = false
	stored_energy += packet.magnitude * (1.0 + rarity * 0.5)

	return []

func get_heal_energy() -> float:
	var e = stored_energy
	stored_energy = 0.0
	return e

func get_pulse_radius() -> float:
	return 180.0 + rarity * 40.0

func get_pulse_interval() -> float:
	return max(2.0, 5.0 - rarity * 0.7)
