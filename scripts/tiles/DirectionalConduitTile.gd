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

# Was missing entirely - GarageGridRenderer's "E to rotate" handler checks
# tile.has_method("rotate") before doing anything, so pressing E over a
# Directional Conduit silently did nothing even though rotation_steps
# above is fully wired up and meaningful for this tile. ReflectorTile has
# the same method; mirroring its implementation here.
func rotate(clockwise: bool = true):
	if clockwise:
		rotation_steps = (rotation_steps + 1) % 6
	else:
		rotation_steps = (rotation_steps - 1) % 6
		if rotation_steps < 0:
			rotation_steps += 6
