extends Node

# Sanity check before investing in a real overdraw investigation: does
# Performance.get_monitor(RENDER_*) report real numbers under --headless,
# or does the dummy/headless rendering driver just report 0 for everything?
# This determines whether the rest of this investigation can use the same
# headless methodology as every other perf check this session, or needs a
# real windowed run instead.

func _ready():
	var world = Node2D.new()
	add_child(world)

	for i in 50:
		var poly = Polygon2D.new()
		poly.polygon = PackedVector2Array([Vector2(-20,-20), Vector2(20,-20), Vector2(20,20), Vector2(-20,20)])
		poly.color = Color(1.0, 0.5, 0.2, 0.3)
		poly.material = CanvasItemMaterial.new()
		poly.material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		poly.position = Vector2(randf_range(0, 400), randf_range(0, 400))
		world.add_child(poly)

	for i in 5:
		await get_tree().process_frame

	var draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var objects = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var primitives = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)

	print("draw_calls=%d objects=%d primitives=%d" % [draw_calls, objects, primitives])
	if draw_calls == 0 and objects == 0 and primitives == 0:
		print("RESULT: headless rendering stats appear to be ALL ZERO - dummy driver doesn't track these, need a different approach")
	else:
		print("RESULT: headless rendering stats report real numbers - can proceed with this methodology")

	get_tree().quit(0)
