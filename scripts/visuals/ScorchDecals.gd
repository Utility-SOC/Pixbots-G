extends MultiMeshInstance2D

# Burn marks left by explosions. One MultiMesh holds a ring buffer of MAX_MARKS decals, so hundreds of
# marks cost a single draw call (the per-mark Polygon2D crater this complements is one draw each).
# Marks fade slowly: alpha is refreshed once a second, not per frame.

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
var _xforms: Array = []
var _tick := 0.0

# Entry point: safe to call from anywhere, does nothing when there is no world to draw into
# (headless checks, menus).
static func mark(tree: SceneTree, pos: Vector2, radius: float, tint: Color = Color(0.05, 0.04, 0.04)) -> void:
	if tree == null or tree.current_scene == null:
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

func _ready():
	z_index = -9 # above terrain (-10 craters), below every entity
	texture = _blob_texture()
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	var quad = QuadMesh.new()
	quad.size = Vector2(1, 1)
	mm.mesh = quad
	mm.instance_count = MAX_MARKS
	mm.visible_instance_count = 0
	multimesh = mm
	_born.resize(MAX_MARKS)
	_base_alpha.resize(MAX_MARKS)
	_alpha.resize(MAX_MARKS)
	_tint.resize(MAX_MARKS)
	_xforms.resize(MAX_MARKS)

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
	var rot = (pos.x * 12.9898 + pos.y * 78.233)
	var xf = Transform2D(rot, Vector2(r * 1.6, r * 1.6), 0.0, pos)
	multimesh.set_instance_transform_2d(idx, xf)
	_xforms[idx] = xf
	_tint[idx] = tint
	_base_alpha[idx] = clampf(0.35 + r / 400.0, 0.35, 0.7)
	_born[idx] = Time.get_ticks_msec() / 1000.0
	_alpha[idx] = _base_alpha[idx]
	multimesh.set_instance_color(idx, Color(tint.r, tint.g, tint.b, _alpha[idx]))
	multimesh.visible_instance_count = mini(_count, MAX_MARKS)

func _process(delta: float):
	_tick += delta
	if _tick < FADE_TICK:
		return
	_tick = 0.0
	var now = Time.get_ticks_msec() / 1000.0
	var n = mini(_count, MAX_MARKS)
	for i in range(n):
		var age = (now - _born[i]) / LIFETIME
		var a = _base_alpha[i] * clampf(1.0 - age, 0.0, 1.0)
		var t: Color = _tint[i]
		_alpha[i] = a
		multimesh.set_instance_color(i, Color(t.r, t.g, t.b, a))
