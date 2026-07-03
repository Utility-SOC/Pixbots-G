class_name AccumulatorTile
extends HexTile

@export var charge_multiplier: float = 3.0 # How many times longer it takes to fire
@export var damage_boost: float = 4.5 # The multiplier applied to the magnitude when fired
@export_enum("None", "1", "2", "3") var trigger_key: String = "None"

func _init():
	tile_type = "Accumulator"
	category = TileCategory.STORAGE

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null) -> Array[EnergyPacket]:
	var mult = _get_power_multiplier()
	
	packet.charge_required *= (charge_multiplier / mult) # Higher rarity = less charge time needed for same boost
	packet.amplify(damage_boost * mult)
	if trigger_key != "None":
		packet.set("trigger_key", trigger_key)
	
	return [packet]

func _get_power_multiplier() -> float:
	var mult = 1.0
	if rarity == Rarity.UNCOMMON: mult = 1.2
	elif rarity == Rarity.RARE: mult = 1.5
	elif rarity == Rarity.LEGENDARY: mult = 3.0
	elif rarity == Rarity.MYTHIC: mult = 5.0
	return mult * (1.0 + (level - 1) * 0.1)

# Used by the adjacency-based "capacitor bank" behavior (see
# Mech._recalculate_grid/_get_adjacent_accumulator_capacity) - when this
# Accumulator sits directly adjacent to a Weapon Mount (rather than being
# routed THROUGH it, which is the process_energy() behavior above), it
# instead contributes to that mount's bank in two ways:
#   - get_bank_charge(): how much longer the mount takes to "fully charge"
#     before it releases everything at once (EnergyPacket.charge_required
#     is hard-capped at 100 by its own setter, so this is scaled to live in
#     that range rather than literal energy units)
#   - get_bank_amplify(): a multiplier applied to the merged volley's total
#     magnitude/synergies once it fires (EnergyPacket.magnitude caps at
#     30,000 - with 2-3 higher-rarity accumulators stacked this can
#     realistically push a merged multi-path packet up toward that cap,
#     which is about as "massive combined blast" as the engine can express)
# Multiple adjacent Accumulators stack on both counts: more of them (or
# higher rarity) means a longer wait for a much bigger payoff.
func get_bank_charge() -> float:
	return 12.0 * _get_power_multiplier()

func get_bank_amplify() -> float:
	return 0.5 * _get_power_multiplier()
