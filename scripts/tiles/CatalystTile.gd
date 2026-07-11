class_name CatalystTile
extends HexTile

# Defaults to RAW (design ruling): a fresh tile shouldn't impose FIRE on
# every new build - the player picks the element. A RAW-target catalyst is
# a legitimate "normalizer" (converts everything back to RAW at its usual
# efficiency), so nothing special-cases it.
@export var target_synergy: EnergyPacket.SynergyType = EnergyPacket.SynergyType.RAW
@export var efficiency: float = 1.2

# MYTHIC ability: "Inverted" catalyst acts as a FILTER instead of a
# converter - voids every energy type EXCEPT the chosen element, protecting
# downstream components. Garage popup toggle; ignored below Mythic.
@export var inverted: bool = false

func toggle_inverted():
	if rarity == Rarity.MYTHIC:
		inverted = not inverted

func _init():
	tile_type = "Catalyst"
	category = TileCategory.CONVERTER

func get_weight() -> float:
	return 4.0 # a moderately complex processor

func cycle_synergy():
	target_synergy = (target_synergy + 1) % 10

func cycle_synergy_backward():
	target_synergy = (target_synergy + 9) % 10

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null) -> Array[EnergyPacket]:
	if packet.magnitude <= 0.0: return [packet]

	if inverted and rarity == Rarity.MYTHIC:
		# Filter mode: keep only the chosen element, void the rest outright
		# (no conversion, no efficiency gain - purity has a price).
		var kept = packet.synergies.get(target_synergy, 0.0)
		packet.synergies.clear()
		packet.magnitude = 0.0
		if kept > 0.0:
			packet.add_synergy(target_synergy, kept)
		return [packet]

	var total_consumed = 0.0
	for syn in packet.synergies.keys():
		total_consumed += packet.synergies[syn]
		
	packet.synergies.clear()
	
	var output_amount = total_consumed * efficiency * _get_power_multiplier()
	packet.magnitude = 0.0
	packet.add_synergy(target_synergy, output_amount)
	
	return [packet]

