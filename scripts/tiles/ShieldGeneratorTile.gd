class_name ShieldGeneratorTile
extends HexTile

func _init():
	super._init("Shield Generator", HexTile.TileCategory.OUTPUT)
	base_color = Color(0.1, 0.4, 0.8)

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null) -> Array[EnergyPacket]:
	if packet.magnitude <= 0.0 or not packet.is_active: return []
	
	packet.is_active = false # Consume energy
	
	# Signal up to the mech that it received shield energy
	if grid and grid.get_parent() and grid.get_parent().has_method("apply_shield_energy"):
		grid.get_parent().apply_shield_energy(packet.magnitude * (1.0 + rarity * 0.5))
		
	return []
