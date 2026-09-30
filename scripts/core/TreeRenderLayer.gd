class_name TreeRenderLayer
extends Node2D

# Draws every tree on the map from a handful of chunked canvas items instead
# of a Polygon2D + Line2D pair per tree. Chunking keeps off-screen culling.

const CHUNK_PX = 512.0
static var TREE_SHAPE := PackedVector2Array([Vector2(0, -12), Vector2(8, 8), Vector2(-8, 8)])
static var TREE_OUTLINE := PackedVector2Array([Vector2(0, -12), Vector2(8, 8), Vector2(-8, 8), Vector2(0, -12)])
const FILL = Color(0.05, 0.3, 0.05)
const OUTLINE = Color(0.9, 0.95, 0.85, 0.9)

var _chunks: Dictionary = {}

func add_tree(pos: Vector2) -> void:
	var key = Vector2i(floori(pos.x / CHUNK_PX), floori(pos.y / CHUNK_PX))
	var chunk = _chunks.get(key)
	if chunk == null:
		chunk = _TreeChunk.new()
		add_child(chunk)
		_chunks[key] = chunk
	chunk.trees.append(pos)
	chunk.queue_redraw()

func remove_tree(pos: Vector2) -> void:
	var key = Vector2i(floori(pos.x / CHUNK_PX), floori(pos.y / CHUNK_PX))
	var chunk = _chunks.get(key)
	if chunk == null:
		return
	var i = chunk.trees.find(pos)
	if i >= 0:
		chunk.trees.remove_at(i)
		chunk.queue_redraw()

class _TreeChunk extends Node2D:
	var trees: PackedVector2Array = PackedVector2Array()

	func _draw() -> void:
		for pos in trees:
			draw_set_transform(pos)
			draw_colored_polygon(TreeRenderLayer.TREE_SHAPE, TreeRenderLayer.FILL)
			draw_polyline(TreeRenderLayer.TREE_OUTLINE, TreeRenderLayer.OUTLINE, 2.0)
