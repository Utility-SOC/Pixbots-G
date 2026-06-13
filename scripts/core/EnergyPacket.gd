class_name EnergyPacket
extends RefCounted

enum SynergyType {
	RAW, FIRE, ICE, LIGHTNING, VORTEX, POISON, EXPLOSION, KINETIC, PIERCE, VAMPIRIC
}

var magnitude: float = 100.0
var synergies: Dictionary = {}

var position: HexCoord = null
var direction: int = 0
var is_active: bool = true
var traversal_steps: int = 0

func _init(_magnitude: float = 100.0, _position: HexCoord = null):
	magnitude = _magnitude
	position = _position
	synergies[SynergyType.RAW] = magnitude

func get_dominant_synergy() -> int:
	if synergies.is_empty():
		return SynergyType.RAW
	var max_syn = SynergyType.RAW
	var max_val = -1.0
	for k in synergies:
		if synergies[k] > max_val:
			max_val = synergies[k]
			max_syn = k
	return max_syn

func total_synergy_magnitude() -> float:
	var total: float = 0.0
	for v in synergies.values():
		total += v
	return total

func add_synergy(synergy_type: int, amount: float):
	var current = synergies.get(synergy_type, 0.0)
	synergies[synergy_type] = current + amount
	magnitude += amount

func has_synergy(synergy_type: int, min_percentage: float = 0.0) -> bool:
	if magnitude == 0: return false
	var perc = synergies.get(synergy_type, 0.0) / magnitude
	return perc >= min_percentage

func convert_synergy(from_type: int, to_type: int, percentage: float):
	if not synergies.has(from_type):
		return
	
	var amount = synergies[from_type] * percentage
	synergies[from_type] -= amount
	
	if synergies[from_type] <= 0:
		synergies.erase(from_type)
	
	var current_to = synergies.get(to_type, 0.0)
	synergies[to_type] = current_to + amount

func amplify(multiplier: float):
	magnitude *= multiplier
	for key in synergies:
		synergies[key] *= multiplier

func split(ratio: float) -> EnergyPacket:
	if ratio <= 0.0 or ratio >= 1.0:
		push_error("Split ratio must be between 0 and 1")
		return null
	
	var new_packet = EnergyPacket.new(magnitude * ratio, position)
	new_packet.direction = direction
	new_packet.synergies.clear()
	for k in synergies:
		new_packet.synergies[k] = synergies[k] * ratio
		
	magnitude *= (1.0 - ratio)
	for k in synergies:
		synergies[k] *= (1.0 - ratio)
		
	return new_packet

func copy() -> EnergyPacket:
	var new_packet = EnergyPacket.new(magnitude, position)
	new_packet.direction = direction
	new_packet.is_active = is_active
	new_packet.synergies = synergies.duplicate()
	new_packet.traversal_steps = traversal_steps
	return new_packet

func merge(other: EnergyPacket):
	magnitude += other.magnitude
	for k in other.synergies:
		synergies[k] = synergies.get(k, 0.0) + other.synergies[k]

func _to_string() -> String:
	return "EnergyPacket(mag: " + str(magnitude) + ")"
