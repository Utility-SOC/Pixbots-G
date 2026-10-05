extends Node

# End-to-end frame-time benchmark of the REAL wave loop (real squads, real
# spawn stagger, real AI). Run windowed:
#   godot --path . res://scripts/debug/BenchGame.tscn -- --wave=12 --seconds=40
# Options: --map=TYPE (force a map type), --wave=N (starting wave, scales enemy count), --seconds=S,
# --nofire, --rate=N (fps cap; default uncapped/no vsync).
# Player gets unlimited lives and full HP so the run can't end early.
# Output: one BENCH_SEC line per second, then a BENCH summary line.

var _wave := 12
var _seconds := 40.0
var _fire := true
var _cap := 0
var _main: Node
var _t := 0.0
var _phase := 0
var _frames: Array[float] = []
var _sec_frames: Array[float] = []
var _sec_t := 0.0
var _peak_enemies := 0
var _peak_nodes := 0
var _hist_done := false
var _seed := 1
var _garage_at := -1.0
var _swarm := 0
var _swarm_spawned := 0
var _swarm_ring := 700.0
var _cum := {"shape": 0.0, "loadout": 0.0, "visual": 0.0, "replay": 0.0, "spawn": 0.0}
var _garage_done := false
var _prep_logged := false
var _map_type := ""
var _notrees := false
var _nomusic := false
var _presolve := false
var _presolve_state := 0
var _off: PackedStringArray = PackedStringArray()

func _ready():
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--wave="): _wave = int(a.split("=")[1])
		elif a.begins_with("--seconds="): _seconds = float(a.split("=")[1])
		elif a.begins_with("--rate="): _cap = int(a.split("=")[1])
		elif a == "--nofire": _fire = false
		elif a.begins_with("--seed="): _seed = int(a.split("=")[1])
		elif a.begins_with("--map="): _map_type = a.split("=")[1]
		elif a.begins_with("--swarm="): _swarm = int(a.split("=")[1])
		elif a.begins_with("--swarmring="): _swarm_ring = float(a.split("=")[1])
		elif a.begins_with("--garage="): _garage_at = float(a.split("=")[1])
		elif a == "--notrees": _notrees = true
		elif a == "--nomusic": _nomusic = true
		elif a == "--presolve": _presolve = true
		elif a.begins_with("--off="): _off = a.split("=")[1].split(",")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = _cap
	RenderingServer.viewport_set_measure_render_time(get_tree().root.get_viewport_rid(), true)
	seed(_seed)
	if _nomusic:
		ProceduralMusic.set_process(false)
		ProceduralMusic.stop()
		AudioManager._quitting = true
	if _map_type != "":
		SaveManager.pending_run_card = {"map_type": _map_type, "layout": "auto", "seed": 0}
	if OS.get_cmdline_user_args().has("--listnodes"):
		for c in get_tree().root.get_children():
			print("BENCH_ROOT ", c.name, " ", c.get_class())
	call_deferred("_plant_root_probes")
	var probe_a = load("res://scripts/debug/FrameSplitProbe.gd").new()
	var probe_b = load("res://scripts/debug/FrameSplitProbe.gd").new()
	probe_b.is_last = true
	get_tree().root.add_child.call_deferred(probe_a)
	get_tree().root.add_child.call_deferred(probe_b)
	_main = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(_main)
	(func(): get_tree().current_scene = _main).call_deferred()

func _describe(n: Node) -> String:
	var sc = ""
	if n.get_script():
		sc = str(n.get_script().resource_path).get_file()
	var kids = []
	for k in n.get_children():
		kids.append((str(k.get_script().resource_path).get_file() if k.get_script() else k.get_class()))
	return "%s{%s}[%s]" % [n.get_class(), sc, ",".join(kids.slice(0, 5))]

func _mk_probe(lbl: String) -> Node:
	var pr = load("res://scripts/debug/TreeProbe.gd").new()
	pr.label = lbl
	return pr

