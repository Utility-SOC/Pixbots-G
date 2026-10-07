extends Node

# DebugRoom: a general, scriptable scenario runner for the REAL game (main.tscn), replacing the
# one-flag-per-experiment growth of BenchGame. Boots Main directly (no menu/cinematic), deploys from the
# Garage, skips the wave countdown, forces full visuals (a killed run otherwise leaves the FxTier marker
# and the next run silently drops to "safe FX"), drives the player's guns itself, spawns a crowd on a
# schedule, and reports STEADY-STATE numbers (after a warm-up) as one JSON summary.
#
#   godot --path . res://scripts/debug/DebugRoom.tscn -- --help
#   godot --path . --audio-driver Dummy res://scripts/debug/DebugRoom.tscn -- \
#       --wave=34 --spawn=40 --ring=500 --fire=auto --seconds=30 --report=/tmp/run.json
#
# Args are --key=value (or a bare --flag = 1). See ARGS below, or run with --help.
# Timeline:  --events="5:spawn=20;10:masskill;12:fire=off;20:quit"   (seconds since deploy)
# Interactive (--interactive): overlay + F1 spawn 5 squads, F2 mass kill, F3 fire on/off, F4 god on/off,
# F5 missile volley, F12 quit.

const ARGS := {
	# --- scenario ---
	"wave": [34, "starting wave (scales enemy tier and caps)"],
	"seed": [1, "RNG seed for spawn angles / template picks"],
	"map": ["", "force a map type (Volcano, Tundra, Open Field, ...)"],
	"layout": ["auto", "map layout (auto, river, ridges, pillars, rings, canyon, crossroads)"],
	"seconds": [30.0, "run length after deploy (0 = run until quit; --interactive implies 0)"],
	"warmup": [5.0, "seconds excluded from the steady-state stats"],
	"interactive": [0, "overlay + hotkeys, never auto-quits"],
	# --- crowd ---
	"spawn": [0, "squads to spawn after deploy"],
	"spawn_at": [2.0, "seconds after deploy before spawning starts"],
	"spawn_rate": [30.0, "squads per second while spawning"],
	"ring": [600.0, "spawn ring radius around the player (px). Engagement range is roughly 300-700"],
	# --- player ---
	"fire": ["auto", "auto = player's guns fire at the nearest enemy; off = hold fire"],
	"god": [1, "player cannot die"],
	# --- load generators ---
	"missiles": [0.0, "missile volleys per second at random enemies"],
	"masskill": [0.0, "kill every enemy in one frame every N seconds (death-burst hitch test)"],
	"garage_at": [-1.0, "re-deploy from the Garage mid-run at this time"],
	"events": ["", "timeline 't:cmd;t:cmd' - cmds: spawn=N ring=R masskill missiles=R fire=on|off god=on|off print=msg quit"],
	# --- environment ---
	"music": [0, "enable procedural music (off by default: a real CPU hog on this machine)"],
	"fx": ["full", "full | safe | auto (auto honours the unclean-exit marker)"],
	"rate": [0, "cap fps (0 = uncapped, vsync off)"],
	# --- A/B tweaks (applied to the live world) ---
	"off": ["", "comma list of node names whose processing is disabled"],
	"noglow": [0, "disable the PixelViewport glow"],
	"notrees": [0, "free TreeObstacles"],
	"noslide": [0, "enemies skip move_and_slide"],
	"hidevis": [0, "hide enemy visuals"],
	"nocollide": [0, "enemy collision layer/mask 0"],
	"stream": [0, "enable ObstacleCollisionStreamer"],
	"freeze": [0, "disable ALL processing on enemies (cost of the nodes themselves vs their scripts)"],
	"nobars": [0, "stop MechStatusBars _process on every mech"],
	"nomechphys": [0, "stop Mech _physics_process on enemies (no AI/move/shoot) but keep everything else processing"],
	"noshoot": [0, "enemies skip _shoot (Mech._diag_skip_shoot)"],
	"nosep": [0, "enemies skip the separation query (Mech._diag_skip_separation)"],
	"nofar": [0, "enemies skip the far-branch body (Mech._diag_skip_far_branch_body)"],
	"perf": [0, "add Mech per-section script timers (ms/s: ai, shoot, move, sight, flow, sep, status, charges, abilities, ...) to each ROOM_SEC row"],
	"procs": [0, "print a census of nodes with _process/_physics_process enabled, by script, at warmup"],
	# --- output ---
	"report": ["", "write the JSON summary to this path"],
	"series": [1, "print one ROOM_SEC line per second"],
}

