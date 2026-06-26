class_name DirectionalConduitTile
extends HexTile

var rotation_steps: int = 0

func _init():
	tile_type = "Directional Conduit"
	category = TileCategory.CONDUIT

func get_exit_direction(entry_direction: int) -> int:
	return (entry_direction + 3) % 6

func can_enter_from(direction: int) -> bool:
	if is_blocked: return false
	var allowed1 = rotation_steps % 6
	var allowed2 = (rotation_steps + 3) % 6
	return direction == allowed1 or direction == allowed2