func _plant_root_probes():
	var root = get_tree().root
	root.add_child(_mk_probe("__first"))
	root.move_child(root.get_child(root.get_child_count() - 1), 0)
	var names = []
	for c in root.get_children():
		if c.get_script() and str(c.get_script().resource_path).ends_with("TreeProbe.gd"):
			continue
		names.append(c)
	for c in names:
		var pr = _mk_probe("after:" + str(c.name))
		root.add_child(pr)
		root.move_child(pr, c.get_index() + 1)
	root.add_child(_mk_probe("__last"))

var _main_probed := false
func _plant_main_probes():
	_main_probed = true
	var nodes = []
	for c in _main.get_children():
		nodes.append(c)
	for c in nodes:
		var pr = _mk_probe("main/after:" + _describe(c))
		_main.add_child(pr)
		_main.move_child(pr, c.get_index() + 1)
	if _main.world:
		var wn = []
		for c in _main.world.get_children():
			wn.append(c)
		for c in wn:
			var pr2 = _mk_probe("world/after:" + str(c.name))
			_main.world.add_child(pr2)
			_main.world.move_child(pr2, c.get_index() + 1)

func _process(delta):
	_t += delta
	if _phase >= 1 and is_instance_valid(_main.player) and not OS.get_cmdline_user_args().has("--nogod"):
		_main.player.hp = _main.player.max_hp
		_main.player_lives_remaining = 99999
		for comp in _main.player.components.values():
			for tile in comp.hex_grid.get_all_tiles():
				if tile.is_disabled or tile.power_lost:
					tile.is_disabled = false
					tile.power_lost = false
					tile.hp = tile.max_hp
	match _phase:
		0:
			if _t > 3.0 and _presolve and _presolve_state == 0:
				_presolve_state = 1
				var d = _main._ensure_squad_director()
				_main.current_wave = _wave
				var t0 = Time.get_ticks_msec()
				var n = d.stock_build_evolution.missing_build_keys(-1).size()
				await d.stock_build_evolution.presolve_missing_builds(-1)
				print("BENCH_PRESOLVE builds=%d ms=%d" % [n, Time.get_ticks_msec() - t0])
				_presolve_state = 2
			elif _t > 3.0 and (not _presolve or _presolve_state == 2):
				for nm in _off:
					var nd = get_tree().root.find_child(nm, true, false)
					print("BENCH_OFF ", nm, " -> ", nd)
					if nd: nd.process_mode = Node.PROCESS_MODE_DISABLED
				_main.current_wave = _wave
				if _notrees:
					for n in get_tree().root.find_children("*", "StaticBody2D", true, false):
						if n.get_script() and n.get_script().resource_path.ends_with("TreeObstacle.gd"):
							n.queue_free()
				_main._close_garage()
				if OS.get_cmdline_user_args().has("--nooil"):
					var cnt = 0
					for n in get_tree().root.find_children("*", "Node2D", true, false):
						if n.get_script() and n.get_script().resource_path.ends_with("OilSlickHazard.gd"):
							n.queue_free()
							cnt += 1
					print("BENCH_NOOIL freed=", cnt)
				if OS.get_cmdline_user_args().has("--freemap"):
					_main.world.get_node("GameMap").queue_free()
				if OS.get_cmdline_user_args().has("--nomainproc"):
					_main.set_process(false)
					_main.set_physics_process(false)
				if _fire:
					var ev = InputEventMouseButton.new()
					ev.button_index = MOUSE_BUTTON_LEFT
					ev.pressed = true
					ev.position = get_viewport().get_visible_rect().size * 0.7
					Input.parse_input_event(ev)
				_phase = 1
				_t = 0.0
		1:
			if not _main_probed:
				_plant_main_probes()
			_record(delta)
			if OS.get_cmdline_user_args().has("--listnodes") and _t < 0.2 and not _hist_done:
				_hist_done = true
				for c in _main.get_children():
					print("BENCH_MAIN ", c.name, " ", c.get_class(), " children=", c.get_child_count())
				for c in _main.world.get_children():
					print("BENCH_WORLD ", c.name, " ", c.get_class(), " children=", c.get_child_count())
			if _swarm > 0 and _t > 3.0 and _swarm_spawned < _swarm:
				# Force a crowded field: one squad per frame on a ring around the player.
				var dsw = _main._ensure_squad_director()
				if dsw.templates.size() > 0:
					var ang = randf() * TAU
					var posw = _main.player.global_position + Vector2(cos(ang), sin(ang)) * _swarm_ring
					dsw.spawn_specific_squad(dsw.templates[randi() % dsw.templates.size()], posw)
					_swarm_spawned += 1
			if not _prep_logged and _main.last_prepare_stats.has("ms"):
				_prep_logged = true
				print("BENCH_PREPARE ", _main.last_prepare_stats, " (t=%.1f)" % _t)
			if _garage_at >= 0.0 and not _garage_done and _t >= _garage_at:
				# Redeploy mid-wave with enemies already on the board.
				_garage_done = true
				var live = get_tree().get_nodes_in_group("enemy").size()
				var t0 = Time.get_ticks_usec()
				_main._close_garage()
				print("BENCH_GARAGE_RETURN t=%.1f enemies_on_board=%d sync_ms=%.1f sections=%s" % [_t, live, (Time.get_ticks_usec() - t0) / 1000.0, _main.last_deploy_timings])
			if not _hist_done and _t > _seconds * 0.6:
				_hist_done = true
				_node_histogram()
			if _t >= _seconds:
				_report()
				get_tree().quit()

