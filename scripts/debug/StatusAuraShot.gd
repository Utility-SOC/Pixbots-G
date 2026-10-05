extends Node
# Screenshot of a burning bot, a poisoned bot, and a bot that is both.
#   godot --path . res://scripts/debug/StatusAuraShot.tscn -- --out=/path.png
const MechScript = preload("res://scripts/entities/Mech.gd")
func _ready():
	var out = "/tmp/aura.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.split("=")[1]
	var world = Node2D.new(); add_child(world)
	var cam = Camera2D.new(); cam.position = Vector2(230, 60); cam.zoom = Vector2(2.4, 2.4); world.add_child(cam)
	var kinds = [["burning"], ["poisoned"], ["frozen"], ["paralyzed"], ["frozen", "paralyzed"], []]
	for i in range(kinds.size()):
		var m = MechScript.new()
		world.add_child(m)
		m.set_physics_process(false)
		m.global_position = Vector2(30 + i * 80, 60)
		for st in kinds[i]:
			m.apply_status(st, 30.0)
	for f in range(40):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
