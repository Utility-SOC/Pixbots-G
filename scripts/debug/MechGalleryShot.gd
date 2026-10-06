extends Node
# Screenshot of one mech per role plus the player.  godot --path . res://scripts/debug/MechGalleryShot.tscn -- --out=/path.png [--rarity=2]
const MechScript = preload("res://scripts/entities/Mech.gd")
func _ready():
	var out = "/tmp/gallery.png"
	var rarity = 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.split("=")[1]
		elif a.begins_with("--rarity="): rarity = int(a.split("=")[1])
	var bg = ColorRect.new(); bg.color = Color(0.32, 0.4, 0.3); bg.size = Vector2(1000, 330); bg.position = Vector2(-40, -60); bg.z_index = -50; add_child(bg)
	var cam = Camera2D.new(); cam.position = Vector2(440, 100); cam.zoom = Vector2(1.3, 1.3); add_child(cam)
	var roles = ["player", "brawler", "sniper", "scout", "flamethrower", "jammer", "commander", "ambusher"]
	var comp = load("res://scripts/core/ComponentEquipment.gd")
	for i in range(roles.size()):
		var m = MechScript.new()
		if roles[i] == "player":
			m.is_player = true
		else:
			m.combat_role = roles[i]
		m.position = Vector2(30 + (i % 4) * 130, 20 + (i / 4) * 140)
		add_child(m)
		m.set_physics_process(false)
		if roles[i] != "player":
			var torso = comp.create_starter_torso(roles[i], rarity)
			m.equip_component(torso)
		m.refresh_visuals()
	for f in range(20):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
