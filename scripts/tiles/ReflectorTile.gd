class_name ReflectorTile
extends HexTile

@export var rotation_steps: int = 1 # CCW steps

func _init():
	tile_type = "Reflector"
	category = TileCategory.ROUTER

func get_exit_direction(entry_direction: int) -> int:
	return (entry_direction + 3 + rotation_steps) % 6

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null) -> Array[EnergyPacket]:
	var new_dir = get_exit_direction(entry_direction)
	packet.direction = new_dir
	return [packet]

func rotate(clockwise: bool = true):
	if clockwise:
		rotation_steps = (rotation_steps + 1) % 6
	else:
		rotation_steps = (rotation_steps - 1) % 6
		if rotation_steps < 0:
			rotation_steps += 6
