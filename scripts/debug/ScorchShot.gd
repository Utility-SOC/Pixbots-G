extends Node
# Screenshot of scorch decals over a light floor.  godot --path . res://scripts/debug/ScorchShot.tscn -- --out=/path.png
func _ready():
	const Scorch = preload("res://scripts/visuals/ScorchDecals.gd")
	var out = "/tmp/scorch.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.split("=")[1]
	var world = Node2D.new(); add_child(world)
	var floor_rect = ColorRect.new(); floor_rect.color = Color(0.55, 0.5, 0.38); floor_rect.size = Vector2(900, 400); floor_rect.position = Vector2(-50, -50); floor_rect.z_index = -20
	world.add_child(floor_rect)
	var cam = Camera2D.new(); cam.position = Vector2(300, 100); world.add_child(cam)
	var d = Scorch.new(); world.add_child(d)
	await get_tree().process_frame
	for i in range(12):
		d.add_mark(Vector2(60 + i * 50, 100 + 40 * sin(i * 1.7)), 30 + (i % 4) * 25, Color(0.05, 0.04, 0.04))
	for f in range(10):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
