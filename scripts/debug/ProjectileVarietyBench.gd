extends Node

# Frame-time benchmark for projectile VARIETY (many different synergy mixes
# on screen at once). Run windowed:
#   godot --audio-driver Dummy --path . res://scripts/debug/ProjectileVarietyBench.tscn -- --mode=legacy|batch --volleys=N --seconds=S [--nocons] [--single]
# --volleys = volleys fired per second from each of 4 mounts; --single makes
# every shot the same element (control for the "variety" cost); --nocons
# disables the saturation consolidation so raw per-shot cost is measured.

const MechScript = preload("res://scripts/entities/Mech.gd")
const WeaponMountTileScript = preload("res://scripts/tiles/WeaponMountTile.gd")
const PoolScript = preload("res://scripts/entities/ProjectileBatchPool.gd")

var _mode := "legacy"
var _rate := 30
var _seconds := 12.0
var _single := false
var _nocons := false
var _nodraw := false
var _shot := ""
var _poly := false
var _rmode := 0
var _shot_done := false
var _mechs: Array = []
var _mounts: Array = []
var _acc := 0.0
var _t := 0.0
var _frames: Array[float] = []
var _peak_live := 0
var _peak_nodes := 0
var _world: Node2D

func _ready():
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="): _mode = a.split("=")[1]
		elif a.begins_with("--volleys="): _rate = int(a.split("=")[1])
		elif a.begins_with("--seconds="): _seconds = float(a.split("=")[1])
		elif a == "--single": _single = true
		elif a == "--nocons": _nocons = true
		elif a == "--nodraw": _nodraw = true
		elif a.begins_with("--shot="): _shot = a.split("=")[1]
		elif a == "--poly": _poly = true
		elif a.begins_with("--render="): _rmode = int(a.split("=")[1])
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	seed(7)
	_world = Node2D.new()
	add_child(_world)
	var cam = Camera2D.new()
	cam.position = Vector2(0, -150)
	cam.zoom = Vector2(1.6, 1.6)
	_world.add_child(cam)
	if _mode == "batch":
		SaveManager.batch_renderer_in_combat = true
		var pool = PoolScript.new()
		_world.add_child(pool)
		ProjectileManager.live_batch_pool = pool
		if _nodraw: pool.visible = false
		if _poly: pool.use_atlas = false
		pool.render_mode = _rmode
	else:
		SaveManager.batch_renderer_in_combat = false
	for i in range(4):
		var m = MechScript.new()
		m.is_player = true
		_world.add_child(m)
		m.set_physics_process(false)
		m.global_position = Vector2(-200 + i * 130, 120)
		m.last_aim_position = m.global_position + Vector2(cos(i * 1.3) * 600, -500)
		var mt = WeaponMountTileScript.new()
		mt.rarity = HexTile.Rarity.RARE
		mt.body_slot = HexTile.BodySlot.TORSO
		_mechs.append(m)
		_mounts.append(mt)

func _random_packet() -> EnergyPacket:
	var p = EnergyPacket.new(randf_range(30.0, 400.0), null)
	var types = [1, 2, 3, 4, 5, 6, 7, 8, 9]
	if _single:
		p.add_synergy(3, p.magnitude)
		return p
	types.shuffle()
	var n = randi_range(1, 3)
	for k in range(n):
		p.add_synergy(types[k], p.magnitude * randf_range(0.2, 1.0))
	return p

func _process(delta):
	_t += delta
	_frames.append(delta)
	if _nocons:
		pass
	_acc += delta * _rate
	while _acc >= 1.0:
		_acc -= 1.0
		for i in range(_mounts.size()):
			_mounts[i]._fire_combined_projectile(_mechs[i], _random_packet(), 0)
	var live = ProjectileManager.live_count()
	if _mode == "batch" and is_instance_valid(ProjectileManager.live_batch_pool):
		live += ProjectileManager.live_batch_pool.live_count()
	_peak_live = max(_peak_live, live)
	_peak_nodes = max(_peak_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	if _shot != "" and _t >= _seconds * 0.8 and not _shot_done:
		_shot_done = true
		get_viewport().get_texture().get_image().save_png(_shot)
	if _t >= _seconds:
		var warm = _frames.slice(int(_frames.size() * 0.4))
		warm.sort()
		var sum = 0.0
		for f in warm: sum += f
		print("BENCH render=%d mode=%s volleys=%d single=%s avg_ms=%.2f p95_ms=%.2f max_ms=%.2f fps=%.1f peak_live=%d peak_nodes=%d draw=%d" % [_rmode, _mode, _rate, _single, sum / warm.size() * 1000.0, warm[int(warm.size() * 0.95)] * 1000.0, warm[-1] * 1000.0, warm.size() / sum, _peak_live, _peak_nodes, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
		get_tree().quit()
