class_name ReverseAccumulatorTile
extends HexTile

# The literal inverse of AccumulatorTile (per the user, in the same breath
# as "the shoot bucket gets bigger" for rapid-fire's new energy cost -
# Mech.gd's RAPID_FIRE_CHARGE_MULT): "what if we added a hex tile that is
# like, a reverse accumulator that reduces an adjacent weapon mount's
# required energy to fire?" Accumulator SPENDS a hex slot to make one shot
# take longer and hit much harder; this SPENDS a hex slot to make normal
# fire charge faster/cheaper - a real tradeoff (give up the hex to a
# non-weapon tile) rather than a free universal discount, same shape as
# Accumulator's own commitment.
#
# Data-driven tiles (Status.md queue item 1): the literals below are just
# the code-side fallback - res://tiles/ReverseAccumulatorTile/stats.json is
# the real source of truth via TileStatsRegistry.
@export var discount_base: float = TileStatsRegistry.get_stat("ReverseAccumulatorTile", "discount_base", 0.15) # fraction shaved off an adjacent mount's charge_required, before rarity/level scaling

func _init():
	tile_type = "Reverse Accumulator"
	category = TileCategory.STORAGE

func get_weight() -> float:
	return TileStatsRegistry.get_stat("ReverseAccumulatorTile", "weight", 5.0)

# Routed-through behavior: a plain passthrough. The intended use (per the
# user's own description) is ADJACENCY to a Weapon Mount, mirroring
# AccumulatorTile's get_bank_charge()/get_bank_amplify() - see
# get_charge_discount() below and Mech._get_adjacent_reverse_accumulator_
# discount(). Kept here (rather than omitted) only so a packet that
# happens to route literally through this tile doesn't silently vanish.
func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	return [packet]

# Adjacency contribution to a neighboring Weapon Mount's charge_required -
# the fraction shaved off (0.15 = 15% cheaper to charge), scaled by
# rarity/level the same way Accumulator's own bank bonuses scale. Multiple
# adjacent Reverse Accumulators stack additively (see Mech.gd), floored so
# a mount can never be discounted to free/negative charge time.
func get_charge_discount() -> float:
	return discount_base * _get_power_multiplier()
