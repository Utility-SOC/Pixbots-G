class_name ShieldTile
extends HexTile

var stored_energy: float = 0.0
var shield_synergies: Dictionary = {}
@export var conversion_rate: float = 2.0 # Energy to Shield HP ratio

func _init():
	tile_type = "Shield Generator"
	category = TileCategory.OUTPUT
	base_color = Color(0.1, 0.4, 0.8) # Blue

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null) -> Array[EnergyPacket]:
	var p = packet.copy()
	
	var mult = 1.1
	if rarity == Rarity.UNCOMMON: mult = 1.5
	elif rarity == Rarity.RARE: mult = 2.5
	elif rarity == Rarity.LEGENDARY: mult = 5.0
	elif rarity == Rarity.MYTHIC: mult = 10.0
	
	stored_energy += p.magnitude * mult
	for k in p.synergies:
		if shield_synergies.has(k):
			shield_synergies[k] += p.synergies[k] * mult
		else:
			shield_synergies[k] = p.synergies[k] * mult
	
	p.is_active = false
	p.magnitude = 0.0
	return [p]

func get_shield_energy() -> float:
	var e = stored_energy
	stored_energy = 0.0
	return e

func get_shield_synergies() -> Dictionary:
	var s = shield_synergies.duplicate()
	shield_synergies.clear()
	return s