var _a: Dictionary = {}
var _main: Node
var _t := 0.0 # seconds since deploy
var _phase := 0 # 0 boot, 1 deploying, 2 running
var _boot_t := 0.0
var _frames: Array[float] = []
var _sec_frames := 0
var _sec_worst := 0.0
var _sec_t := 0.0
var _series: Array = []
var _split_sum := {"gap_pre": 0.0, "phys": 0.0, "gap_post": 0.0, "proc": 0.0}
var _split_n := 0
var _peak := {"enemies": 0, "projectiles": 0, "nodes": 0}
var _enemy_sum := 0.0
var _spawn_left := 0
var _spawn_acc := 0.0
var _missile_acc := 0.0
var _next_masskill := 0.0
var _fire := true
var _god := true
var _garage_done := false
var _timeline: Array = [] # [t, cmd, arg]
var _tweaks_done := false
var _label: Label
var _arm_toggle := false
var _quit_requested := false
var _wake_probe := 0.0

func _ready() -> void:
	_parse_args()
	if _a.get("help", 0):
		_print_help()
		get_tree().quit()
		return
	seed(int(_a["seed"]))
	_fire = str(_a["fire"]) != "off"
	_god = int(_a["god"]) != 0
	_spawn_left = int(_a["spawn"])
	_next_masskill = float(_a["masskill"])
	_parse_timeline(str(_a["events"]))
	if int(_a["interactive"]) != 0:
		_a["seconds"] = 0.0
		_build_overlay()
	match str(_a["fx"]):
		"full": OS.set_environment("PIXBOTS_FULL_FX", "1")
		"safe": OS.set_environment("PIXBOTS_SAFE_FX", "1")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(_a["rate"])
	if int(_a["perf"]) != 0:
		FpsCounter.set_process(false) # it resets the same Mech._perf_* counters on its own timer
	if int(_a["music"]) == 0:
		ProceduralMusic.set_process(false)
		ProceduralMusic.stop()
		AudioManager._quitting = true
	if str(_a["map"]) != "":
		SaveManager.pending_run_card = {"map_type": str(_a["map"]), "layout": str(_a["layout"]), "seed": 0}
	var pa = load("res://scripts/debug/FrameSplitProbe.gd").new()
	var pb = load("res://scripts/debug/FrameSplitProbe.gd").new()
	pb.is_last = true
	get_tree().root.add_child.call_deferred(pa)
	get_tree().root.add_child.call_deferred(pb)
	_main = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(_main)
	(func(): get_tree().current_scene = _main).call_deferred()
	print("ROOM start args=", JSON.stringify(_a))

# ---------------------------------------------------------------- args

func _parse_args() -> void:
	for k in ARGS:
		_a[k] = ARGS[k][0]
	_a["help"] = 0
	for raw in OS.get_cmdline_user_args():
		if not raw.begins_with("--"):
			continue
		var kv: PackedStringArray = raw.substr(2).split("=", true, 1)
		var key := kv[0]
		var val: String = kv[1] if kv.size() > 1 else "1"
		if key == "help":
			_a["help"] = 1
		elif ARGS.has(key):
			var d = ARGS[key][0]
			if d is int: _a[key] = int(val)
			elif d is float: _a[key] = float(val)
			else: _a[key] = val
		else:
			print("ROOM warning: unknown argument --%s (try --help)" % key)

func _print_help() -> void:
	print("DebugRoom arguments (--key=value, bare --flag = 1):")
	for k in ARGS:
		print("  --%-12s default=%-10s %s" % [k, str(ARGS[k][0]), ARGS[k][1]])

