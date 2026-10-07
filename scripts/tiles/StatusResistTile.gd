extends HexTile

# (No class_name on purpose: a brand-new global class is not resolvable until the editor re-scans, which broke the
# subclasses' `extends`. Subclasses extend this file by path; everything else loads tiles by path too.)
#
# Base for the Stun / Shock / Freeze Guard tiles (owner request 2026-10-07: "there should be a stun tile, a shock
# tile, and a freeze tile ... the resistance will cost grid capacity", and "strength proportional to the amount of
# energy received ... lightweight is more important than nuance"). A Guard shortens the duration of one crowd-
# control status applied to its wearer:
#   Stun Guard   -> "concussed"  (Explosion proc: move speed x0.1)
#   Shock Guard  -> "paralyzed"  (Lightning proc: move speed 0)
#   Freeze Guard -> "frozen"     (Ice proc: move speed x0.4)
#
# ENERGY-FED, like the Heal Beacon / Jammer / Cloak sinks: it absorbs whatever energy the grid routes into it
# (stored_energy += magnitude * (1 + rarity * 0.5), same intake as the Heal Beacon, so rarity is a better converter).
# Resistance is simply proportional to that intake, computed ONCE per grid recalculation (no per-frame work):
#       resistance = clamp(energy / energy_for_max, 0, 1) * max_resist
# so an unfed Guard does nothing, half the energy gives half the protection, and the cap (max_resist, default 90%)
# means no build is ever fully immune. Several Guards of the same kind simply add up to the same cap.
#
# THE COST ("grid capacity"): the Guard sits in a cell that could hold something else, weighs 3.0 (mass slows the
# mech) and the energy it swallows no longer reaches weapons or modules. Tunables: tiles/<Kind>GuardTile/stats.json
# (energy_for_max, max_resist, weight).
#
# LATER (owner's heat design, see Status.md): the Freeze Guard is meant to become a heat sink on a separate, simpler
# heat-pipe layer once Heat exists; until then it is this tile.

var resisted_status: String = "" # StatusEffectRunner effect name, set by subclasses
var stats_key: String = "StatusResistTile" # tiles/<stats_key>/stats.json
var stored_energy: float = 0.0

func process_energy(packet: EnergyPacket, _entry_direction: int, _grid: Node = null, _entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	if packet.magnitude <= 0.0 or not packet.is_active:
		return []
	packet.is_active = false
	stored_energy += packet.magnitude * (1.0 + rarity * 0.5)
	return []

# Read-and-reset, once per Mech._recalculate_grid (same contract as HealBeaconTile.get_heal_energy).
func get_guard_energy() -> float:
	var e := stored_energy
	stored_energy = 0.0
	return e

func get_max_resist() -> float:
	return TileStatsRegistry.get_stat(stats_key, "max_resist", 0.9)

# Resistance this tile contributes for `energy` (linear in energy, capped at max_resist).
func resist_for_energy(energy: float) -> float:
	var full: float = maxf(TileStatsRegistry.get_stat(stats_key, "energy_for_max", 1500.0), 1.0)
	return clampf(energy / full, 0.0, 1.0) * get_max_resist()

func get_weight() -> float:
	return TileStatsRegistry.get_stat(stats_key, "weight", 3.0)
