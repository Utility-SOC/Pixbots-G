extends "res://scripts/tiles/StatusResistTile.gd"

# Remediation Matrix (owner direction 2026-10-09, docs/ELEMENTAL_REWORK_SPEC.md): the Mythic, SUPER rare Guard that handles
# ALL conditions. Same energy-fed rule as the single Guards (StatusResistTile.gd), but it needs 6x the energy for the same
# fraction (energy_for_max 9000 vs 1500) and its cap is lower (70% vs 90%): it saves grid space in return for being less
# focused than the Legendary one-condition Guards.

const COVERED = ["concussed", "paralyzed", "frozen", "burning", "poisoned", "vortexed"]

func _init():
	tile_type = "Remediation Matrix"
	category = TileCategory.OUTPUT
	base_color = Color(0.85, 0.75, 1.0)
	stats_key = "RemediationMatrixTile"

func get_resisted_statuses() -> Array:
	return COVERED
