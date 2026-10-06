extends Node
# Screenshot of the player mech with each build identity.  godot --path . res://scripts/debug/PlayerIdentityShot.tscn -- --out=/path.png
const MechScript = preload("res://scripts/entities/Mech.gd")
func _ready():
	var out = "/tmp/identity.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.split("=")[1]
	var bg = ColorRect.new(); bg.color = Color(0.3, 0.38, 0.28); bg.size = Vector2(1100, 330); bg.position = Vector2(-40, -70); bg.z_index = -50; add_child(bg)
	var cam = Camera2D.new(); cam.position = Vector2(470, 80); cam.zoom = Vector2(1.25, 1.25); add_child(cam)
	var syns = [-1, 1, 2, 3, 4, 5, 6, 7, 9]
	for i in range(syns.size()):
		var m = MechScript.new()
		m.is_player = true
		m.position = Vector2(30 + (i % 5) * 120, 10 + (i / 5) * 130)
		add_child(m)
		m.set_physics_process(false)
	for f in range(10):
		await get_tree().process_frame
	for i in range(syns.size()):
		var m2 = get_child(i + 2)
		m2.identity_synergy = syns[i] # set after the mech's own recalculation (which finds no weapons here)
		m2.refresh_visuals()
	for f in range(20):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
