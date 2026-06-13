class_name ActuatorTile
extends HexTile

var current_speed_bonus: float = 0.0
@export var base_speed_multiplier: float = 0.5

func _init():
	tile_type = "Actuator"
	category = TileCategory.OUTPUT
	base_color = Color(0.8, 0.4, 0.1) # Orange/Brown for motor

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null) -> Array[EnergyPacket]:
	var p = packet.copy()
	# Calculate speed bonus based on energy
	current_speed_bonus = p.magnitude * base_speed_multiplier
	if p.has_synergy(EnergyPacket.SynergyType.KINETIC):
		current_speed_bonus *= 1.5
	if p.has_synergy(EnergyPacket.SynergyType.LIGHTNING):
		current_speed_bonus *= 2.0
		
	p.is_active = false
	p.magnitude = 0.0
	return [p]

func get_speed_bonus() -> float:
	var bonus = current_speed_bonus
	current_speed_bonus = 0.0 # reset for next tick
	return bonus
