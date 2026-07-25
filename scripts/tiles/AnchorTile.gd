class_name AnchorTile
extends HexTile

func _init():
	tile_type = "Anchor"
	category = TileCategory.SPECIAL
	base_color = Color(0.2, 0.2, 0.25) # Dark, heavy grey
	
func get_weight() -> float:
	return TileStatsRegistry.get_stat("AnchorTile", "weight", 8.0)
