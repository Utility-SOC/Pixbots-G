class_name SplitterTile
extends HexTile

var active_faces: Array[int] = []

func _init():
	tile_type = "Splitter"
	category = TileCategory.ROUTER
	active_faces = [1, 5]

func get_max_faces() -> int:
	match rarity:
		Rarity.COMMON: return 2
		Rarity.UNCOMMON: return 2
		Rarity.RARE: return 3
		Rarity.LEGENDARY: return 5
		_: return 2

func toggle_output(direction: int):
	if active_faces.has(direction):
		if active_faces.size() > 1:
			active_faces.erase(direction)
	else:
		if active_faces.size() < get_max_faces():
			active_faces.append(direction)
		else:
			active_faces.pop_front()
			active_faces.append(direction)

func get_exit_directions(entry_direction: int = 0) -> Array[int]:
	return active_faces

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null) -> Array[EnergyPacket]:
	var packets: Array[EnergyPacket] = []
	var split_count = active_faces.size()
	if split_count == 0:
		return [packet]
		
	var ratio = 1.0 / split_count
	
	for i in range(split_count):
		var exit_dir = active_faces[i]
		
		if i < split_count - 1:
			var new_packet = packet.split(ratio / (1.0 - ratio * i))
			new_packet.direction = exit_dir
			packets.append(new_packet)
		else:
			packet.direction = exit_dir
			packets.append(packet)
			
	return packets
