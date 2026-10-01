extends Node
# Flight recorder ("look over my shoulder"). Autoload; polls game state ~4x/sec,
# writes a timestamped log + screenshots under user://flight/ and echoes
# "[REC]" lines to stdout so a launcher/console can tail them.
#   - state-change events: wave, map swap, pause, cutscene, garage, loadout, player, redraw
#   - invariant checks on the hero's body (parts missing/hidden/under the map)
#     -> auto-screenshot + state dump when one breaks
#   - F9: manual screenshot + snapshot ("something just looked wrong")
#   - delayed screenshots 1s after wave clear / map swap / cutscene end / garage close
# Off in headless runs. Disable entirely with --no-recorder.

const POLL := 0.25
const KEEP_SHOTS := 80
const VIOLATION_COOLDOWN := 3.0
var _dir_user := "user://flight"
var _log: FileAccess = null
var _t0 := 0
var _acc := 0.0
var _prev: Dictionary = {}
var _last_violation_sig := ""
var _last_violation_t := -99.0
var _pending_shots: Array = [] # [due_msec, label]
var _shot_n := 0
var _enabled := true

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless" or "--no-recorder" in OS.get_cmdline_user_args():
		_enabled = false
		set_process(false)
		set_process_unhandled_input(false)
		return
	DirAccess.make_dir_recursive_absolute(_dir_user)
	_t0 = Time.get_ticks_msec()
	var stamp = Time.get_datetime_string_from_system().replace(":", "-")
	_log = FileAccess.open("%s/session_%s.log" % [_dir_user, stamp], FileAccess.WRITE)
	_emit("session start, build=%s" % str(ProjectSettings.get_setting("application/config/version", "?")))

func _unhandled_input(event):
	if _enabled and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F9:
		_emit("F9 pressed", _snap())
		_shoot("manual")
		get_viewport().set_input_as_handled()

func _process(delta):
	var now = Time.get_ticks_msec()
	while not _pending_shots.is_empty() and _pending_shots[0][0] <= now:
		_shoot(_pending_shots.pop_front()[1])
	_acc += delta
	if _acc < POLL:
		return
	_acc = 0.0
	_poll()

func _scene() -> Node:
	return get_tree().current_scene

func _main_like(s: Node) -> bool:
	return s != null and "player" in s and "current_wave" in s

func _has_cutscene(s: Node) -> bool:
	for c in s.get_children():
		var sc = c.get_script()
		if sc and str(sc.resource_path).ends_with("CutscenePlayer.gd"):
			return true
	return false

func _comp_sig(p: Node) -> String:
	var parts: PackedStringArray = []
	var keys = p.components.keys()
	keys.sort()
	for k in keys:
		var c = p.components[k]
		var n = c.hex_grid.get_all_tiles().size() if c and c.hex_grid else -1
		parts.append("%s:%s/r%s/t%d" % [k, c.component_name if c else "null", c.rarity if c else "-", n])
	return ",".join(parts)

func _poll():
	var s = _scene()
	var cur: Dictionary = {"scene": s.name if s else "none", "paused": get_tree().paused}
	if _main_like(s):
		cur["wave"] = s.current_wave
		cur["map"] = s.map.get_instance_id() if is_instance_valid(s.map) else 0
		cur["map_type"] = s.map.map_type if is_instance_valid(s.map) else ""
		cur["cutscene"] = _has_cutscene(s)
		cur["garage"] = is_instance_valid(s.garage_ui)
		var p = s.player
		cur["player"] = p.get_instance_id() if is_instance_valid(p) else 0
		if is_instance_valid(p):
			cur["loadout"] = _comp_sig(p)
			var r = p._renderer
			cur["redraw"] = r.drawn_parts["Torso"].get_instance_id() if is_instance_valid(r) and r.drawn_parts.has("Torso") else 0
	for k in cur:
		if _prev.get(k) != cur[k]:
			_on_change(k, _prev.get(k), cur[k])
	_prev = cur
	if _main_like(s) and is_instance_valid(s.player):
		_check_invariants(s)

func _on_change(key: String, old, new):
	if key in ["loadout", "redraw", "map_type"]:
		_emit("%s changed: %s -> %s" % [key, str(old).left(120), str(new).left(120)])
		return
	_emit("%s: %s -> %s" % [key, str(old), str(new)], _snap())
	var post := false
	if key == "wave" or key == "map" or (key == "cutscene" and new == false) or (key == "garage" and new == false):
		post = true
	if post:
		_pending_shots.append([Time.get_ticks_msec() + 1000, "after_" + key])

