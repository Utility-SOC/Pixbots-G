extends Node

# Soak diagnostic: runs the REAL Main (campaign, high wave) through repeated wave cycles and map rotations and logs
# node / orphan / object counts and frame time per cycle, so leaks show up as a slope. Run windowed:
#   godot --path . --rendering-method gl_compatibility res://scripts/debug/SoakDiag.tscn -- --cycles=30 --start=100 [--no-rotate]
# Prints "SOAK" lines and a final slope summary.

var cycles = 30
var start_wave = 100
var rotate_every = 2
var main: Node

func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + name + "="):
			return a.get_slice("=", 1)
	return def

func _sample(tag: String) -> Dictionary:
	var d = {
		"tag": tag,
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orph": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"objs": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"res": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"mem": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"fps": Performance.get_monitor(Performance.TIME_FPS),
	}
	print("SOAK %-14s nodes=%6d orphans=%5d objs=%7d res=%5d mem=%7.1fMB fps=%4.0f" % [tag, d.nodes, d.orph, d.objs, d.res, d.mem, d.fps])
	return d

func _ready():
	cycles = int(_arg("cycles", "30"))
	start_wave = int(_arg("start", "100"))
	if "--no-rotate" in OS.get_cmdline_user_args():
		rotate_every = 0
	SaveManager.current_game_mode = "campaign"
	SaveManager.save_to_load = ""
	SaveManager.tutorial_completed = true
	SaveManager.pending_run_card = {"map_type": _arg("map", "Desert"), "layout": "auto", "seed": 6}
	main = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	(func(): get_tree().current_scene = main).call_deferred()
	for i in range(60):
		await get_tree().process_frame
	var waited = 0
	while (main.get("player") == null or not is_instance_valid(main.player)) and waited < 900:
		await get_tree().process_frame
		waited += 1
	await get_tree().create_timer(1.0).timeout
	if main.garage_ui and is_instance_valid(main.garage_ui):
		main._close_garage()
		await get_tree().process_frame
	main.current_wave = start_wave
	var first = _sample("start")
	var samples: Array = [first]
	for c in range(cycles):
		if is_instance_valid(main.player):
			main.player.hp = main.player.max_hp # keep the soak alive
		if rotate_every > 0 and c % rotate_every == 1:
			main._rotate_campaign_map_now("", "")
		main._start_wave()
		var t = 0.0
		while t < 60.0 and (main._spawning_wave or main.active_enemies <= 0):
			await get_tree().create_timer(0.25).timeout
			t += 0.25
		# let them fight for a moment, then cut them down
		await get_tree().create_timer(1.5).timeout
		for e in get_tree().get_nodes_in_group("enemy"):
			if is_instance_valid(e) and e.has_method("die"):
				e.hp = 0.0
				e.die()
		t = 0.0
		var before = main.current_wave
		while t < 30.0 and main.current_wave == before:
			await get_tree().create_timer(0.25).timeout
			t += 0.25
		for i in range(40):
			await get_tree().process_frame
		if main.garage_ui and is_instance_valid(main.garage_ui):
			main._close_garage()
		get_tree().paused = false
		samples.append(_sample("cycle %d w%d" % [c + 1, main.current_wave]))
	if samples.size() < 3:
		print_orphan_nodes()
		get_tree().quit(0)
		return
	var a = samples[1]
	var b = samples[samples.size() - 1]
	var n = float(cycles - 1)
	print("SOAK SLOPE per cycle: nodes %+.1f  orphans %+.1f  objs %+.1f  res %+.1f  mem %+.2fMB" % [
		(b.nodes - a.nodes) / n, (b.orph - a.orph) / n, (b.objs - a.objs) / n, (b.res - a.res) / n, (b.mem - a.mem) / n])
	print_orphan_nodes()
	get_tree().quit(0)
