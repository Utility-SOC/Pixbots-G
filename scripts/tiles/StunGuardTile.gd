extends "res://scripts/tiles/StatusResistTile.gd"

# Stun Guard: shortens the "concussed" status on its wearer in proportion to the energy fed into it.
# See StatusResistTile.gd for the rules and the cost.

func _init():
	tile_type = "Stun Guard"
	category = TileCategory.OUTPUT # an energy sink, like the Heal Beacon
	base_color = Color(0.9,0.7,0.2)
	resisted_status = "concussed"
	stats_key = "StunGuardTile"
