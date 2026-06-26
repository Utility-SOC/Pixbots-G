class_name ShieldGeneratorTile
extends HexTile

func _init():
	super._init("Shield Generator", HexTile.TileCategory.OUTPUT)
	base_color = Color(0.1, 0.4, 0.8)

var stored_energy: float = 0.0

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null) -> Array[EnergyPacket]:
	if packet.magnitude <= 0.0 or not packet.is_active: return []
	
	packet.is_active = false # Consume energy
	stored_energy += packet.magnitude * (1.0 + rarity * 0.5)
	
	return []

func get_shield_energy() -> float:
	var e = stored_energy
	stored_energy = 0.0
	return e
