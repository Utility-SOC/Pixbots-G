extends Node2D

# Burn marks left by explosions: a ring buffer of MAX_MARKS decals drawn from ONE canvas item with a shared
# texture, which the canvas batcher merges into a handful of draws (the per-mark Polygon2D crater this
# complements is one draw each). Marks fade slowly: redrawn once a second, not per frame.
# (Was a MultiMesh; a player's Ivy Bridge GPU lost its Vulkan device right after a long session using it,
# so this sticks to the same plain textured-quad path the rest of the 2D renderer already exercises.)

const MAX_MARKS = 192
const LIFETIME = 90.0 # seconds to fade out completely
const TEX_SIZE = 64
const FADE_TICK = 1.0

static var _instance: Node = null

var _count := 0 # total ever added (ring index = _count % MAX_MARKS)
var _born := PackedFloat64Array()
var _base_alpha := PackedFloat32Array()
var _alpha := PackedFloat32Array() # last alpha written (the headless renderer cannot read colours back)
var _tint: Array = []
var _tick := 0.0

# Entry point: safe to call from anywhere, does nothing when there is no world to draw into
# (headless checks, menus).
static func mark(tree: SceneTree, pos: Vector2, radius: float, tint: Color = Color(0.05, 0.04, 0.04)) -> void:
	if tree == null or tree.current_scene == null or OS.get_environment("PIXBOTS_SAFE_FX") == "1":
		return
	if _instance == null or not is_instance_valid(_instance):
		var scene = tree.current_scene
		var host = scene.world if "world" in scene and scene.world != null else null
		if host == null:
			return
		_instance = load("res://scripts/visuals/ScorchDecals.gd").new()
		host.add_child(_instance)
	_instance.add_mark(pos, radius, tint)

static func marks_added() -> int:
	return _instance._count if _instance != null and is_instance_valid(_instance) else 0

var _tex: Texture2D
var _pos := PackedVector2Array()
var _size := PackedFloat32Array()

func _ready():
	z_index = -9 # above terrain (-10 craters), below every entity
	_tex = _blob_texture()
	_born.resize(MAX_MARKS)
	_base_alpha.resize(MAX_MARKS)
	_alpha.resize(MAX_MARKS)
	_tint.resize(MAX_MARKS)
	_pos.resize(MAX_MARKS)
	_size.resize(MAX_MARKS)

static func _blob_texture() -> Texture2D:
	var img = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var c = (TEX_SIZE - 1) * 0.5
	var rng = RandomNumberGenerator.new()
	rng.seed = 7
	for y in range(TEX_SIZE):
		for x in range(TEX_SIZE):
			var d = Vector2(x - c, y - c).length() / c
			var ang = atan2(y - c, x - c)
			# ragged edge: radius wobbles with angle
			var edge = 0.82 + 0.05 * sin(ang * 3.0 + 0.4) + 0.035 * sin(ang * 7.0 + 1.3) + 0.02 * sin(ang * 13.0)
			var a = clampf(1.0 - d / edge, 0.0, 1.0)
			a = pow(a, 0.6)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

func add_mark(pos: Vector2, radius: float, tint: Color) -> void:
	var idx = _count % MAX_MARKS
	_count += 1
	var r = clampf(radius, 12.0, 260.0)
	_pos[idx] = pos
	_size[idx] = r * 1.6
	_tint[idx] = tint
	_base_alpha[idx] = clampf(0.35 + r / 400.0, 0.35, 0.7)
	_alpha[idx] = _base_alpha[idx]
	_born[idx] = Time.get_ticks_msec() / 1000.0
	queue_redraw()

func visible_marks() -> int:
	return mini(_count, MAX_MARKS)

func _draw() -> void:
	if _tex == null:
		return
	for i in range(visible_marks()):
		if _alpha[i] <= 0.004:
			continue
		var t: Color = _tint[i]
		var h = _size[i]
		draw_texture_rect(_tex, Rect2(_pos[i] - Vector2(h, h) * 0.5, Vector2(h, h)), false, Color(t.r, t.g, t.b, _alpha[i]))

func _process(delta: float):
	_tick += delta
	if _tick < FADE_TICK:
		return
	_tick = 0.0
	var now = Time.get_ticks_msec() / 1000.0
	for i in range(visible_marks()):
		var age = (now - _born[i]) / LIFETIME
		_alpha[i] = _base_alpha[i] * clampf(1.0 - age, 0.0, 1.0)
	queue_redraw()
