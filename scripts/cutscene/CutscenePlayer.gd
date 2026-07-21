class_name CutscenePlayer
extends CanvasLayer

# Pixel-art cutscene framework (overnight list: "the framework that would be
# needed for pixel art cutscenes (with actual sprites!) to go in between
# waves and rounds"). JSON-driven and data-only - adding a new cutscene means
# dropping a .json in config/cutscenes/ and mapping it in manifest.json,
# no code. Sprite actors are real PNGs (Sprite2D + hframes/vframes flipbook,
# nearest-filtered so pixels stay crisp); an actor whose texture doesn't
# exist yet renders as a procedurally generated pixel-bot placeholder so
# scenes can be scripted and tested before art lands.
#
# Scene JSON shape:
#   {
#     "background": {"color": "#101018"},        # or {"texture": "res://..."}
#     "actors": {
#       "evan": {"texture": "res://assets/cutscenes/evan.png",
#                "hframes": 4, "vframes": 1, "fps": 6, "scale": 4,
#                "placeholder_color": "#4d8bd4"}  # used if texture missing
#       "case": {"kind": "prop", "texture": "res://assets/cutscenes/glass_case.png",
#                "scale": 4, "placeholder_color": "#6a7a8a"}  # shop set-dressing -
#                # see _make_prop_placeholder_texture for the untextured look
#     },
#     "steps": [                                  # run strictly in order
#       {"cmd": "enter", "actor": "evan", "from": [-0.1, 0.7], "to": [0.3, 0.7], "duration": 1.2},
#       {"cmd": "say",   "actor": "evan", "name": "Evan", "text": "...", "auto": 4.0},
#       {"cmd": "move",  "actor": "evan", "to": [0.5, 0.7], "duration": 0.8},
#       {"cmd": "shake", "actor": "evan", "duration": 0.4, "strength": 6},
#       {"cmd": "flip",  "actor": "evan"},
#       {"cmd": "wait",  "duration": 0.5},
#       {"cmd": "exit",  "actor": "evan", "to": [1.1, 0.7], "duration": 1.0}
#     ]
#   }
# Positions are normalized [0..1] viewport fractions (resolution-safe).
# "say" advances on click/Space/Enter (or after "auto" seconds once typed
# out); Esc or the Skip button ends the whole scene instantly. The tree is
# paused for the duration and restored to its prior pause state after.

signal finished

const MANIFEST_PATH = "res://config/cutscenes/manifest.json"
const CUTSCENE_DIR = "res://config/cutscenes/"
const CHARS_PER_SEC = 40.0
const LETTERBOX_H = 56.0

# Played-this-session memory so a wave cutscene never replays after a
# checkpoint kickback to the same wave number. Deliberately NOT persisted:
# a fresh boot replaying story beats is fine (and useful while authoring).
static var _seen_this_session: Dictionary = {}

var cutscene_data: Dictionary = {}

var _actors: Dictionary = {} # name -> Sprite2D
var _actor_anim_t: float = 0.0
var _step_i: int = -1
var _step_t: float = 0.0
var _step: Dictionary = {}
var _move_from: Vector2 = Vector2.ZERO
var _say_full_text: String = ""
var _say_shown: float = 0.0
var _was_paused: bool = false
var _done: bool = false

var _dialogue_panel: PanelContainer = null
var _name_label: Label = null
var _text_label: Label = null

# --- Factory: manifest lookup for a between-waves beat ---------------------
# Returns a ready-to-add_child player, or null (no scene mapped / already
# seen this session / malformed file - all silent no-ops, gameplay never
# blocks on cutscene data). Untyped returns + self-load instead of the own
# class_name: headless check runs don't have the editor's global class
# cache, so in-script self-references to CutscenePlayer fail to compile
# there (load() of an already-loaded script is just a cache hit).
static func maybe_create_for_wave(wave: int):
	var key = str(wave)
	if _seen_this_session.has(key):
		return null
	if not FileAccess.file_exists(MANIFEST_PATH):
		return null
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not (manifest is Dictionary):
		return null
	var waves = manifest.get("waves", {})
	if not (waves is Dictionary) or not waves.has(key):
		return null
	var player = create_from_file(CUTSCENE_DIR + str(waves[key]))
	if player:
		_seen_this_session[key] = true
	return player

static func create_from_file(path: String):
	if not FileAccess.file_exists(path):
		return null
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary) or not (data.get("steps") is Array) or data["steps"].is_empty():
		return null
	var player = load("res://scripts/cutscene/CutscenePlayer.gd").new()
	player.cutscene_data = data
	return player

