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
	"keep": [0, "keep at least this many enemies alive (spawns squads at ~4/s when below); 0 = off"],
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
	"stage": [99, "enemies return from Mech._physics_process after section N: 0 top, 1 preamble, 2 status, 3 charges, 5 abilities, 6 AI, 7 move (truncation bisect)"],
	"hitgrid": [1, "ProjectileBatchPool hit-test spatial grid (1) vs the old brute-force scan (0) for A/B"],
	"adaptive": [0, "AdaptiveTick (lower the physics rate under load); default off, 1 = on for A/B"],
	"micro": [0, "after warm-up, pause the sim and time each per-tick Mech function directly on the live enemies (us/call), write it to the report and quit"],
	"crowdlod": [0, "Mech crowd LOD (stagger per-tick systems when many enemies); default off (no measured gain)"],
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
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	Mech.crowd_lod_enabled = int(_a["crowdlod"]) != 0
	preload("res://scripts/core/AdaptiveTick.gd").enabled = int(_a["adaptive"]) != 0
	ProjectileBatchPool.use_hit_grid = int(_a["hitgrid"]) != 0
	Mech.diag_stage_limit = int(_a["stage"])
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
var _frames0 := 0
var _sim_at_sec := 0.0
var _phys_at_sec := 0
var _speed_sum := 0.0
var _tpf_sum := 0.0
var _speed_n := 0
var _sim_t := 0.0 # simulated seconds since running (sum of physics step deltas)
var _phys0 := 0
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
				_frames0 = Engine.get_frames_drawn()
				_phys0 = Engine.get_physics_frames()
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

func _physics_process(_d: float) -> void:
	if _phase == 2:
		_sim_t += get_physics_process_delta_time()

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
	# A wave that gets cleared ends in the Garage (paused, ~100 fps): never let that contaminate a run.
	if is_instance_valid(_main.garage_ui) and ("garage_at" not in _a or float(_a["garage_at"]) < 0.0 or _garage_done):
		_garage_autoclosed += 1
		print("ROOM garage opened by the game at t=%.1f - closing it (enemies=%d)" % [_t, EntityCache.get_group(&"enemy").size()])
		_main._close_garage()
	_keep_crowd(delta)
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
	if int(_a["micro"]) != 0 and _t >= float(_a["warmup"]) + 1.0:
		_run_micro()
		return
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

