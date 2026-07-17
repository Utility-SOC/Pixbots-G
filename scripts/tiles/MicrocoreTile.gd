class_name MicrocoreTile
extends "res://scripts/tiles/CoreTile.gd"

func _init():
	super._init()
	tile_type = "Microcore"

func get_weight() -> float:
	return TileStatsRegistry.get_stat("MicrocoreTile", "weight", 5.0) # a compact reactor - still a heavy power source, just lighter than the full Core

func get_max_faces() -> int:
	return int(TileStatsRegistry.get_stat_by_rarity("MicrocoreTile", "max_faces_by_rarity", rarity, [2, 2, 3, 4, 6]))

func get_power_output() -> float:
	return TileStatsRegistry.get_stat_by_rarity("MicrocoreTile", "power_output_by_rarity", rarity, [50.0, 75.0, 120.0, 200.0, 320.0])

func get_face_output(direction: int) -> int:
	if face_outputs.has(direction):
		return face_outputs[direction]
	return EnergyPacket.SynergyType.RAW

func cycle_face_output(direction: int):
	var current = get_face_output(direction)
	current = (current + 1) % EnergyPacket.SynergyType.size()
	face_outputs[direction] = current

func cycle_face_output_backward(direction: int):
	var current = get_face_output(direction)
	current = (current + EnergyPacket.SynergyType.size() - 1) % EnergyPacket.SynergyType.size()
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
