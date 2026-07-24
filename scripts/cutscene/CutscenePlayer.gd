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
#                                                 # or {"scene": "shop"} - shared
#                                                 # procedural backdrop, see
#                                                 # _make_shop_background_texture
#     "actors": {
#       "frank": {"texture": "res://assets/cutscenes/frank.png",
#                "hframes": 4, "vframes": 1, "fps": 6, "scale": 4,
#                "placeholder_color": "#4d8bd4"}  # used if texture missing
#       "case": {"kind": "prop", "texture": "res://assets/cutscenes/glass_case.png",
#                "scale": 4, "placeholder_color": "#6a7a8a"}  # shop set-dressing -
#                # see _make_prop_placeholder_texture for the untextured look
#     },
#     "steps": [                                  # run strictly in order
#       {"cmd": "enter", "actor": "frank", "from": [-0.1, 0.7], "to": [0.3, 0.7], "duration": 1.2},
#       {"cmd": "say",   "actor": "frank", "name": "Frank", "text": "...", "auto": 4.0},
#       {"cmd": "move",  "actor": "frank", "to": [0.5, 0.7], "duration": 0.8},
#       {"cmd": "shake", "actor": "frank", "duration": 0.4, "strength": 6},
#       {"cmd": "flip",  "actor": "frank"},
#       {"cmd": "wait",  "duration": 0.5},
#       {"cmd": "exit",  "actor": "frank", "to": [1.1, 0.7], "duration": 1.0}
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
	elif str(bg_data.get("scene", "")) == "shop":
		# Shared procedural backdrop (per the user: "use the same background
		# for all in shop cinematics?") - every Frank scene was either a flat
		# color or (tutorial_welcome) two floating prop rectangles with
		# nothing establishing they're sitting in a room at all. One
		# generated texture, reused by every in-shop cutscene JSON via
		# "background": {"scene": "shop"} - no per-file art needed.
		var bg_tex = TextureRect.new()
		bg_tex.texture = _make_shop_background_texture()
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
		# prop_type picks the SILHOUETTE (not just the color) - playtest
		# report: "not clear what the two blocks are" - register and case
		# used to share the exact same shape (just different flat colors),
		# so neither one actually read as a specific object.
		sprite.texture = _make_prop_placeholder_texture(Color.html(str(def.get("placeholder_color", "#6a7a8a"))), str(def.get("prop_type", "case")))
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

# Shop set-dressing silhouettes - deliberately NOT the tall narrow humanoid
# shape above, so furniture reads as furniture at a glance even before real
# prop art exists. prop_type picks a genuinely different SHAPE, not just a
# different color, per the user's playtest report that register/case used
# to be visually identical (same wide flat-topped rectangle) and neither
# one read as a specific object.
static func _make_prop_placeholder_texture(body: Color, prop_type: String = "case") -> ImageTexture:
	if prop_type == "register":
		return _make_register_texture(body)
	return _make_case_texture(body)

