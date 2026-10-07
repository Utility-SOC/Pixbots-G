extends "res://scripts/tiles/StatusResistTile.gd"

# Shock Guard: shortens the "paralyzed" status on its wearer in proportion to the energy fed into it.
# See StatusResistTile.gd for the rules and the cost.

func _init():
	tile_type = "Shock Guard"
	category = TileCategory.OUTPUT # an energy sink, like the Heal Beacon
	base_color = Color(0.6,0.8,1.0)
	resisted_status = "paralyzed"
	stats_key = "ShockGuardTile"
