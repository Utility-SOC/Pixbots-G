class_name CoreTile
extends HexTile

var face_outputs: Dictionary = {} # int (0-5) -> EnergyPacket.SynergyType
var active_faces: Array[int] = [] # List of active directions

func _init():
	super._init("Core Reactor", HexTile.TileCategory.CONVERTER)
	# Default all faces to KINETIC to start
	for i in range(6):
		face_outputs[i] = EnergyPacket.SynergyType.KINETIC
	# Default active faces
	active_faces.append(0)

func get_weight() -> float:
	return TileStatsRegistry.get_stat("CoreTile", "weight", 8.0) # heaviest tile in the game - it's the reactor

func get_exit_directions(entry_direction: int = 0) -> Array[int]:
	return active_faces

func get_max_faces() -> int:
	return int(TileStatsRegistry.get_stat_by_rarity("CoreTile", "max_faces_by_rarity", rarity, [1, 1, 2, 6, 6]))

func toggle_face(direction: int):
	if active_faces.has(direction):
		if active_faces.size() > 1:
			active_faces.erase(direction)
	else:
		if active_faces.size() < get_max_faces():
			active_faces.append(direction)
		else:
			# If at max, remove the oldest one and add the new one
			active_faces.pop_front()
			active_faces.append(direction)

func set_face_output(direction: int, synergy: EnergyPacket.SynergyType):
	face_outputs[direction] = synergy


# The Core's own rarity previously only affected how many faces it could use
# (get_max_faces above), not how much power it actually put out - a Common
# and a Legendary Core Reactor produced the exact same 10.0-magnitude
# packets. This gives rarity a real payoff on the primary power source too.
func get_power_output() -> float:
	return TileStatsRegistry.get_stat_by_rarity("CoreTile", "power_output_by_rarity", rarity, [10.0, 14.0, 20.0, 35.0, 55.0])

func generate_energy(grid: Node) -> Array[EnergyPacket]:
	var packets: Array[EnergyPacket] = []
	var power = get_power_output()
	for dir in face_outputs.keys():
		if not active_faces.has(dir): continue
		var packet = EnergyPacket.new(0.0, null)
		packet.synergies.clear()
		packet.add_synergy(face_outputs[dir], power)
		packet.direction = dir
		packets.append(packet)
	return packets

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	# The Core takes incoming energy (e.g. from Head return) and redistributes it out its active faces!
	if is_disabled: return [packet]
	
	packet.is_active = false
	var out_packets: Array[EnergyPacket] = []
	
	for dir in active_faces:
		var new_pkt = packet.copy()
		new_pkt.direction = dir
		new_pkt.is_active = true
		out_packets.append(new_pkt)
		
	return out_packets
