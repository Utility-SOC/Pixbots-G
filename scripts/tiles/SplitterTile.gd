class_name SplitterTile
extends HexTile

var active_faces: Array[int] = []

# Mythic Splitters gain a Resonator-style remnant boost (see ResonatorTile) -
# whatever passed through last time juices up the next packet through.
var _remnant_magnitudes: Dictionary = {}

func _init():
	tile_type = "Splitter"
	category = TileCategory.ROUTER
	active_faces = [1, 5]

func get_weight() -> float:
	return 2.0 # light - just a routing junction

func get_max_faces() -> int:
	match rarity:
		Rarity.COMMON: return 2
		Rarity.UNCOMMON: return 2
		Rarity.RARE: return 3
		Rarity.LEGENDARY: return 5
		Rarity.MYTHIC: return 6 # every face on the hex - the geometric maximum
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
	# Mythic upgrade: doubles total throughput and behaves like a Resonator
	# too (remnant energy from the last packet boosts the next one).
	if rarity == Rarity.MYTHIC:
		if _remnant_magnitudes.size() > 0:
			for k in _remnant_magnitudes:
				packet.add_synergy(k, _remnant_magnitudes[k] * 0.8)
				_remnant_magnitudes[k] *= 0.2 # consume most of it
		for syn in packet.synergies:
			_remnant_magnitudes[syn] = packet.synergies[syn] * 0.15
		packet.amplify(2.0)

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