func _record(delta):
	var ms = delta * 1000.0
	_frames.append(ms)
	_sec_frames.append(ms)
	_sec_t += delta
	if ms > 80.0:
		var sp = load("res://scripts/debug/FrameSplitProbe.gd").last_split
		print("BENCH_GAPS t=%.2f ms=%.0f %s" % [_t, ms, load("res://scripts/debug/TreeProbe.gd").worst_gaps(2)])
		print("BENCH_SPLIT t=%.2f total=%.0f gap_pre=%.1f phys=%.1f (steps=%d) gap_post=%.1f proc=%.1f" % [_t, ms, sp.get("gap_pre", 0.0), sp.get("phys", 0.0), sp.get("steps", 0), sp.get("gap_post", 0.0), sp.get("proc", 0.0)])
		var vp = get_tree().root.get_viewport_rid()
		print("BENCH_SPIKE_RENDER t=%.2f frame_setup_cpu=%.1f vp_cpu=%.1f vp_gpu=%.1f" % [_t, RenderingServer.get_frame_setup_time_cpu(), RenderingServer.viewport_get_measured_render_time_cpu(vp), RenderingServer.viewport_get_measured_render_time_gpu(vp)])
		print("BENCH_SPIKE t=%.2f ms=%.0f proc=%.0f phys=%.0f nav=%.0f enemies=%d nodes=%d physsteps=%d" % [
			_t, ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0,
			_main.active_enemies, get_tree().get_node_count(), Engine.get_physics_frames()])
	_peak_enemies = max(_peak_enemies, _main.active_enemies)
	_peak_nodes = max(_peak_nodes, get_tree().get_node_count())
	if _sec_t >= 1.0:
		var w := 0.0
		for x in _sec_frames:
			w = max(w, x)
		print("BENCH_LIVE enemy_group=%d" % get_tree().get_nodes_in_group("enemy").size())
		print("BENCH_SEC t=%02d fps=%d worst_ms=%.0f enemies=%d nodes=%d draws=%d proc_ms=%.1f phys_ms=%.1f projectiles=%d" % [
			int(_t), _sec_frames.size(), w, _main.active_enemies, get_tree().get_node_count(),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			get_tree().get_nodes_in_group("projectile").size()])
		print("BENCH_PERF ms: spawn=%.0f shape=%.0f loadout=%.0f visual=%.0f stock_lookup=%.0f replay=%.0f fresh_inv=%.0f serialize=%.0f | ai=%.0f shoot=%.0f move=%.0f sight=%.0f flow=%.0f sep=%.0f status=%.0f music=%.0f recalc=%.0fms/%dcalls" % [
			SquadDirector._perf_bot_spawn_usec / 1000.0, Mech._perf_shape_gen_usec / 1000.0, Mech._perf_build_loadout_usec / 1000.0,
			Mech._perf_visual_build_usec / 1000.0, Mech._perf_stock_lookup_usec / 1000.0, Mech._perf_stock_replay_usec / 1000.0,
			Mech._perf_fresh_inventory_usec / 1000.0, Mech._perf_post_solve_serialize_usec / 1000.0,
			Mech._perf_ai_tactics_usec / 1000.0, Mech._perf_shoot_usec / 1000.0, Mech._perf_move_usec / 1000.0,
			Mech._perf_sight_usec / 1000.0, Mech._perf_flow_field_usec / 1000.0, Mech._perf_separation_usec / 1000.0,
			Mech._perf_status_effects_usec / 1000.0, ProceduralMusic._perf_fill_usec / 1000.0, Mech._perf_recalc_usec / 1000.0, Mech._perf_recalc_calls])
		_cum["shape"] += Mech._perf_shape_gen_usec
		_cum["loadout"] += Mech._perf_build_loadout_usec
		_cum["visual"] += Mech._perf_visual_build_usec
		_cum["replay"] += Mech._perf_stock_replay_usec
		_cum["spawn"] += SquadDirector._perf_bot_spawn_usec
		SquadDirector._perf_bot_spawn_usec = 0
		Mech._perf_shape_gen_usec = 0
		Mech._perf_build_loadout_usec = 0
		Mech._perf_visual_build_usec = 0
		Mech._perf_stock_lookup_usec = 0
		Mech._perf_stock_replay_usec = 0
		Mech._perf_fresh_inventory_usec = 0
		Mech._perf_post_solve_serialize_usec = 0
		Mech._perf_ai_tactics_usec = 0
		Mech._perf_shoot_usec = 0
		Mech._perf_move_usec = 0
		Mech._perf_sight_usec = 0
		Mech._perf_flow_field_usec = 0
		Mech._perf_separation_usec = 0
		Mech._perf_status_effects_usec = 0
		ProceduralMusic._perf_fill_usec = 0
		Mech._perf_recalc_usec = 0
		Mech._perf_recalc_calls = 0
		if Mech._perf_sim_rust_calls + Mech._perf_sim_gd_calls > 0:
			print("BENCH_SIM phases_ms reset=%.0f mass=%.0f simulate=%.0f collect=%.0f finalize=%.0f | rust=%d gd=%d" % [Mech._perf_phase_usec[0]/1000.0, Mech._perf_phase_usec[1]/1000.0, Mech._perf_phase_usec[2]/1000.0, Mech._perf_phase_usec[3]/1000.0, Mech._perf_phase_usec[4]/1000.0, Mech._perf_sim_rust_calls, Mech._perf_sim_gd_calls])
		print("BENCH_PROJ ms: proj_phys=%.0f homing_q=%.0f vortex_q=%.0f blink_q=%.0f broadphase=%.0f mgr_collect=%.0f mgr_rust=%.0f | shoot_fired=%.0f shoot_checked=%.0f shots=%d weapon_charges=%.0f apply_damage=%.0f" % [
			Projectile._perf_physics_usec / 1000.0, Projectile._perf_homing_query_usec / 1000.0, Projectile._perf_vortex_query_usec / 1000.0, Projectile._perf_blink_query_usec / 1000.0,
			ProjectileBroadphase._perf_physics_usec / 1000.0, ProjectileManager._perf_collect_usec / 1000.0, ProjectileManager._perf_rust_call_usec / 1000.0,
			Mech._perf_shoot_fired_usec / 1000.0, Mech._perf_shoot_checked_only_usec / 1000.0, Mech._perf_diag_shots_fired_count, Mech._perf_weapon_charges_usec / 1000.0, Mech._perf_apply_damage_usec / 1000.0])
		Projectile._perf_physics_usec = 0
		Projectile._perf_homing_query_usec = 0
		Projectile._perf_vortex_query_usec = 0
		Projectile._perf_blink_query_usec = 0
		ProjectileBroadphase._perf_physics_usec = 0
		ProjectileManager._perf_collect_usec = 0
		ProjectileManager._perf_rust_call_usec = 0
		Mech._perf_shoot_fired_usec = 0
		Mech._perf_shoot_checked_only_usec = 0
		Mech._perf_diag_shots_fired_count = 0
		Mech._perf_weapon_charges_usec = 0
		Mech._perf_apply_damage_usec = 0
		if RustGridSim._perf_tiles > 0:
			print("BENCH_BRIDGE describe=%.0f rustcall=%.0f writeback=%.0f | inside_rust parse=%.1f sim=%.1f out=%.1f ms steps=%d captures=%d calls=%d tiles=%d" % [RustGridSim._perf_us[0]/1000.0, RustGridSim._perf_us[1]/1000.0, RustGridSim._perf_us[2]/1000.0, RustGridSim._perf_us[3]/1000.0, RustGridSim._perf_us[4]/1000.0, RustGridSim._perf_us[5]/1000.0, RustGridSim._perf_us[6], RustGridSim._perf_us[7], RustGridSim._perf_us[8], RustGridSim._perf_tiles])
		RustGridSim._perf_us = [0, 0, 0, 0, 0, 0, 0, 0, 0]
		RustGridSim._perf_tiles = 0
		Mech._perf_phase_usec = [0, 0, 0, 0, 0]
		Mech._perf_sim_rust_calls = 0
		Mech._perf_sim_gd_calls = 0
		_sec_frames.clear()
		_sec_t = 0.0

