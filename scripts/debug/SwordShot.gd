extends Node
# Renders kinetic sword missiles of increasing damage in flight and at impact, for a screenshot.
#   godot --path . res://scripts/debug/SwordShot.tscn -- --out=/path.png
const ShellScript = preload("res://scripts/attacks/MortarShell.gd")
func _ready():
	var out = "/tmp/sword.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.split("=")[1]
	var world = Node2D.new(); add_child(world)
	var cam = Camera2D.new(); cam.position = Vector2(300, 120); cam.zoom = Vector2(2.2, 2.2); world.add_child(cam)
	var shells = []
	var dmgs = [150.0, 600.0, 2500.0, 10000.0, 60000.0]
	for i in range(dmgs.size()):
		for row in range(2):
			var sh = ShellScript.new()
			world.add_child(sh)
			var tgt = Vector2(80 + i * 110, 60 + row * 120)
			sh.setup(tgt + Vector2(0, -90), tgt, 1.0, dmgs[i], {EnergyPacket.SynergyType.KINETIC: dmgs[i]}, true, null)
			sh._elapsed = 0.5 if row == 0 else sh.flight_time
			if row == 1:
				sh._landed = true
				sh._impact_elapsed = 0.09
			shells.append(sh)
	for f in range(3):
		await get_tree().process_frame
	for sh in shells:
		sh.set_process(false)
		sh.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
