class_name AccumulatorTile
extends HexTile

# Data-driven tiles (Status.md queue item 1): the literals below are just the
# code-side fallback now - res://tiles/AccumulatorTile/stats.json is the real
# source of truth, read once and cached by TileStatsRegistry. A missing file
# or key falls back to these exact numbers, so nothing changes for anyone
# until a modder (or a future in-repo tuning pass) actually edits the JSON.
@export var charge_multiplier: float = TileStatsRegistry.get_stat("AccumulatorTile", "charge_multiplier", 3.0) # How many times longer it takes to fire
@export var damage_boost: float = TileStatsRegistry.get_stat("AccumulatorTile", "damage_boost", 4.5) # The multiplier applied to the magnitude when fired
@export_enum("None", "1", "2", "3") var trigger_key: String = "None"

# Auto-dump threshold (tile config, Status.md re-imaginings): 0.0 = the
# banked shot fires only on its 1/2/3 key (unchanged default); 0.25-1.0 =
# it releases ITSELF the moment the bank reaches that fraction of full
# charge, payload scaled to what was actually banked - a fully automated
# burst-fire rhythm with a real tradeoff (lower threshold = faster but
# weaker automated volleys). See Mech._tick_weapon_charges.
@export_range(0.0, 1.0, 0.25) var auto_dump_threshold: float = 0.0

func _init():
	tile_type = "Accumulator"
	category = TileCategory.STORAGE

func get_weight() -> float:
	return TileStatsRegistry.get_stat("AccumulatorTile", "weight", 7.0) # a capacitor bank storing this much charge is heavy

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	var mult = _get_power_multiplier()

	# The through-flowing packet is NOT modified (design: clicking fires
	# the weapon "almost as if there were no accumulator"). Instead the
	# accumulator records its boost multipliers on the packet, and the
	# mount collection in Mech._recalculate_grid builds a SEPARATE big
	# charged shot from them - fired exclusively by this tile's 1/2/3 key.
	packet.acc_charge_mult *= (charge_multiplier / mult) # higher rarity = less extra charge time for the same boost
	packet.acc_damage_mult *= (damage_boost * mult)
	packet.auto_dump_threshold = max(packet.auto_dump_threshold, auto_dump_threshold)
	if trigger_key != "None":
		packet.set("trigger_key", trigger_key)
	# The "almost": normal mouse fire pays a small quality tax
	packet.accumulator_quality = min(packet.accumulator_quality, get_quality_factor())

	return [packet]

# Convenience tax on NORMAL (mouse) fire through this accumulator: 1.0 is
# no penalty. Better rarity/level = smoother discharge circuitry = smaller
# tax. Manual key-dumps (hold 1/2/3 + fire) bypass it entirely - see
# Mech._shoot.
func get_quality_factor() -> float:
	var base = TileStatsRegistry.get_stat_by_rarity("AccumulatorTile", "quality_factor_by_rarity", rarity, [0.85, 0.88, 0.91, 0.95, 1.0])
	return min(1.0, base + (level - 1) * 0.005)

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
	return TileStatsRegistry.get_stat("AccumulatorTile", "bank_charge_base", 12.0) * _get_power_multiplier()

func get_bank_amplify() -> float:
	return TileStatsRegistry.get_stat("AccumulatorTile", "bank_amplify_base", 0.5) * _get_power_multiplier()
