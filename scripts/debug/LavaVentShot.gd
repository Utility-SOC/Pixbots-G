extends Node
# Screenshot of a vent idle / telegraphing / erupting.  godot --path . res://scripts/debug/LavaVentShot.tscn -- --out=/path.png
func _ready():
	var out = "/tmp/vent.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.split("=")[1]
	var world = Node2D.new(); add_child(world)
	var floor_rect = ColorRect.new(); floor_rect.color = Color(0.2, 0.15, 0.13); floor_rect.size = Vector2(500, 200); floor_rect.position = Vector2(-50, -50); floor_rect.z_index = -20
	world.add_child(floor_rect)
	var cam = Camera2D.new(); cam.position = Vector2(200, 50); cam.zoom = Vector2(2.2, 2.2); world.add_child(cam)
	var vents = []
	for i in range(3):
		var v = load("res://scripts/hazards/LavaVent.gd").new(); v.radius = 44.0; world.add_child(v); v.position = Vector2(60 + i * 140, 50); vents.append(v)
		v.set_process(false)
	await get_tree().process_frame
	vents[1]._phase = 1; vents[1]._timer = 0.3; vents[1].queue_redraw()
	vents[2]._phase = 2; vents[2]._timer = 0.2; vents[2].queue_redraw()
	for f in range(6):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
