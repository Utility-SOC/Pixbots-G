extends Node2D

# A short-lived jagged lightning chain through a list of world positions (a missile's impact
# arcing out to nearby enemies). Geometry is built once; it just fades out.

const LIFETIME = 0.35

var _points: PackedVector2Array = PackedVector2Array()
var _color: Color = Color(1.0, 0.95, 0.4)
var _age: float = 0.0

func setup(world_points: Array, color: Color) -> void:
	_color = color
	z_index = 60
	var pts = PackedVector2Array()
	for i in range(world_points.size() - 1):
		var a: Vector2 = world_points[i]
		var b: Vector2 = world_points[i + 1]
		var segs = max(3, int(a.distance_to(b) / 22.0))
		var ortho = (b - a).orthogonal().normalized()
		pts.append(a)
		for k in range(1, segs):
			var f = float(k) / float(segs)
			pts.append(a.lerp(b, f) + ortho * randf_range(-9.0, 9.0))
	if not world_points.is_empty():
		pts.append(world_points[world_points.size() - 1])
	_points = pts
	global_position = Vector2.ZERO # points are world coordinates

func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	if _points.size() < 2:
		return
	var a = 1.0 - _age / LIFETIME
	draw_polyline(_points, Color(_color.r, _color.g, _color.b, 0.35 * a), 7.0)
	draw_polyline(_points, Color(_color.r, _color.g, _color.b, 0.9 * a), 3.0)
	draw_polyline(_points, Color(1, 1, 1, a), 1.2)