func _ready():
	layer = 95 # above HUD/minimap, below debug menu (100)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_was_paused = get_tree().paused
	get_tree().paused = true

	var vp = _viewport_size()

	# Backdrop
	var bg = ColorRect.new()
	var bg_data = cutscene_data.get("background", {})
	bg.color = Color.html(str(bg_data.get("color", "#0a0a10")))
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	if bg_data.has("texture") and ResourceLoader.exists(str(bg_data["texture"])):
		var bg_tex = TextureRect.new()
		bg_tex.texture = load(str(bg_data["texture"]))
		bg_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bg_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(bg_tex)

	# Actors (between backdrop and letterbox)
	var actor_defs = cutscene_data.get("actors", {})
	for actor_name in actor_defs.keys():
		var sprite = _build_actor(actor_name, actor_defs[actor_name])
		sprite.visible = false # steps bring them on
		add_child(sprite)
		_actors[actor_name] = sprite

	# Letterbox bars - the "this is a scene, not gameplay" frame
	for at_top in [true, false]:
		var bar = ColorRect.new()
		bar.color = Color.BLACK
		bar.size = Vector2(vp.x, LETTERBOX_H)
		bar.position = Vector2(0, 0 if at_top else vp.y - LETTERBOX_H)
		add_child(bar)

	# Dialogue box
	_dialogue_panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.1, 0.92)
	style.border_color = Color(0.5, 0.6, 0.75, 0.8)
	style.border_width_top = 2
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_dialogue_panel.add_theme_stylebox_override("panel", style)
	_dialogue_panel.position = Vector2(vp.x * 0.1, vp.y - LETTERBOX_H - 110)
	_dialogue_panel.size = Vector2(vp.x * 0.8, 96)
	var dvbox = VBoxContainer.new()
	_dialogue_panel.add_child(dvbox)
	_name_label = Label.new()
	_name_label.modulate = Color(0.7, 0.9, 1.0)
	dvbox.add_child(_name_label)
	_text_label = Label.new()
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dvbox.add_child(_text_label)
	_dialogue_panel.visible = false
	add_child(_dialogue_panel)

	# Skip affordance
	var skip_btn = Button.new()
	skip_btn.text = "Skip (Esc)"
	skip_btn.flat = true
	skip_btn.modulate = Color(1, 1, 1, 0.7)
	skip_btn.position = Vector2(vp.x - 110, LETTERBOX_H + 6)
	skip_btn.pressed.connect(skip)
	add_child(skip_btn)

	_advance_step()

func _viewport_size() -> Vector2:
	var vp = get_viewport()
	return vp.get_visible_rect().size if vp else Vector2(1152, 648)

# --- Actor construction ----------------------------------------------------
func _build_actor(actor_name: String, def: Dictionary) -> Sprite2D:
	var sprite = Sprite2D.new()
	sprite.name = actor_name
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var tex_path = str(def.get("texture", ""))
	var kind = str(def.get("kind", "character"))
	if tex_path != "" and ResourceLoader.exists(tex_path):
		sprite.texture = load(tex_path)
		sprite.hframes = max(1, int(def.get("hframes", 1)))
		sprite.vframes = max(1, int(def.get("vframes", 1)))
	elif kind == "prop":
		# Shop set-dressing (glass card case, cash register, ...) - a plain
		# furniture silhouette, not the humanoid pixel-bot placeholder below,
		# so a scene can be staged/reviewed before real prop art lands too.
		sprite.texture = _make_prop_placeholder_texture(Color.html(str(def.get("placeholder_color", "#6a7a8a"))))
	else:
		# No art yet: procedurally generated pixel-bot placeholder, so a
		# scene can be scripted, staged, and reviewed before the PNG lands.
		sprite.texture = _make_placeholder_texture(Color.html(str(def.get("placeholder_color", "#4d8bd4"))))
	sprite.scale = Vector2.ONE * float(def.get("scale", 4.0))
	sprite.set_meta("fps", float(def.get("fps", 0.0)))
	return sprite