func _node_histogram():
	var counts := {}
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var scr = n.get_script()
		var key = n.get_class() + ("|" + scr.resource_path.get_file() if scr else "")
		counts[key] = counts.get(key, 0) + 1
		for c in n.get_children():
			stack.append(c)
	var procs := {}
	stack = [get_tree().root]
	while not stack.is_empty():
		var n2: Node = stack.pop_back()
		var scr2 = n2.get_script()
		if scr2 and (n2.is_processing() or n2.is_physics_processing()):
			var k2 = scr2.resource_path.get_file() + (" P" if n2.is_processing() else " ") + ("PP" if n2.is_physics_processing() else "")
			procs[k2] = procs.get(k2, 0) + 1
		for c2 in n2.get_children():
			stack.append(c2)
	for k in procs:
		print("BENCH_PROCS %4d  %s" % [procs[k], k])
	var keys = counts.keys()
	keys.sort_custom(func(a, b): return counts[a] > counts[b])
	for i in min(14, keys.size()):
		print("BENCH_NODES %5d  %s" % [counts[keys[i]], keys[i]])

func _report():
	var dpool = _main._ensure_squad_director()
	print("BENCH_POOL hits=%d misses=%d stock=%d rebuild_wave=%d energy_scale=%.2f" % [dpool.pool_hits, dpool.pool_misses, dpool.pool_stock(), dpool.rebuild_wave, dpool.energy_scale_for_wave()])
	var nb = max(1, Mech._perf_bots_built)
	print("BENCH_PER_BOT bots=%d avg_ms: spawn=%.1f shape=%.1f loadout=%.1f (replay=%.1f) visual=%.1f" % [Mech._perf_bots_built, _cum["spawn"] / 1000.0 / nb, _cum["shape"] / 1000.0 / nb, _cum["loadout"] / 1000.0 / nb, _cum["replay"] / 1000.0 / nb, _cum["visual"] / 1000.0 / nb])
	var s = _frames.duplicate()
	s.sort()
	var sum := 0.0
	var over100 := 0
	for x in s:
		sum += x
		if x > 100.0: over100 += 1
	var n = s.size()
	print("BENCH renderer=%s wave=%d frames=%d avg_fps=%.1f p50=%.1f p95=%.1f p99=%.1f worst=%.0f frames_over_100ms=%d peak_enemies=%d peak_nodes=%d" % [
		RenderingServer.get_current_rendering_method(), _wave, n, 1000.0 * n / sum,
		s[n / 2], s[int(n * 0.95)], s[int(n * 0.99)], s[n - 1], over100, _peak_enemies, _peak_nodes])
