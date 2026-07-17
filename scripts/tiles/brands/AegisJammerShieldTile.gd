class_name AegisJammerShieldTile
extends "res://scripts/tiles/JammerModuleTile.gd"

# Corporate Sponsorships (task #17): Aegis Dynamics' signature tile - a
# Jammer Module that's also an AoE ally shield-pulse, with a hard per-hit
# damage cap ("Aegis") against every ELEMENTAL synergy (FIRE/ICE/LIGHTNING/
# VORTEX/POISON/VAMPIRIC - everything except RAW/KINETIC/PIERCE/EXPLOSION,
# per EnergyPacket.SynergyType's real enum order).
#
# Inherits JammerModuleTile's routed-energy jammer capacity wholesale -
# tile_type stays "Jammer Module" (see PowerGridSplitterTile.gd's comment
# for why preserving the base tile_type matters everywhere else in the
# codebase). The shield-pulse and elemental-Aegis are detected separately
# via brand_id == "defensive" in
# Mech._collect_weapon_mounts_and_tile_capabilities(), right alongside the
# existing Jammer Module capacity block.

func _init(forced_synergy: int = -1):
	super._init(forced_synergy)

# JammerModuleTile.get_weight() reads TileStatsRegistry with the hardcoded
# key "JammerModuleTile" - inheriting it as-is would silently read the
# BASE tile's stats.json instead of this brand's own, so this needs an
# explicit override even though the code looks identical.
func get_weight() -> float:
	return TileStatsRegistry.get_stat("AegisJammerShieldTile", "weight", 6.5)

func get_shield_pulse_power() -> float:
	var base = TileStatsRegistry.get_stat("AegisJammerShieldTile", "shield_pulse_power_base", 30.0)
	var coeff = TileStatsRegistry.get_stat("AegisJammerShieldTile", "shield_pulse_power_rarity_coeff", 0.5)
	return base * (1.0 + rarity * coeff)

func get_shield_pulse_radius() -> float:
	return TileStatsRegistry.get_stat("AegisJammerShieldTile", "shield_pulse_radius", 220.0)

func get_shield_pulse_interval() -> float:
	return TileStatsRegistry.get_stat("AegisJammerShieldTile", "shield_pulse_interval", 4.0)