# Things that must hold for the hero's body to be on screen.
func _check_invariants(s: Node):
	var p = s.player
	var r = p._renderer
	var bad: PackedStringArray = []
	if not is_instance_valid(r):
		bad.append("no renderer")
	else:
		for part in ["Torso", "Arm_true", "Arm_false", "Leg_true", "Leg_false", "Head"]:
			if not r.drawn_parts.has(part) or not is_instance_valid(r.drawn_parts[part]):
				bad.append("missing part " + part)
				continue
			var n: Node2D = r.drawn_parts[part]
			if not n.is_visible_in_tree():
				bad.append(part + " not visible in tree")
			if n.modulate.a < 0.05:
				bad.append(part + " transparent")
			if absf(n.scale.x) < 0.2 or absf(n.scale.y) < 0.2:
				bad.append(part + " collapsed scale")
			if n.get_child_count() == 0:
				bad.append(part + " has no draw children")
			elif n.z_index + p.z_index <= (s.map.z_index if is_instance_valid(s.map) else -99) and is_instance_valid(s.map) \
					and s.map.get_parent() == p.get_parent() and s.map.get_index() > p.get_index():
				bad.append(part + " drawn under the map (child order)")
	for slot in [HexTile.BodySlot.ARM_L, HexTile.BodySlot.ARM_R, HexTile.BodySlot.LEG_L, HexTile.BodySlot.LEG_R]:
		if not p.components.has(slot):
			bad.append("no component in slot %s" % str(slot))
	if bad.is_empty():
		_last_violation_sig = ""
		return
	var sig = ";".join(bad)
	var t = Time.get_ticks_msec() / 1000.0
	if sig == _last_violation_sig or t - _last_violation_t < VIOLATION_COOLDOWN:
		return
	_last_violation_sig = sig
	_last_violation_t = t
	_emit("INVARIANT BROKEN: " + sig, _snap())
	_shoot("violation")

func _snap() -> Dictionary:
	var s = _scene()
	var d: Dictionary = {"scene": s.name if s else "none", "paused": get_tree().paused}
	if _main_like(s):
		d["wave"] = s.current_wave
		d["lives"] = s.get("player_lives_remaining")
		d["map_type"] = s.map.map_type if is_instance_valid(s.map) else ""
		d["map_index"] = s.map.get_index() if is_instance_valid(s.map) else -1
		d["cutscene"] = _has_cutscene(s)
		d["garage_open"] = is_instance_valid(s.garage_ui)
		d["enemies"] = s.get("active_enemies")
		var p = s.player
		if is_instance_valid(p):
			d["player_index"] = p.get_index()
			d["hp"] = "%d/%d" % [int(p.hp), int(p.max_hp)]
			d["loadout"] = _comp_sig(p)
			var r = p._renderer
			var parts: Dictionary = {}
			if is_instance_valid(r):
				for k in r.drawn_parts:
					var n = r.drawn_parts[k]
					if is_instance_valid(n):
						parts[k] = "vis=%s gvis=%s z=%d scale=(%.2f,%.2f) a=%.2f kids=%d" % [n.visible, n.is_visible_in_tree(), n.z_index, n.scale.x, n.scale.y, n.modulate.a, n.get_child_count()]
			d["parts"] = parts
	return d

func _emit(msg: String, snap = null):
	var line = "[REC +%6.1fs] %s" % [(Time.get_ticks_msec() - _t0) / 1000.0, msg]
	if snap != null:
		line += "\n   snap=" + JSON.stringify(snap)
	print(line)
	if _log:
		_log.store_line(line)
		_log.flush()

func _shoot(label: String):
	var tex = get_viewport().get_texture()
	if tex == null:
		return
	var img = tex.get_image()
	if img == null:
		return
	_shot_n += 1
	var path = "%s/shot_%04d_%s.png" % [_dir_user, _shot_n, label]
	img.save_png(ProjectSettings.globalize_path(path))
	_emit("screenshot -> " + ProjectSettings.globalize_path(path))
	_trim()

func _trim():
	var d = DirAccess.open(_dir_user)
	if d == null:
		return
	var shots: Array = []
	for f in d.get_files():
		if f.begins_with("shot_") and f.ends_with(".png"):
			shots.append(f)
	shots.sort()
	while shots.size() > KEEP_SHOTS:
		d.remove(shots.pop_front())
