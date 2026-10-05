class_name StatusAura
extends Node2D

# Particle look for the burning and poisoned statuses on a Mech: orange/yellow
# embers rising off a burning bot, green bubbles drifting up and popping off a
# poisoned one. Both can show at once. Particles are textured quads from ONE
# shared soft-disc texture (same-texture quads batch into a single draw, unlike
# per-particle draw_circle), simulated analytically from a clock (no per-
# particle state), and the aura only redraws while a status is active. A global
# cap keeps a screen full of burning bots from adding unbounded draw cost.

const MAX_AURAS = 28
const EMBERS = 8
const BUBBLES = 6
const BODY_RADIUS = 36.0

static var _tex: ImageTexture = null
static var _count: int = 0

var mech: Node
var _t: float = 0.0
var _seed: float = 0.0

static func _ensure_tex() -> void:
	if _tex != null:
		return
	var n = 32
	var img = Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in range(n):
		for x in range(n):
			var d = Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
			var a = clamp(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_tex = ImageTexture.create_from_image(img)

# Called from Mech.apply_status; at most one aura per mech, capped globally.
static func ensure_on(m: Node) -> void:
	if m.has_node("StatusAura"):
		return
	if _count >= MAX_AURAS:
		return
	var aura = load("res://scripts/visuals/StatusAura.gd").new()
	aura.name = "StatusAura"
	aura.mech = m
	m.add_child(aura)

func _init() -> void:
	z_index = 8
	var mat = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat

func _enter_tree() -> void:
	_count += 1
	_seed = float(get_instance_id() % 1000) / 1000.0
	_ensure_tex()

func _exit_tree() -> void:
	_count -= 1

func _process(delta: float) -> void:
	if not is_instance_valid(mech):
		queue_free()
		return
	var fx = mech.get("status_effects")
	if fx == null or (not fx.has("burning") and not fx.has("poisoned")):
		queue_free()
		return
	_t += delta
	queue_redraw()

func _quad(pos: Vector2, size: float, col: Color) -> void:
	draw_texture_rect(_tex, Rect2(pos - Vector2(size, size) * 0.5, Vector2(size, size)), false, col)

func _draw() -> void:
	if not is_instance_valid(mech):
		return
	var fx = mech.get("status_effects")
	if fx == null:
		return
	if fx.has("burning"):
		for k in range(EMBERS):
			var ph = fmod(_t * 1.6 + float(k) / EMBERS + _seed, 1.0) # 0..1 life
			var h = (float(k) * 0.618 + _seed) # per-ember stable offset
			var x = (fmod(h * 7.0, 1.0) - 0.5) * 2.0 * BODY_RADIUS * (1.0 - ph * 0.5)
			x += sin((_t + h) * 9.0) * 3.0 * ph
			var y = BODY_RADIUS * 0.3 - ph * BODY_RADIUS * 2.2
			var size = lerp(34.0, 8.0, ph)
			var col = Color(1.0, lerp(0.35, 0.9, ph), lerp(0.05, 0.2, ph), (1.0 - ph) * 1.0)
			_quad(Vector2(x, y), size, col)
	if fx.has("poisoned"):
		for k in range(BUBBLES):
			var ph = fmod(_t * 0.7 + float(k) / BUBBLES + _seed * 0.5, 1.0)
			var h = (float(k) * 0.381 + _seed)
			var x = (fmod(h * 5.0, 1.0) - 0.5) * 2.0 * BODY_RADIUS + sin((_t + h) * 3.0) * 4.0
			var y = BODY_RADIUS * 0.6 - ph * BODY_RADIUS * 1.8
			var size = lerp(11.0, 20.0, ph)
			var pop = 1.0 if ph < 0.85 else (1.0 - (ph - 0.85) / 0.15) # quick pop at the top
			_quad(Vector2(x, y), size, Color(0.35, 0.95, 0.25, 0.95 * pop))
		# faint green sheen at the base so poison reads even between bubbles
		_quad(Vector2(0, BODY_RADIUS * 0.4), BODY_RADIUS * 2.4, Color(0.2, 0.8, 0.15, 0.28))
