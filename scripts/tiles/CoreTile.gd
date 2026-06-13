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

func get_exit_directions(entry_direction: int = 0) -> Array[int]:
	return active_faces

func get_max_faces() -> int:
	match rarity:
		Rarity.COMMON: return 1
		Rarity.UNCOMMON: return 1
		Rarity.RARE: return 2
		Rarity.LEGENDARY: return 6
		_: return 1

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

func generate_energy(grid: Node) -> Array[EnergyPacket]:
	var packets: Array[EnergyPacket] = []
	for dir in face_outputs.keys():
		if not active_faces.has(dir): continue
		var packet = EnergyPacket.new(0.0, null)
		packet.synergies.clear()
		packet.add_synergy(face_outputs[dir], 10.0)
		packet.direction = dir
		packets.append(packet)
	return packets

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null) -> Array[EnergyPacket]:
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