func _parse_timeline(s: String) -> void:
	for item in s.split(";", false):
		var p := item.strip_edges().split(":", true, 1)
		if p.size() < 2:
			continue
		var cmd := p[1].strip_edges()
		var kv := cmd.split("=", true, 1)
		_timeline.append([float(p[0]), kv[0], kv[1] if kv.size() > 1 else ""])
	_timeline.sort_custom(func(x, y): return x[0] < y[0])

func _run_cmd(cmd: String, arg: String) -> void:
	match cmd:
		"spawn": _spawn_left += int(arg)
		"ring": _a["ring"] = float(arg)
		"masskill": _masskill()
		"missiles": _a["missiles"] = float(arg)
		"fire": _fire = arg != "off"
		"god": _god = arg != "off"
		"print": print("ROOM note t=%.1f %s" % [_t, arg])
		"quit": _finish()
		_: print("ROOM warning: unknown timeline command '%s'" % cmd)

# ---------------------------------------------------------------- main loop

var _wall_last_us := 0
func _process(game_delta: float) -> void:
	# Engine clamps the delta it hands to _process to max_physics_steps_per_frame ticks (50 ms), so on slow
	# frames it under-reports and 'fps' saturates near 20. Everything here runs on wall-clock time instead.
	var now_us := Time.get_ticks_usec()
	var delta := (now_us - _wall_last_us) / 1e6 if _wall_last_us > 0 else game_delta
	_wall_last_us = now_us
	if _main == null or not is_instance_valid(_main) or _quit_requested:
		return
	match _phase:
		0:
			_boot_t += delta
			# Main builds the player/map/HUD in _ready (deferred add); wait for it plus a beat.
			if _boot_t > 2.0 and "player" in _main and is_instance_valid(_main.player):
				_phase = 1
				_main.current_wave = int(_a["wave"])
				_apply_world_tweaks()
				_main._close_garage()
				print("ROOM deploy boot_s=%.1f" % _boot_t)
		1:
			_skip_countdown()
			if _main.current_wave >= 1 and _main.get("active_enemies") != null and _wave_started():
				_phase = 2
				_t = 0.0
				print("ROOM running (wave %d)" % _main.current_wave)
		2:
			_t += delta
			_tick_running(delta)

func _wave_started() -> bool:
	# Wave 'starting in 5 seconds' timer has fired once the Main timer child is gone / enemies exist,
	# or after the safety timeout.
	return _boot_t > 0.0 and (_countdown_fired or _boot_t > 40.0)

var _countdown_fired := false
func _skip_countdown() -> void:
	_boot_t += 0.0
	for c in _main.get_children():
		if c is Timer and c.one_shot and is_equal_approx(c.wait_time, 5.0) and not c.is_stopped():
			c.stop()
			c.timeout.emit() # runs Main._start_wave now instead of 5 s from now
			_countdown_fired = true
			return

func _tick_running(delta: float) -> void:
	if _god and is_instance_valid(_main.player):
		_main.player.hp = _main.player.max_hp
		_main.player_lives_remaining = 99999
		for comp in _main.player.components.values():
			for tile in comp.hex_grid.get_all_tiles():
				if tile.is_disabled or tile.power_lost:
					tile.is_disabled = false
					tile.power_lost = false
					tile.hp = tile.max_hp
	while not _timeline.is_empty() and _timeline[0][0] <= _t:
		var ev = _timeline.pop_front()
		_run_cmd(ev[1], ev[2])
	_apply_world_tweaks()
	if int(_a["procs"]) != 0 and not _procs_done and _t >= float(_a["warmup"]):
		_procs_done = true
		_print_proc_census()
	_drive_spawn(delta)
	_drive_player_fire(delta)
	if float(_a["missiles"]) > 0.0:
		_missile_acc += delta * float(_a["missiles"])
		while _missile_acc >= 1.0:
			_missile_acc -= 1.0
			_fire_missile()
	if _next_masskill > 0.0 and _t >= _next_masskill:
		_next_masskill = _t + float(_a["masskill"])
		_masskill()
	var ga := float(_a["garage_at"])
	if ga >= 0.0 and not _garage_done and _t >= ga:
		_garage_done = true
		var t0 := Time.get_ticks_usec()
		_main._close_garage()
		print("ROOM garage_return t=%.1f sync_ms=%.1f" % [_t, (Time.get_ticks_usec() - t0) / 1000.0])
	_record(delta)
	var secs := float(_a["seconds"])
	if secs > 0.0 and _t >= secs:
		_finish()

