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
	# probes: things that use negative z_index must still be visible over the baked ground
	await get_tree().process_frame
	var c = cam.position
	var vent = load("res://scripts/hazards/LavaVent.gd").new(); vent.radius = 60.0; vent.position = c + Vector2(-120, 0); m.add_child(vent)
	var sc = load("res://scripts/visuals/ScorchDecals.gd").new(); m.add_child(sc); await get_tree().process_frame; sc.add_mark(c + Vector2(120, 0), 60.0, Color(0.05, 0.04, 0.04))
	var ov = load("res://scripts/visuals/ShallowOverlay.gd").new(); ov.setup([Vector2i(int(c.x / 32) - 2, int(c.y / 32) + 2), Vector2i(int(c.x / 32) - 1, int(c.y / 32) + 2)], 32); m.add_child(ov)
	for f in range(20):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