var _garage_autoclosed := 0
var _keep_acc := 0.0
func _keep_crowd(delta: float) -> void:
	var want := int(_a["keep"])
	if want <= 0:
		return
	if EntityCache.get_group(&"enemy").size() >= want:
		return
	_keep_acc += delta * 4.0
	var d = _main._ensure_squad_director()
	while _keep_acc >= 1.0 and d.templates.size() > 0:
		_keep_acc -= 1.0
		var ang := randf() * TAU
		var pos: Vector2 = _main.player.global_position + Vector2(cos(ang), sin(ang)) * float(_a["ring"])
		d.spawn_specific_squad(d.templates[randi() % d.templates.size()], pos)

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
		var sim_dt := _sim_t - _sim_at_sec
		var phys_dt := Engine.get_physics_frames() - _phys_at_sec
		var sim_speed := sim_dt / _sec_t
		var tpf: float = float(phys_dt) / float(maxi(_sec_frames, 1))
		_sim_at_sec = _sim_t
		_phys_at_sec = Engine.get_physics_frames()
		if steady:
			_speed_sum += sim_speed
			_tpf_sum += tpf
			_speed_n += 1
		var cal_ms := _cpu_canary_ms()
		if steady:
			_cal_sum += cal_ms
			_cal_n += 1
		var proj := _projectile_count()
		_peak["projectiles"] = max(_peak["projectiles"], proj)
		var row := {
			"t": int(_t), "cal_ms": snappedf(cal_ms, 0.01), "fps": _sec_frames,
			"sim_speed": snappedf(sim_speed, 0.01), "ticks_per_frame": snappedf(tpf, 0.1), "hz": Engine.physics_ticks_per_second, "worst_ms": snappedf(_sec_worst, 0.1), "enemies": enemies,
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
		"proj_phys": Projectile._perf_physics_usec, "homing_q": Projectile._perf_homing_query_usec,
		"vortex_q": Projectile._perf_vortex_query_usec, "blink_q": Projectile._perf_blink_query_usec,
		"broadphase": ProjectileBroadphase._perf_physics_usec, "mgr_collect": ProjectileManager._perf_collect_usec,
		"mgr_rust": ProjectileManager._perf_rust_call_usec, "apply_damage": Mech._perf_apply_damage_usec,
	}
	out["pool_sim"] = ProjectileBatchPool._perf_sim_usec
	out["pool_hit"] = ProjectileBatchPool._perf_hit_usec
	out["pool_draw"] = ProjectileBatchPool._perf_draw_usec
	out["pool_spawn"] = ProjectileBatchPool._perf_spawn_usec
	for k in out:
		out[k] = snappedf(out[k] / 1000.0, 0.1)
	out["pool_spawns"] = ProjectileBatchPool._perf_spawn_count
	out["pool_hits"] = ProjectileBatchPool._perf_hit_count
	out["shots_fired"] = Mech._perf_diag_shots_fired_count
	ProjectileBatchPool._perf_sim_usec = 0
	ProjectileBatchPool._perf_hit_usec = 0
	ProjectileBatchPool._perf_draw_usec = 0
	ProjectileBatchPool._perf_spawn_usec = 0
	ProjectileBatchPool._perf_spawn_count = 0
	ProjectileBatchPool._perf_hit_count = 0
	Projectile._perf_physics_usec = 0
	Projectile._perf_homing_query_usec = 0
	Projectile._perf_vortex_query_usec = 0
	Projectile._perf_blink_query_usec = 0
	ProjectileBroadphase._perf_physics_usec = 0
	ProjectileManager._perf_collect_usec = 0
	ProjectileManager._perf_rust_call_usec = 0
	Mech._perf_apply_damage_usec = 0
	Mech._perf_diag_shots_fired_count = 0
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

# --- micro: direct per-call timing of the per-tick Mech functions on the live, realistic enemies.
const MICRO_CALLS := [
	["_tick_weapon_charges", [0.016]], ["update_status_effects", [0.016]], ["_update_jammer_module", [0.016]],
	["_update_healer", [0.016]], ["_update_shield_pulse", [0.016]], ["_execute_ai_tactics", [0.016]],
	["_update_flee_state", [0.016]], ["_refresh_water_state", []], ["_update_obstacle_phasing", []],
	["sync_hitbox_layers", []], ["_check_drowning", []], ["_process_ramming", [0.016]],
	["_process_reactive_plating_cooldowns", [0.016]], ["_apply_terrain_to_ai_velocity", [0.016]],
	["_avoid_water_in_velocity", [Vector2(100, 0), 0.016]], ["move_and_slide", []], ["_ai_aim_point", [Vector2(300, 0), 300.0]],
]
func _run_micro() -> void:
	get_tree().paused = true # freeze the sim; this node keeps running (PROCESS_MODE_ALWAYS below)
	var enemies: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e.has_method("_tick_weapon_charges") and not e.get("is_dead"):
			enemies.append(e)
	var res := {"enemies": enemies.size()}
	var wsum := 0
	var bank := 0
	var offline := 0
	for e in enemies:
		wsum += e.precalculated_weapons.size()
		for w in e.precalculated_weapons:
			if w.get("bank_mode", "") == "bank": bank += 1
			if e._weapon_offline(w): offline += 1
	res["avg_weapons_per_enemy"] = snappedf(float(wsum) / max(enemies.size(), 1), 0.01)
	res["avg_bank_weapons"] = snappedf(float(bank) / max(enemies.size(), 1), 0.01)
	res["avg_offline_weapons"] = snappedf(float(offline) / max(enemies.size(), 1), 0.01)
	# Overhead of the dynamic call itself, subtracted from every figure.
	var oh := _time_calls(enemies, "is_queued_for_deletion", [])
	res["callv_overhead_us"] = snappedf(oh, 0.001)
	var total := 0.0
	for c in MICRO_CALLS:
		var best := INF
		for rep in range(4):
			best = minf(best, _time_calls(enemies, c[0], c[1]))
		var us := maxf(best - oh, 0.0)
		res[c[0]] = snappedf(us, 0.01)
		if c[0] != "move_and_slide" and c[0] != "_ai_aim_point":
			total += us
	# Same-process interleaved A/B for the weapon-charge early-out: fast (default) vs the original loop.
	var best_fast := INF
	var best_slow := INF
	for rep in range(6):
		Mech.diag_slow_charges = false
		best_fast = minf(best_fast, _time_calls(enemies, "_tick_weapon_charges", [0.016]))
		Mech.diag_slow_charges = true
		best_slow = minf(best_slow, _time_calls(enemies, "_tick_weapon_charges", [0.016]))
	Mech.diag_slow_charges = false
	res["charges_fast_us"] = snappedf(maxf(best_fast - oh, 0.0), 0.01)
	res["charges_slow_us"] = snappedf(maxf(best_slow - oh, 0.0), 0.01)
	# cloak system tick is an object call, not a Mech method
	var cs: Array = []
	for e in enemies:
		if e.cloak_system: cs.append(e.cloak_system)
	if not cs.is_empty():
		var best := INF
		for rep in range(4):
			best = minf(best, _time_calls(cs, "tick", [0.016]))
		res["cloak_system.tick"] = snappedf(maxf(best - oh, 0.0), 0.01)
		total += res["cloak_system.tick"]
	res["sum_us_per_mech_tick"] = snappedf(total, 0.01)
	res["est_ms_per_tick_all_enemies"] = snappedf(total * enemies.size() / 1000.0, 0.1)
	print("ROOM_MICRO ", JSON.stringify(res))
	var path := str(_a["report"])
	if path != "":
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(res, "  "))
			f.close()
	get_tree().paused = false
	_quit_requested = true
	preload("res://scripts/core/FxTier.gd").end_session()
	get_tree().quit()

