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
	tile_type = "Chopper" # was "Reverse Accumulator" - a chopper circuit
	# chops a continuous signal into rapid pulses, matching this tile's new
	# split-fire ability below. Deliberately NOT a file/class_name rename -
	# a real save stores script_path: "res://scripts/tiles/
	# ReverseAccumulatorTile.gd", and SaveManager._load_cached() resolves
	# tiles by that exact path, so renaming the file would silently drop
	# every existing save's copy of this tile. See SaveManager.
	# _deserialize_tile's matching tile_type migration shim.
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

# MYTHIC ability (brand new - this tile had none before): how many smaller
# shots a mount's one combined release gets chopped into (2/16/64), SAME
# total magnitude redistributed evenly (EnergyPacket.split(), see HexTile.
# _fire_combined_projectile's chopper-split block) - a rate-of-fire/
# alpha-strike tradeoff, not a damage bonus. Multiple adjacent Choppers
# combine additively (Mech._get_adjacent_chopper_split_factor) - unlike
# Accumulator's capacity dial (which only ever EXTENDS a mount's own
# pre-existing dial), a mount has no split ability at all without an
# adjacent Chopper, so the aggregate IS the split factor outright.
const SPLIT_FACTOR_OPTIONS = [1, 2, 16, 64]
@export var mythic_split_factor: int = 1

func cycle_mythic_split_factor():
	if rarity != HexTile.Rarity.MYTHIC:
		return
	var idx = SPLIT_FACTOR_OPTIONS.find(mythic_split_factor)
	if idx == -1: idx = 0
	mythic_split_factor = SPLIT_FACTOR_OPTIONS[(idx + 1) % SPLIT_FACTOR_OPTIONS.size()]
