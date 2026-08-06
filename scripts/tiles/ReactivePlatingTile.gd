class_name ReactivePlatingTile
extends HexTile

# Reactive armor (design request: "reactive armor options which melee
# mechs will abuse") - explosive plating that counter-hits whatever just
# damaged the wearer, IF the attacker was close enough for that to make
# physical sense. See Mech.gd's has_reactive_plating field comment for the
# full trigger design (the actual counter-hit logic lives in
# Mech.apply_damage - this tile is pure config, same pattern as
# AnchorTile.gd's passive vortex immunity: zero energy routing needed,
# effect comes purely from being equipped).

func _init():
	tile_type = "Reactive Plating"
	category = TileCategory.SPECIAL
	base_color = Color(0.55, 0.18, 0.15) # dull explosive-ordnance red

func get_weight() -> float:
	return TileStatsRegistry.get_stat("ReactivePlatingTile", "weight", 7.0) # same defensive-tile weight class as Anchor (8.0) - this is armor plating, not routing hardware
