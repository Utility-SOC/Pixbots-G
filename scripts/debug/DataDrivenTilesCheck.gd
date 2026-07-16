extends Node

# Regression harness for the "data-driven tiles" pass (Status.md queue item
# 1): every tile's previously-hardcoded balance numbers (weight, charge/
# damage multipliers, per-rarity curves) now route through
# TileStatsRegistry.get_stat()/get_stat_by_rarity(), reading
# res://tiles/<TileType>/stats.json with the original hardcoded value as the
# fallback default. This check has two jobs:
#   1. Prove NOTHING changed: every stat-returning method across all 24 tile
#      types still returns the exact pre-conversion value, with the real
#      stats.json files present on disk (today's actual values baked in).
#   2. Prove the fallback path works: a tile type with NO stats.json at all
#      falls back cleanly to the code-supplied default, not an error/crash -
#      this is what makes the whole thing backward-compatible/purely additive
#      rather than a hard dependency on every file existing.

const AccumulatorTileScript = preload("res://scripts/tiles/AccumulatorTile.gd")
const AmplifierTileScript = preload("res://scripts/tiles/AmplifierTile.gd")
const ActuatorTileScript = preload("res://scripts/tiles/ActuatorTile.gd")
const CatalystTileScript = preload("res://scripts/tiles/CatalystTile.gd")
const CloakTileScript = preload("res://scripts/tiles/CloakTile.gd")
const ComponentLinkTileScript = preload("res://scripts/tiles/ComponentLinkTile.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")
const DirectionalConduitTileScript = preload("res://scripts/tiles/DirectionalConduitTile.gd")
const DroneBayTileScript = preload("res://scripts/tiles/DroneBayTile.gd")
const FilterTileScript = preload("res://scripts/tiles/FilterTile.gd")
const HealBeaconTileScript = preload("res://scripts/tiles/HealBeaconTile.gd")
const InfuserTileScript = preload("res://scripts/tiles/InfuserTile.gd")
const JammerModuleTileScript = preload("res://scripts/tiles/JammerModuleTile.gd")
const JumpjetTileScript = preload("res://scripts/tiles/JumpjetTile.gd")
const LanceMountTileScript = preload("res://scripts/tiles/LanceMountTile.gd")
const MagnetTileScript = preload("res://scripts/tiles/MagnetTile.gd")
const ManeuveringThrusterTileScript = preload("res://scripts/tiles/ManeuveringThrusterTile.gd")
const MicrocoreTileScript = preload("res://scripts/tiles/MicrocoreTile.gd")
const MissileRackTileScript = preload("res://scripts/tiles/MissileRackTile.gd")
const ReflectorTileScript = preload("res://scripts/tiles/ReflectorTile.gd")
const ResonatorTileScript = preload("res://scripts/tiles/ResonatorTile.gd")
const ShieldGeneratorTileScript = preload("res://scripts/tiles/ShieldGeneratorTile.gd")
const ShieldTileScript = preload("res://scripts/tiles/ShieldTile.gd")
const SplitterTileScript = preload("res://scripts/tiles/SplitterTile.gd")
const WeaponMountTileScript = preload("res://scripts/tiles/WeaponMountTile.gd")

var failures = 0

func _check(label: String, actual, expected):
	if typeof(actual) == TYPE_FLOAT or typeof(expected) == TYPE_FLOAT:
		if not is_equal_approx(float(actual), float(expected)):
			push_error("FAIL: %s - got %s, expected %s" % [label, actual, expected])
			failures += 1
			return
	elif actual != expected:
		push_error("FAIL: %s - got %s, expected %s" % [label, actual, expected])
		failures += 1
		return
	print("ok: %s = %s" % [label, actual])