var _procs_done := false
func _print_proc_census() -> void:
	var cnt := {}
	var total := 0
	for n in get_tree().root.find_children("*", "", true, false):
		var p: bool = n.is_processing()
		var pp: bool = n.is_physics_processing()
		if not (p or pp):
			continue
		var k := "%s %s%s" % [n.get_script().resource_path.get_file() if n.get_script() else n.get_class(), "P" if p else "-", "p" if pp else "-"]
		cnt[k] = cnt.get(k, 0) + 1
		total += 1
	var keys := cnt.keys()
	keys.sort_custom(func(a, b): return cnt[a] > cnt[b])
	print("ROOM_PROCS total=%d of %d nodes" % [total, get_tree().get_node_count()])
	for k in keys.slice(0, 25):
		print("ROOM_PROCS %5d  %s" % [cnt[k], k])

func _drive_spawn(delta: float) -> void:
	if _spawn_left <= 0 or _t < float(_a["spawn_at"]):
		return
	_spawn_acc += delta * float(_a["spawn_rate"])
	var d = _main._ensure_squad_director()
	while _spawn_acc >= 1.0 and _spawn_left > 0 and d.templates.size() > 0:
		_spawn_acc -= 1.0
		_spawn_left -= 1
		var ang := randf() * TAU
		var pos: Vector2 = _main.player.global_position + Vector2(cos(ang), sin(ang)) * float(_a["ring"])
		d.spawn_specific_squad(d.templates[randi() % d.templates.size()], pos)

func _drive_player_fire(_delta: float) -> void:
	if not _fire or not is_instance_valid(_main.player):
		return
	var best: Node2D = null
	var best_d := INF
	for e in EntityCache.get_group(&"enemy"):
		if is_instance_valid(e) and e is Node2D and not e.get("is_dead"):
			var dd: float = e.global_position.distance_squared_to(_main.player.global_position)
			if dd < best_d:
				best_d = dd
				best = e
	if best == null:
		return
	_arm_toggle = not _arm_toggle
	_main.player._shoot(best.global_position, true, _arm_toggle, _delta)

func _fire_missile() -> void:
	var enemies = get_tree().get_nodes_in_group("enemy")
	if enemies.is_empty():
		return
	var e = enemies[randi() % enemies.size()]
	if not is_instance_valid(e):
		return
	var syn = {6: 600.0}
	var shell = load("res://scripts/attacks/MortarShell.gd").acquire()
	shell.setup(_main.player.global_position, e.global_position, 0.7, 600.0, syn, true, _main.player)
	_main.world.add_child(shell)

func _masskill() -> void:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and not e.get("is_dead") and e.has_method("die"):
			e.die()
			n += 1
	print("ROOM masskill t=%.1f killed=%d" % [_t, n])

# ---------------------------------------------------------------- tweaks

