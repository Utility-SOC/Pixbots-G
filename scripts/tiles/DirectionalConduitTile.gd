class_name DirectionalConduitTile
extends HexTile

@export var allowed_directions: Array[int] = [0, 3]

func _init():
	tile_type = "Directional Conduit"
	category = TileCategory.CONDUIT

func can_enter_from(direction: int) -> bool:
	return (direction in allowed_directions) and not is_blocked