# Glass display counter, waist-high on the shop floor and MUCH longer than
# a single small case - per the user: "half as tall as Frank" (still) but
# "the counter should be much longer" - a real shop counter, not a single
# small kiosk box. Frank's own placeholder is 16x24 at scale 5 -> 120px on
# screen; this texture is sized/scaled (see tutorial_welcome.json's
# "scale": 2 on a 30px-tall texture -> 60px) to land at exactly half that.
const COUNTER_HEIGHT = 30
static func _make_case_texture(body: Color) -> ImageTexture:
	var w = 140
	var img = Image.create(w, COUNTER_HEIGHT, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var dark = body.darkened(0.45)
	var glass = body.lightened(0.5)
	glass.a = 0.55
	for y in range(4, COUNTER_HEIGHT):
		for x in range(1, w - 1):
			var edge = (y == 4 or y == COUNTER_HEIGHT - 1 or x == 1 or x == w - 2)
			img.set_pixel(x, y, dark if edge else body)
	# Glass display band across most of the counter's height, not just a
	# thin strip near the top - reads as a real glass front you can see
	# through, not a decorative racing stripe.
	for y in range(6, COUNTER_HEIGHT - 6):
		for x in range(3, w - 3):
			img.set_pixel(x, y, glass)
	return ImageTexture.create_from_image(img)

# Cash register - no table/legs of its own anymore. Per the user: "the
# bottom of the register should be the top of the counter" - it sits
# DIRECTLY on the glass counter above, not on a separate wooden table.
# Bottom row of this texture is the register's own flush base, positioned
# in tutorial_welcome.json so that base lines up with the counter's top
# edge (see that file's comment on the register step for the math).
static func _make_register_texture(body: Color) -> ImageTexture:
	var img = Image.create(24, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var dark = body.darkened(0.45)
	var screen = Color(0.95, 0.85, 0.4, 0.9) # warm amber readout

	# Base, flush with the texture's bottom edge.
	for y in range(9, 20):
		for x in range(2, 22):
			var edge = (y == 9 or y == 19 or x == 2 or x == 21)
			img.set_pixel(x, y, dark if edge else body)

	# Raised till/screen block on top of the base.
	for y in range(1, 9):
		for x in range(4, 13):
			var edge = (y == 1 or x == 4 or x == 12)
			img.set_pixel(x, y, dark if edge else body)
	for x in range(6, 11):
		img.set_pixel(x, 3, screen)

	# Keypad dots on the base's front face.
	for row in range(2):
		for col in range(4):
			img.set_pixel(14 + col * 2, 12 + row * 3, dark)

	return ImageTexture.create_from_image(img)

# Shared procedural shop interior backdrop (per the user: reuse one
# background across every in-shop cutscene rather than a flat void color).
# Flat-shaded bands, not smooth gradients - matches the fat-pixel/discrete
# shading convention used everywhere else (MapGenerator's biome painting,
# DestructibleObstacle silhouettes) rather than a smooth-gradient look that
# would clash with it. Generated once per cutscene playback, not cached -
# cheap (single-digit ms for a 384x216 canvas) and playbacks are rare
# (between-wave beats), so a cache would be premature.
static func _make_shop_background_texture() -> ImageTexture:
	var w = 384
	var h = 216
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)

	var wall_upper = Color(0.055, 0.06, 0.085)
	var wall_lower = Color(0.08, 0.085, 0.11)
	var floor_far = Color(0.1, 0.09, 0.08)
	var floor_near = Color(0.14, 0.12, 0.1)
	var horizon = int(h * 0.66)
	var wall_split = int(horizon * 0.6)

	for y in range(h):
		var row_color: Color
		if y < wall_split:
			row_color = wall_upper
		elif y < horizon:
			row_color = wall_lower
		else:
			row_color = floor_near if y > horizon + int((h - horizon) * 0.5) else floor_far
		for x in range(w):
			img.set_pixel(x, y, row_color)

	# Floor seam lines - a few flat bands suggesting tile/plank joints,
	# spaced wider apart toward the "camera" (bottom of frame) for a cheap
	# sense of depth without an actual perspective transform.
	var seam = floor_far.darkened(0.35)
	for seam_y in [horizon + 4, horizon + 14, horizon + 30, horizon + 52]:
		if seam_y < h:
			for x in range(w):
				img.set_pixel(x, seam_y, seam)

	# Wall shelving, floor to (near) ceiling, spread across the whole back
	# wall - per the user: "covered in cards... shelves covered in boxes of
	# cards, boardgames, miniatures... much less sparse." Fixed seed so the
	# shop looks the same every time it's generated, not different clutter
	# per playback. Six zones across the wall, each stacked pegboard (CCG
	# hangtag cards) -> shelf (boxed games) -> shelf (painted miniatures).
	var rng = RandomNumberGenerator.new()
	rng.seed = 1337
	var zone_w = 58
	for zone_x in [4, 68, 132, 196, 260, 324]:
		_draw_pegboard_cards(img, zone_x, 6, zone_w, 34, rng, wall_lower)
		_draw_shelf_boxes(img, zone_x, 46, zone_w, 38, rng, wall_lower)
		_draw_shelf_minis(img, zone_x, 90, zone_w, 26, rng, wall_lower)

	# Warm work-light pool on the floor near the counter (where Frank
	# usually stands) - a flat tinted patch, not a radial blur, matching
	# the flat-shaded convention above.
	var glow = Color(0.35, 0.28, 0.15, 0.35)
	var glow_x0 = int(w * 0.22)
	var glow_x1 = int(w * 0.5)
	for y in range(horizon, h):
		for x in range(glow_x0, glow_x1):
			var base = img.get_pixel(x, y)
			img.set_pixel(x, y, base.lerp(glow, glow.a))

	return ImageTexture.create_from_image(img)

# Pegboard hung with small CCG-style hangtag cards - a grid of tiny colored
# rectangles (booster-pack-ish palette) each with a punched "hang hole" dot,
# on a slightly lighter board backing so it reads as mounted on the wall.
static func _draw_pegboard_cards(img: Image, x0: int, y0: int, zone_w: int, zone_h: int, rng: RandomNumberGenerator, wall_color: Color):
	var board = wall_color.lightened(0.08)
	for y in range(y0, y0 + zone_h):
		for x in range(x0, x0 + zone_w):
			img.set_pixel(x, y, board)
	var palette = [Color(0.75, 0.25, 0.28), Color(0.25, 0.42, 0.78), Color(0.3, 0.62, 0.35), Color(0.82, 0.66, 0.24), Color(0.56, 0.36, 0.72)]
	var card_w = 5
	var card_h = 6
	var gap = 2
	var y = y0 + 3
	while y + card_h < y0 + zone_h:
		var x = x0 + 3
		while x + card_w < x0 + zone_w:
			var col: Color = palette[rng.randi() % palette.size()]
			for cy in range(card_h):
				for cx in range(card_w):
					img.set_pixel(x + cx, y + cy, col)
			img.set_pixel(x + card_w / 2, y, Color(0.05, 0.05, 0.05, 0.6)) # hang hole
			x += card_w + gap
		y += card_h + gap

# A shelf ledge stacked with boxed product (board games/card boxes) -
# varied widths/heights/colors sitting on a lit ledge line.
static func _draw_shelf_boxes(img: Image, x0: int, y0: int, zone_w: int, zone_h: int, rng: RandomNumberGenerator, wall_color: Color):
	var ledge = wall_color.darkened(0.2)
	var ledge_y = y0 + zone_h - 3
	for x in range(x0, x0 + zone_w):
		img.set_pixel(x, ledge_y, ledge.lightened(0.3))
		for y in range(ledge_y + 1, y0 + zone_h):
			img.set_pixel(x, y, ledge)
	var palette = [Color(0.5, 0.35, 0.2), Color(0.35, 0.15, 0.15), Color(0.2, 0.25, 0.4), Color(0.4, 0.42, 0.22), Color(0.55, 0.5, 0.4)]
	var x = x0 + 2
	while x < x0 + zone_w - 6:
		var bw = 6 + rng.randi() % 6
		var bh = min(10 + rng.randi() % 14, ledge_y - y0 - 2)
		var col: Color = palette[rng.randi() % palette.size()]
		var dark = col.darkened(0.4)
		var bx1 = min(x + bw, x0 + zone_w)
		for by in range(ledge_y - bh, ledge_y):
			for bx in range(x, bx1):
				var edge = (by == ledge_y - bh or bx == x or bx == bx1 - 1)
				img.set_pixel(bx, by, dark if edge else col)
		x += bw + 2

# A shelf ledge lined with small painted-miniature silhouettes - thin
# vertical blobs with a slight per-figure color tint, suggesting a
# painted-minis display without needing real sculpted detail.
static func _draw_shelf_minis(img: Image, x0: int, y0: int, zone_w: int, zone_h: int, rng: RandomNumberGenerator, wall_color: Color):
	var ledge = wall_color.darkened(0.2)
	var ledge_y = y0 + zone_h - 2
	for x in range(x0, x0 + zone_w):
		img.set_pixel(x, ledge_y, ledge.lightened(0.3))
	var mini_base = Color(0.5, 0.5, 0.56)
	var x = x0 + 3
	while x < x0 + zone_w - 3:
		var mh = 5 + rng.randi() % 5
		var tint = mini_base.lerp(Color(rng.randf(), rng.randf(), rng.randf()), 0.15)
		for y in range(ledge_y - mh, ledge_y):
			img.set_pixel(x, y, tint)
			if mh > 6:
				img.set_pixel(x + 1, y, tint.darkened(0.15))
		x += 3

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
