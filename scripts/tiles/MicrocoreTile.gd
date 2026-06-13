class_name MicrocoreTile
extends "res://scripts/tiles/CoreTile.gd"

func _init():
	super._init()
	tile_type = "Microcore"

func get_max_faces() -> int:
	match rarity:
		Rarity.COMMON: return 1
		Rarity.UNCOMMON: return 1
		Rarity.RARE: return 2
		Rarity.LEGENDARY: return 2
		_: return 1

var power_output: float = 50.0

func set_face_output(direction: int, synergy: EnergyPacket.SynergyType):
	face_outputs[direction] = synergy

func get_face_output(direction: int) -> int:
	if face_outputs.has(direction):
		return face_outputs[direction]
	return EnergyPacket.SynergyType.RAW

func cycle_face_output(direction: int):
	var current = get_face_output(direction)
	current = (current + 1) % 7 # Assumes up to 7 synergies exist
	face_outputs[direction] = current

func generate_energy(grid: Node) -> Array[EnergyPacket]:
	var packets: Array[EnergyPacket] = []
	for face in active_faces:
		var pkt = EnergyPacket.new()
		pkt.magnitude = power_output
		pkt.direction = face
		
		var syn = get_face_output(face)
		if syn != EnergyPacket.SynergyType.RAW:
			pkt.add_synergy(syn, power_output)
			
		packets.append(pkt)
	return packets