static func _make_placeholder_texture(body: Color) -> ImageTexture:
	var img = Image.create(16, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var dark = body.darkened(0.45)
	for y in range(2, 24):
		for x in range(3, 13):
			var edge = (y == 2 or y == 23 or x == 3 or x == 12)
			img.set_pixel(x, y, dark if edge else body)
	# visor
	for x in range(5, 11):
		img.set_pixel(x, 6, Color(0.95, 0.95, 0.6))
	# antenna
	img.set_pixel(8, 0, dark)
	img.set_pixel(8, 1, dark)
	return ImageTexture.create_from_image(img)

# Wide flat-topped counter/case silhouette - deliberately NOT the tall
# narrow humanoid shape above, so shop set-dressing (a glass card case, a
# cash register, a parts shelf) reads as furniture at a glance even before
# real prop art exists. A lighter "glass" band near the top reads as a
# display case; swap placeholder_color per prop to distinguish them.
static func _make_prop_placeholder_texture(body: Color) -> ImageTexture:
	var img = Image.create(28, 18, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var dark = body.darkened(0.45)
	var glass = body.lightened(0.5)
	glass.a = 0.55
	for y in range(4, 18):
		for x in range(1, 27):
			var edge = (y == 4 or y == 17 or x == 1 or x == 26)
			img.set_pixel(x, y, dark if edge else body)
	# glass band near the top - suggests a display case front
	for x in range(3, 25):
		img.set_pixel(x, 6, glass)
		img.set_pixel(x, 7, glass)
	return ImageTexture.create_from_image(img)

func _norm_to_px(norm) -> Vector2:
	var vp = _viewport_size()
	return Vector2(float(norm[0]) * vp.x, float(norm[1]) * vp.y)

# --- Step machine ----------------------------------------------------------
func _advance_step():
	_step_i += 1
	_step_t = 0.0
	var steps: Array = cutscene_data.get("steps", [])
	if _step_i >= steps.size():
		_finish()
		return
	_step = steps[_step_i]
	var cmd = str(_step.get("cmd", ""))
	var actor: Sprite2D = _actors.get(str(_step.get("actor", "")), null)

	match cmd:
		"enter":
			if actor:
				actor.position = _norm_to_px(_step.get("from", [-0.1, 0.7]))
				_move_from = actor.position
				actor.visible = true
		"move", "exit":
			if actor:
				_move_from = actor.position
		"say":
			_say_full_text = str(_step.get("text", ""))
			_say_shown = 0.0
			_name_label.text = str(_step.get("name", _step.get("actor", "")))
			_text_label.text = ""
			_dialogue_panel.visible = true
		"flip":
			if actor:
				actor.flip_h = not actor.flip_h
			_advance_step() # instant, zero-duration
			return
		"wait", "shake":
			pass
		_:
			# Unknown command: skip it rather than stalling the scene.
			push_warning("CutscenePlayer: unknown cmd '%s' (step %d)" % [cmd, _step_i])
			_advance_step()
			return

func _process(delta):
	if _done:
		return
	_step_t += delta

	# Flipbook animation for any visible multi-frame actor
	_actor_anim_t += delta
	for sprite in _actors.values():
		var fps = float(sprite.get_meta("fps"))
		var total = sprite.hframes * sprite.vframes
		if fps > 0.0 and total > 1 and sprite.visible:
			sprite.frame = int(_actor_anim_t * fps) % total

	var cmd = str(_step.get("cmd", ""))
	var actor: Sprite2D = _actors.get(str(_step.get("actor", "")), null)
	match cmd:
		"enter", "move", "exit":
			var duration = max(0.01, float(_step.get("duration", 1.0)))
			var t = clamp(_step_t / duration, 0.0, 1.0)
			if actor:
				actor.position = _move_from.lerp(_norm_to_px(_step.get("to", [0.5, 0.7])), ease(t, -1.8))
			if t >= 1.0:
				if cmd == "exit" and actor:
					actor.visible = false
				_advance_step()
		"say":
			if _say_shown < _say_full_text.length():
				_say_shown = min(_say_shown + CHARS_PER_SEC * delta, float(_say_full_text.length()))
				_text_label.text = _say_full_text.substr(0, int(_say_shown))
			elif _step.has("auto") and _step_t >= float(_step["auto"]):
				_end_say()
		"wait":
			if _step_t >= float(_step.get("duration", 1.0)):
				_advance_step()
		"shake":
			var duration = float(_step.get("duration", 0.4))
			if actor:
				var strength = float(_step.get("strength", 5.0))
				actor.offset = Vector2(randf_range(-strength, strength), randf_range(-strength, strength))
				if _step_t >= duration:
					actor.offset = Vector2.ZERO
			if _step_t >= duration:
				_advance_step()

func _end_say():
	_dialogue_panel.visible = false
	_advance_step()

# Click / Space / Enter: finish typing first, then advance past the line.
func advance():
	if _done or str(_step.get("cmd", "")) != "say":
		return
	if _say_shown < _say_full_text.length():
		_say_shown = float(_say_full_text.length())
		_text_label.text = _say_full_text
	else:
		_end_say()

func skip():
	_finish()

func _finish():
	if _done:
		return
	_done = true
	get_tree().paused = _was_paused
	finished.emit()
	queue_free()

func _input(event):
	if _done:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			skip()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_SPACE or event.physical_keycode == KEY_ENTER:
			advance()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		advance()
