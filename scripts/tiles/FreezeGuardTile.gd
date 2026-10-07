extends "res://scripts/tiles/StatusResistTile.gd"

# Freeze Guard: shortens the "frozen" status on its wearer in proportion to the energy fed into it.
# See StatusResistTile.gd for the rules and the cost.

func _init():
	tile_type = "Freeze Guard"
	category = TileCategory.OUTPUT # an energy sink, like the Heal Beacon
	base_color = Color(0.5,0.9,0.95)
	resisted_status = "frozen"
	stats_key = "FreezeGuardTile"
