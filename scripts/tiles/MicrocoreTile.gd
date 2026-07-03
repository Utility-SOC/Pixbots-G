class_name MicrocoreTile
extends "res://scripts/tiles/CoreTile.gd"

func _init():
	super._init()
	tile_type = "Microcore"

func get_max_faces() -> int:
	match rarity:
		Rarity.COMMON: return 2
		Rarity.UNCOMMON: return 2
		Rarity.RARE: return 3
		Rarity.LEGENDARY: return 4
		Rarity.MYTHIC: return 6 # geometric ceiling
		_: return 2

func get_power_output() -> float:
	match rarity:
		Rarity.COMMON: return 50.0
		Rarity.UNCOMMON: return 75.0
		Rarity.RARE: return 120.0
		Rarity.LEGENDARY: return 200.0
		Rarity.MYTHIC: return 320.0
		_: return 50.0

func set_face_output(direction: int, synergy: EnergyPacket.SynergyType):
	face_outputs[direction] = synergy

func get_face_output(direction: int) -> int:
	if face_outputs.has(direction):
		return face_outputs[direction]
	return EnergyPacket.SynergyType.RAW

func cycle_face_output(direction: int):
	var current = get_face_output(direction)
	current = (current + 1) % EnergyPacket.SynergyType.size()
	face_outputs[direction] = current

func generate_energy(grid: Node) -> Array[EnergyPacket]:
	var packets: Array[EnergyPacket] = []
	var current_power = get_power_output()
	for face in active_faces:
		var pkt = EnergyPacket.new(0.0, null)
		pkt.synergies.clear()
		pkt.add_synergy(get_face_output(face), current_power)
		pkt.direction = face
			
		packets.append(pkt)
	return packets