func _apply_world_tweaks() -> void:
	if not _tweaks_done:
		_tweaks_done = true
		for nm in str(_a["off"]).split(",", false):
			var nd = get_tree().root.find_child(nm, true, false)
			print("ROOM off ", nm, " -> ", nd)
			if nd: nd.process_mode = Node.PROCESS_MODE_DISABLED
		if int(_a["noglow"]) != 0:
			var we = get_tree().root.find_child("PixelViewportEnvironment", true, false)
			if we and we.environment: we.environment.glow_enabled = false
		if int(_a["notrees"]) != 0:
			for n in get_tree().root.find_children("*", "StaticBody2D", true, false):
				if n.get_script() and n.get_script().resource_path.ends_with("TreeObstacle.gd"):
					n.queue_free()
		var map = _main.world.get_node_or_null("GameMap") if _main.world else null
		if map and map.obstacle_streamer:
			map.obstacle_streamer.enabled = int(_a["stream"]) != 0
	# Per-enemy tweaks apply to new spawns too, so re-run every few frames.
	if Engine.get_physics_frames() % 10 != 0:
		return
	if int(_a["nobars"]) != 0:
		for b in get_tree().root.find_children("*", "Node2D", true, false):
			if b.get_script() and b.get_script().resource_path.ends_with("MechStatusBars.gd") and b.is_processing():
				b.set_process(false)
	if int(_a["noslide"]) + int(_a["hidevis"]) + int(_a["nocollide"]) + int(_a["freeze"]) \
			+ int(_a["nomechphys"]) + int(_a["noshoot"]) + int(_a["nosep"]) + int(_a["nofar"]) == 0:
		return
	for e in get_tree().get_nodes_in_group("enemy"):
		if int(_a["nomechphys"]) != 0 and e.is_physics_processing():
			e.set_physics_process(false)
		if int(_a["noshoot"]) != 0: e._diag_skip_shoot = true
		if int(_a["nosep"]) != 0: e._diag_skip_separation = true
		if int(_a["nofar"]) != 0: e._diag_skip_far_branch_body = true
		if int(_a["freeze"]) != 0 and e.process_mode != Node.PROCESS_MODE_DISABLED:
			e.process_mode = Node.PROCESS_MODE_DISABLED
		if int(_a["noslide"]) != 0: e._diag_skip_move_and_slide = true
		if int(_a["hidevis"]) != 0 and e is CanvasItem: e.visible = false
		if int(_a["nocollide"]) != 0 and e is CollisionObject2D:
			e.collision_layer = 0
			e.collision_mask = 0

# ---------------------------------------------------------------- measurement

func _record(delta: float) -> void:
	var ms := delta * 1000.0
	var steady := _t >= float(_a["warmup"])
	if steady:
		_frames.append(ms)
		var sp: Dictionary = load("res://scripts/debug/FrameSplitProbe.gd").last_split
		if not sp.is_empty():
			for k in _split_sum:
				_split_sum[k] += float(sp.get(k, 0.0))
			_split_n += 1
	_sec_frames += 1
	_sec_worst = max(_sec_worst, ms)
	_sec_t += delta
	var enemies := EntityCache.get_group(&"enemy").size()
	_peak["enemies"] = max(_peak["enemies"], enemies)
	if steady: _enemy_sum += enemies
	_peak["nodes"] = max(_peak["nodes"], get_tree().get_node_count())
	if _sec_t >= 1.0:
		var proj := _projectile_count()
		_peak["projectiles"] = max(_peak["projectiles"], proj)
		var row := {
			"t": int(_t), "fps": _sec_frames, "worst_ms": snappedf(_sec_worst, 0.1), "enemies": enemies,
			"projectiles": proj, "nodes": get_tree().get_node_count(),
			"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			"phys_active": int(Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)),
			"phys_pairs": int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)),
			"proc_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.1),
			"phys_ms": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.1),
		}
		if int(_a["perf"]) != 0:
			row["perf_ms"] = _take_perf()
		_series.append(row)
		if int(_a["series"]) != 0:
			print("ROOM_SEC ", JSON.stringify(row))
		_sec_frames = 0
		_sec_worst = 0.0
		_sec_t = 0.0
	if _label:
		_label.text = "t=%.0f  fps=%d  enemies=%d  proj=%d  nodes=%d\nF1 spawn5  F2 masskill  F3 fire=%s  F4 god=%s  F5 missiles  F12 quit" % [
			_t, Engine.get_frames_per_second(), enemies, _projectile_count(), get_tree().get_node_count(), _fire, _god]

