class_name PrimeCircuitTile
extends HexTile

# Corporate Sponsorships (task #17): Prime Circuits' signature tile - one hex
# that's simultaneously an Amplifier, an Elemental Infuser, AND a Resonator
# (Natalia: "the efficiency would be all three of those tiles in one").
# Applies the same three formulas those tiles already use (flat amplify,
# RAW -> chosen-element conversion, baseline resonance amplify + remnant
# memory) SEQUENTIALLY to the same packet, reading from this tile's own
# res://tiles/PrimeCircuitTile/stats.json rather than composing three nested
# sub-tile instances - keeps this brand's balance independently tunable
# without the complexity of syncing rarity/level across three child objects.
#
# Doesn't set packet.direction anywhere (matching AmplifierTile/
# ResonatorTile's style, not InfuserTile's) - InfuserTile's own
# `packet.direction = (entry_direction + 3) % 6` resolves back to the exact
# value the packet already had (entry_direction is already the opposite of
# travel direction), so it's a no-op; leaving direction untouched is
# identically correct and simpler.

var secondary_synergy: EnergyPacket.SynergyType = EnergyPacket.SynergyType.RAW
var _remnant_magnitudes: Dictionary = {}

func _init():
	tile_type = "Prime Circuit"
	category = TileCategory.PROCESSOR

func get_weight() -> float:
	return TileStatsRegistry.get_stat("PrimeCircuitTile", "weight", 6.0)

func reset_simulation_state() -> void:
	super.reset_simulation_state()
	_remnant_magnitudes.clear()

# RAW is part of the cycle (the inert/default state), same convention as
# InfuserTile.cycle_synergy/cycle_synergy_backward.
func cycle_synergy():
	secondary_synergy = (secondary_synergy + 1) % EnergyPacket.SynergyType.size()

func cycle_synergy_backward():
	secondary_synergy = (secondary_synergy + EnergyPacket.SynergyType.size() - 1) % EnergyPacket.SynergyType.size()

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	# 1. Amplifier stage
	var amp_mult = TileStatsRegistry.get_stat("PrimeCircuitTile", "amplification", 1.2) * _get_power_multiplier()
	packet.amplify(amp_mult)

	# 2. Infuser stage - RAW = unconfigured, pure pass-through (same guard as
	# InfuserTile: without it, add_synergy below would mint free magnitude).
	if secondary_synergy != EnergyPacket.SynergyType.RAW:
		var conversion_rate = TileStatsRegistry.get_stat("PrimeCircuitTile", "conversion_rate_base", 0.4) \
			+ (rarity * TileStatsRegistry.get_stat("PrimeCircuitTile", "conversion_rate_rarity_coeff", 0.15)) \
			+ ((level - 1) * TileStatsRegistry.get_stat("PrimeCircuitTile", "conversion_rate_level_coeff", 0.05))
		conversion_rate = min(conversion_rate, 1.0)
		packet.convert_synergy(EnergyPacket.SynergyType.RAW, secondary_synergy, conversion_rate)

		var infusion_amount = TileStatsRegistry.get_stat("PrimeCircuitTile", "power_infusion", 2.0) \
			* (1.0 + rarity * TileStatsRegistry.get_stat("PrimeCircuitTile", "infusion_rarity_coeff", 0.5)) \
			* (1.0 + (level - 1) * TileStatsRegistry.get_stat("PrimeCircuitTile", "infusion_level_coeff", 0.1))
		packet.add_synergy(secondary_synergy, infusion_amount)

	# 3. Resonator stage (baseline amplify + remnant memory - the non-Mythic
	# ResonatorTile path; Mythic Sync's 3-way crossing mechanic is deliberately
	# NOT reproduced here, since this tile isn't sitting at a real 3-way
	# crossing the way a standalone Mythic Resonator would be built to).
	var res_mult = 1.0 + (TileStatsRegistry.get_stat("PrimeCircuitTile", "baseline_amplify", 0.15) * _get_power_multiplier())
	if _remnant_magnitudes.size() > 0:
		for k in _remnant_magnitudes:
			packet.add_synergy(k, _remnant_magnitudes[k] * 0.8)
			_remnant_magnitudes[k] *= 0.2
		res_mult += TileStatsRegistry.get_stat("PrimeCircuitTile", "boost_per_remnant", 1.3) * _get_power_multiplier()
	packet.amplify(res_mult)
	for syn in packet.synergies:
		_remnant_magnitudes[syn] = packet.synergies[syn] * 0.15

	return [packet]