# Best per-call time in microseconds for method `name` over `objs` (one pass).
func _time_calls(objs: Array, name: String, args: Array) -> float:
	var n := 0
	var t0 := Time.get_ticks_usec()
	for o in objs:
		if is_instance_valid(o):
			o.callv(name, args)
			n += 1
	return float(Time.get_ticks_usec() - t0) / max(n, 1)

func _projectile_count() -> int:
	var n := get_tree().get_nodes_in_group("projectile").size()
	if is_instance_valid(ProjectileManager.live_batch_pool):
		n += ProjectileManager.live_batch_pool.live_count()
	return n

# CPU-speed canary. This machine thermally throttles (kidle_inj idle injection at ~93 C) and shares the CPU
# with other apps, so identical runs can differ by 30-50%. A fixed pure-compute workload timed once a second
# tells us how fast the CPU was running; the summary reports norm_fps = avg_fps * mean_cal_ms / CAL_REF_MS
# (a slow CPU, longer canary, scales fps UP), which makes A/B runs comparable.
const CAL_ITERS := 60000
const CAL_REF_MS := 4.0
var _cal_sum := 0.0
var _cal_n := 0
func _cpu_canary_ms() -> float:
	var t0 := Time.get_ticks_usec()
	var x := 0.0
	for k in range(CAL_ITERS):
		x += sqrt(float(k)) * 0.5
	if x < 0.0:
		print(x) # keep the loop from being optimised away
	return (Time.get_ticks_usec() - t0) / 1000.0

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
		"sim_s": _sim_t, "frames_total": Engine.get_frames_drawn() - _frames0, "phys_frames_total": Engine.get_physics_frames() - _phys0,
		"garage_autoclosed": _garage_autoclosed, "peak_enemies": _peak["enemies"], "peak_projectiles": _peak["projectiles"], "peak_nodes": _peak["nodes"],
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
		if _speed_n > 0:
			out["mean_sim_speed"] = snappedf(_speed_sum / _speed_n, 0.01)
			out["mean_ticks_per_frame"] = snappedf(_tpf_sum / _speed_n, 0.1)
		if _cal_n > 0:
			var cal := _cal_sum / _cal_n
			out["mean_cal_ms"] = snappedf(cal, 0.01)
			out["norm_fps"] = snappedf(out["avg_fps"] * cal / CAL_REF_MS, 0.1)
			out["norm_p50_ms"] = snappedf(out["p50_ms"] * CAL_REF_MS / cal, 0.1)
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