# Mech's per-section script timers (usec accumulated over the last second); read and reset here.
func _take_perf() -> Dictionary:
	var out := {
		"ai": Mech._perf_ai_tactics_usec, "shoot": Mech._perf_shoot_usec, "move": Mech._perf_move_usec,
		"sight": Mech._perf_sight_usec, "flow": Mech._perf_flow_field_usec, "sep": Mech._perf_separation_usec,
		"status": Mech._perf_status_effects_usec, "charges": Mech._perf_weapon_charges_usec,
		"abilities": Mech._perf_ability_systems_usec, "orbit_ray": Mech._perf_orbit_raycast_usec,
		"flee": Mech._perf_flee_check_usec, "search": Mech._perf_execute_search_usec,
		"shoot_fired": Mech._perf_shoot_fired_usec, "shoot_checked": Mech._perf_shoot_checked_only_usec,
	}
	for k in out:
		out[k] = snappedf(out[k] / 1000.0, 0.1)
	Mech._perf_ai_tactics_usec = 0
	Mech._perf_shoot_usec = 0
	Mech._perf_move_usec = 0
	Mech._perf_sight_usec = 0
	Mech._perf_flow_field_usec = 0
	Mech._perf_separation_usec = 0
	Mech._perf_status_effects_usec = 0
	Mech._perf_weapon_charges_usec = 0
	Mech._perf_ability_systems_usec = 0
	Mech._perf_orbit_raycast_usec = 0
	Mech._perf_flee_check_usec = 0
	Mech._perf_execute_search_usec = 0
	Mech._perf_shoot_fired_usec = 0
	Mech._perf_shoot_checked_only_usec = 0
	return out

func _projectile_count() -> int:
	var n := get_tree().get_nodes_in_group("projectile").size()
	if is_instance_valid(ProjectileManager.live_batch_pool):
		n += ProjectileManager.live_batch_pool.live_count()
	return n

func _summary() -> Dictionary:
	var s := _frames.duplicate()
	s.sort()
	var n := s.size()
	var sum := 0.0
	var o50 := 0
	var o100 := 0
	for x in s:
		sum += x
		if x > 50.0: o50 += 1
		if x > 100.0: o100 += 1
	var out := {
		"wave": int(_a["wave"]), "renderer": RenderingServer.get_current_rendering_method(),
		"steady_frames": n, "warmup_s": float(_a["warmup"]), "args": _a,
		"peak_enemies": _peak["enemies"], "peak_projectiles": _peak["projectiles"], "peak_nodes": _peak["nodes"],
	}
	if n > 0:
		out["avg_fps"] = snappedf(1000.0 * n / max(sum, 0.001), 0.1)
		out["p50_ms"] = snappedf(s[n / 2], 0.1)
		out["p95_ms"] = snappedf(s[int(n * 0.95)], 0.1)
		out["p99_ms"] = snappedf(s[int(n * 0.99)], 0.1)
		out["worst_ms"] = snappedf(s[n - 1], 0.1)
		out["frames_over_50ms"] = o50
		out["frames_over_100ms"] = o100
		out["mean_enemies"] = snappedf(_enemy_sum / n, 0.1)
	if _split_n > 0:
		var sp := {}
		for k in _split_sum:
			sp[k] = snappedf(_split_sum[k] / _split_n, 0.1)
		out["avg_frame_split_ms"] = sp
	return out

func _finish() -> void:
	if _quit_requested:
		return
	_quit_requested = true
	var sm := _summary()
	print("ROOM_SUMMARY ", JSON.stringify(sm))
	var path := str(_a["report"])
	if path != "":
		sm["series"] = _series
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(sm, "  "))
			f.close()
			print("ROOM report written: ", path)
	preload("res://scripts/core/FxTier.gd").end_session()
	get_tree().quit()

# ---------------------------------------------------------------- interactive

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 200
	_label = Label.new()
	_label.position = Vector2(10, 6)
	_label.add_theme_color_override("font_color", Color(1, 1, 0.6))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	layer.add_child(_label)
	add_child(layer)

func _input(event: InputEvent) -> void:
	if int(_a["interactive"]) == 0 or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F1: _spawn_left += 5
		KEY_F2: _masskill()
		KEY_F3: _fire = not _fire
		KEY_F4: _god = not _god
		KEY_F5:
			for i in 5: _fire_missile()
		KEY_F12: _finish()
