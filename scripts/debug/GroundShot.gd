extends Node
# Screenshot of real generated ground.  godot --path . res://scripts/debug/GroundShot.tscn -- --out=/path.png [--type=Forest]
func _ready():
	var out = "/tmp/ground.png"
	var t = "Forest"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.split("=")[1]
		elif a.begins_with("--type="): t = a.split("=")[1]
	var m = load("res://scripts/core/MapGenerator.gd").new()
	m.map_type = t
	add_child(m)
	var cam = Camera2D.new()
	cam.position = Vector2(m.width, m.height) * m.tile_size * 0.5
	cam.zoom = Vector2(0.75, 0.75)
	add_child(cam)
	for f in range(20):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
