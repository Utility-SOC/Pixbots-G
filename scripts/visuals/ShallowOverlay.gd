extends Node2D

# Static pale tint over shallow-water tiles (see MapGenerator._mark_shallows). Drawn once; Godot keeps the
# command list, so there is no per-frame cost.

var _cells: Array = []
var _tile := 32

func setup(cells: Array, tile_size: int) -> void:
	_cells = cells
	_tile = tile_size
	z_index = -9

func _draw() -> void:
	var col = Color(0.75, 0.95, 1.0, 0.42)
	for c in _cells:
		draw_rect(Rect2(c.x * _tile, c.y * _tile, _tile, _tile), col)