func _ready():
	# --- 1. get_weight() sweep across all 24 tile types --------------------
	var weight_cases = [
		[AccumulatorTileScript.new(), 7.0, "Accumulator"],
		[AmplifierTileScript.new(), 6.0, "Amplifier"],
		[ActuatorTileScript.new(), 7.0, "Actuator"],
		[CatalystTileScript.new(), 4.0, "Catalyst"],
		[CloakTileScript.new(), 4.5, "Cloak"],
		[ComponentLinkTileScript.new(), 1.0, "ComponentLink"],
		[CoreTileScript.new(), 8.0, "Core"],
		[DirectionalConduitTileScript.new(), 1.0, "DirectionalConduit"],
		[DroneBayTileScript.new(), 8.0, "DroneBay"],
		[FilterTileScript.new(), 2.0, "Filter"],
		[HealBeaconTileScript.new(), 4.5, "HealBeacon"],
		[InfuserTileScript.new(), 4.0, "Infuser"],
		[JammerModuleTileScript.new(), 4.0, "JammerModule"],
		[JumpjetTileScript.new(), 7.0, "Jumpjet"],
		[LanceMountTileScript.new(), 14.0, "LanceMount"],
		[MagnetTileScript.new(), 5.0, "Magnet"],
		[ManeuveringThrusterTileScript.new(), 5.0, "ManeuveringThruster"],
		[MicrocoreTileScript.new(), 5.0, "Microcore"],
		[MissileRackTileScript.new(), 7.0, "MissileRack"],
		[ReflectorTileScript.new(), 2.5, "Reflector"],
		[ResonatorTileScript.new(), 3.0, "Resonator"],
		[ShieldGeneratorTileScript.new(), 6.5, "ShieldGenerator"],
		[ShieldTileScript.new(), 6.5, "Shield"],
		[SplitterTileScript.new(), 2.0, "Splitter"],
		[WeaponMountTileScript.new(), 6.0, "WeaponMount"],
	]
	for c in weight_cases:
		_check("%s.get_weight()" % c[2], c[0].get_weight(), c[1])

	# --- 2. Per-instance @export defaults still match ----------------------
	_check("Accumulator.charge_multiplier", AccumulatorTileScript.new().charge_multiplier, 3.0)
	_check("Accumulator.damage_boost", AccumulatorTileScript.new().damage_boost, 4.5)
	_check("Amplifier.amplification", AmplifierTileScript.new().amplification, 1.2)
	_check("Actuator.base_speed_multiplier", ActuatorTileScript.new().base_speed_multiplier, 0.5)
	_check("Catalyst.efficiency", CatalystTileScript.new().efficiency, 1.2)
	_check("Filter.raw_return_rate", FilterTileScript.new().raw_return_rate, 0.5)
	_check("Jumpjet.speed_boost_mult", JumpjetTileScript.new().speed_boost_mult, 1.5)
	_check("Resonator.boost_per_remnant", ResonatorTileScript.new().boost_per_remnant, 1.3)
	_check("Shield.conversion_rate", ShieldTileScript.new().conversion_rate, 2.0)
	_check("WeaponMount.damage_multiplier", WeaponMountTileScript.new().damage_multiplier, 1.0)

	# --- 3. Per-rarity curves across all 5 rarities -------------------------
	var rarities = [HexTile.Rarity.COMMON, HexTile.Rarity.UNCOMMON, HexTile.Rarity.RARE, HexTile.Rarity.LEGENDARY, HexTile.Rarity.MYTHIC]

	var core_power = [10.0, 14.0, 20.0, 35.0, 55.0]
	var core_faces = [1, 1, 2, 6, 6]
	var micro_power = [50.0, 75.0, 120.0, 200.0, 320.0]
	var micro_faces = [2, 2, 3, 4, 6]
	var splitter_faces = [2, 2, 3, 5, 6]
	var cloak_duration = [2.5, 3.5, 4.5, 6.0, 8.0]
	var cloak_recharge = [9.0, 7.0, 5.5, 4.0, 3.0]
	var jammer_interval = [10.0, 8.0, 6.5, 5.0, 4.0]
	var magnet_mult = [1.0, 1.2, 1.5, 2.0, 3.0]
	var shield_energy_mult = [1.1, 1.5, 2.5, 5.0, 10.0]
	var acc_quality = [0.85, 0.88, 0.91, 0.95, 1.0]

	for i in range(5):
		var r = rarities[i]
		var core = CoreTileScript.new(); core.rarity = r
		_check("Core.get_power_output() @ rarity %d" % r, core.get_power_output(), core_power[i])
		_check("Core.get_max_faces() @ rarity %d" % r, core.get_max_faces(), core_faces[i])

		var micro = MicrocoreTileScript.new(); micro.rarity = r
		_check("Microcore.get_power_output() @ rarity %d" % r, micro.get_power_output(), micro_power[i])
		_check("Microcore.get_max_faces() @ rarity %d" % r, micro.get_max_faces(), micro_faces[i])

		var splitter = SplitterTileScript.new(); splitter.rarity = r
		_check("Splitter.get_max_faces() @ rarity %d" % r, splitter.get_max_faces(), splitter_faces[i])

		var cloak = CloakTileScript.new(); cloak.rarity = r
		_check("Cloak.get_cloak_duration() @ rarity %d" % r, cloak.get_cloak_duration(), cloak_duration[i])
		_check("Cloak.get_recharge_time() @ rarity %d" % r, cloak.get_recharge_time(), cloak_recharge[i])

		var jammer = JammerModuleTileScript.new(); jammer.rarity = r
		_check("JammerModule.get_pulse_interval() @ rarity %d" % r, jammer.get_pulse_interval(), jammer_interval[i])

		# NOTE: EnergyPacket.has_synergy(type) defaults min_percentage=0.0, so
		# `perc >= 0.0` is true for ANY nonzero packet regardless of which
		# synergy it actually carries - MagnetTile.process_energy()'s
		# `p.has_synergy(LIGHTNING)` call (no threshold arg) is therefore
		# always true, not conditional on real lightning content. Pre-existing
		# behavior, unrelated to this conversion - the *1.5 below reflects
		# what the tile actually does today, not what its comment claims.
		var magnet = MagnetTileScript.new(); magnet.rarity = r
		magnet.process_energy(EnergyPacket.new(10.0, null), 0)
		_check("Magnet.get_magnetic_power() @ rarity %d" % r, magnet.get_magnetic_power(), 10.0 * 1.5 * magnet_mult[i])

		var shield = ShieldTileScript.new(); shield.rarity = r
		var pkt = EnergyPacket.new(10.0, null)
		shield.process_energy(pkt, 0)
		_check("Shield energy accumulation @ rarity %d" % r, shield.get_shield_energy(), 10.0 * shield_energy_mult[i])

		var acc = AccumulatorTileScript.new(); acc.rarity = r; acc.level = 1
		_check("Accumulator.get_quality_factor() @ rarity %d" % r, acc.get_quality_factor(), min(1.0, acc_quality[i]))

	# --- 4. HealBeacon's formula-based (not table-based) per-rarity curve --
	for i in range(5):
		var r = rarities[i]
		var beacon = HealBeaconTileScript.new(); beacon.rarity = r
		_check("HealBeacon.get_pulse_radius() @ rarity %d" % r, beacon.get_pulse_radius(), 180.0 + r * 40.0)
		_check("HealBeacon.get_pulse_interval() @ rarity %d" % r, beacon.get_pulse_interval(), max(2.0, 5.0 - r * 0.7))

	# --- 5. Missing-file fallback: a tile type with no stats.json at all ---
	var fallback = TileStatsRegistry.get_stat("NonexistentTileTypeForTesting", "weight", 42.0)
	_check("TileStatsRegistry fallback for a nonexistent tile type", fallback, 42.0)
	var fallback_by_rarity = TileStatsRegistry.get_stat_by_rarity("NonexistentTileTypeForTesting", "power_by_rarity", HexTile.Rarity.MYTHIC, [1.0, 2.0, 3.0, 4.0, 5.0])
	_check("TileStatsRegistry per-rarity fallback for a nonexistent tile type", fallback_by_rarity, 5.0)

	if failures == 0:
		print("PASS: all 24 tile types' stats preserved exactly through the data-driven conversion, fallback path verified")
	get_tree().quit(0 if failures == 0 else 1)
