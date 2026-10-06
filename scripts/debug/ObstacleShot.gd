extends Node
# Screenshot of every destructible obstacle type, one flashing.  godot --path . res://scripts/debug/ObstacleShot.tscn -- --out=/path.png
func _ready():
	var out = "/tmp/obstacles.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.split("=")[1]
	var bg = ColorRect.new(); bg.color = Color(0.4, 0.55, 0.35); bg.size = Vector2(400, 120); bg.position = Vector2(-30, -30); bg.z_index = -5; add_child(bg)
	var cam = Camera2D.new(); cam.position = Vector2(160, 30); cam.zoom = Vector2(3.2, 3.2); add_child(cam)
	var names = ["Boulder", "Cactus", "IceBoulder", "LavaRock", "StoneWall"]
	var obs = []
	for i in range(names.size()):
		var o = load("res://scripts/core/DestructibleObstacle.gd").new()
		o.obstacle_name = names[i]
		o.position = Vector2(30 + i * 70, 30)
		add_child(o)
		obs.append(o)
	await get_tree().process_frame
	obs[0].apply_damage(5.0, "KINETIC") # absorbed hit -> flash
	for f in range(3):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
