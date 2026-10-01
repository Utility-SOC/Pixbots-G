extends Node
# Plays a REAL wave 1: waits for enemies to spawn, kills them through the normal
# damage path, skips the wave-2 cinematic, then runs a few seconds of wave 2.
# Watch the FlightRecorder log (user://flight) for "INVARIANT BROKEN".
var _main: Node
var _t := 0.0
var _phase := 0
var _kill_t := 0.0
var _after_t := 0.0
func _ready():
	SaveManager.current_game_mode = "campaign"
	_main = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(_main)
	(func(): get_tree().current_scene = _main).call_deferred()
func _cutscene():
	for c in _main.get_children():
		var sc = c.get_script()
		if sc and str(sc.resource_path).ends_with("CutscenePlayer.gd"): return c
	return null
func _process(d):
	_t += d
	if is_instance_valid(_main.player):
		_main.player.hp = _main.player.max_hp
	if _phase == 0 and _t > 2.0 and is_instance_valid(_main.garage_ui):
		_main._close_garage(); _phase = 1
	if _phase == 1 and _main.current_wave == 1 and get_tree().get_nodes_in_group("enemy").size() > 0:
		_phase = 2; _main._map_rotation_elapsed = 999.0; print("RW wave1 enemies present: ", get_tree().get_nodes_in_group("enemy").size())
	if _phase == 2:
		_kill_t += d
		if _kill_t > 1.5:
			_kill_t = 0.0
			for e in get_tree().get_nodes_in_group("enemy"):
				if is_instance_valid(e) and e.has_method("apply_damage"):
					e.apply_damage(99999.0, "RAW", _main.player)
		if _main.current_wave >= 2: _phase = 3; print("RW wave advanced to ", _main.current_wave)
	if _phase == 3:
		var cs = _cutscene()
		if cs:
			print("RW cutscene up; skipping"); cs.skip()
		_after_t += d
		if _after_t > 14.0: print("RW done"); get_tree().quit()
	if _t > 150.0: print("RW timeout phase=", _phase); get_tree().quit()
