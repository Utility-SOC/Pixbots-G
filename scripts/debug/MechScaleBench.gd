extends Node
# Where does a crowd of mechs spend its frame time?  Spawns N idle enemy mechs in view and measures average fps
# for several variants (all windowed; needs a real renderer).
#   godot --path . res://scripts/debug/MechScaleBench.tscn -- --n=80
const MechScript = preload("res://scripts/entities/Mech.gd")
var _n := 80
var mechs: Array = []

func _ready():
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--n="): _n = int(a.split("=")[1])
	var cam = Camera2D.new(); cam.position = Vector2(500, 300); cam.zoom = Vector2(0.75, 0.75); add_child(cam)
	var comp = load("res://scripts/core/ComponentEquipment.gd")
	for i in range(_n):
		var m = MechScript.new()
		m.combat_role = ["brawler", "sniper", "scout", "flamethrower"][i % 4]
		m.position = Vector2(60 + (i % 16) * 60, 40 + (i / 16) * 70)
		add_child(m)
		m.equip_component(comp.create_starter_torso(m.combat_role, 1))
		m.refresh_visuals()
		m.set_physics_process(false)
		mechs.append(m)
	await _settle()
	print("MSB n=%d baseline: %s" % [_n, await _measure()])
	for m in mechs: m.visible = false
	print("MSB hidden (no drawing): %s" % await _measure())
	for m in mechs: m.visible = true
	for m in mechs: m.process_mode = Node.PROCESS_MODE_DISABLED
	print("MSB process disabled: %s" % await _measure())
	for m in mechs: m.process_mode = Node.PROCESS_MODE_INHERIT
	var hb = get_tree().get_nodes_in_group("part_hitbox")
	for h in hb: h.get_parent().remove_child(h)
	print("MSB hitboxes removed (%d): %s" % [hb.size(), await _measure()])
	get_tree().quit()

func _settle():
	for f in range(30):
		await get_tree().process_frame

func _measure() -> String:
	var t0 = Time.get_ticks_usec()
	var frames = 90
	for f in range(frames):
		await get_tree().process_frame
	var ms = (Time.get_ticks_usec() - t0) / 1000.0 / frames
	return "%.1f ms/frame (%.0f fps) draws=%d proc=%.1f" % [ms, 1000.0 / ms, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0]
