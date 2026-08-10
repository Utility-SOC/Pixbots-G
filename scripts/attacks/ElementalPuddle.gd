class_name ElementalPuddle
extends Area2D

var _radius: float = 50.0
var _duration: float = 3.0
var _base_damage: float = 10.0
var _synergies: Dictionary = {}
var _by_player: bool = false
var _tick_timer: float = 0.0
var _life_timer: float = 0.0

const TICK_RATE = 0.25 # Apply damage every 0.25s
const MAX_RADIUS = 2000.0

var _victims = []
# Resolved once in setup(), reused by every _apply_tick() call - apply_damage()
# needs a String element name (e.g. "FIRE"), not the raw synergy Dictionary.
var _dominant_element: String = "RAW"

# Visuals
var _circle_poly: Polygon2D
var _outer_color: Color
var _inner_color: Color

func setup(radius: float, duration: float, total_damage: float, synergies: Dictionary, by_player: bool):
	_radius = min(radius, MAX_RADIUS)
	_duration = duration
	# total_damage is expected over the entire duration. So damage per tick:
	var ticks = duration / TICK_RATE
	_base_damage = (total_damage / max(1.0, ticks)) if ticks > 0 else total_damage
	_synergies = synergies.duplicate()
	for k in _synergies:
		_synergies[k] /= max(1.0, ticks)
	_by_player = by_player
	
	# Determine colors based on dominant element
	var dominant = -1
	var dom_val = -1.0
	for k in synergies:
		if synergies[k] > dom_val:
			dom_val = synergies[k]
			dominant = k
			
	_inner_color = Color(1, 1, 1, 0.7)
	_outer_color = Color(1, 1, 1, 0.3)
	
	# Try to map element
	var EnergyPacket = load("res://scripts/core/EnergyPacket.gd")
	if EnergyPacket:
		# apply_damage() needs the dominant element as a String, not the raw
		# synergy Dictionary this file used to pass it directly (real bug -
		# "Cannot convert argument 2 from Dictionary to String" on every
		# tick). EnergyPacket.element_name() is the same helper MortarShell
		# already uses for its own splash/AOE damage calls.
		_dominant_element = EnergyPacket.element_name(dominant)
		match dominant:
			EnergyPacket.SynergyType.FIRE:
				_inner_color = Color(1.0, 0.4, 0.0, 0.7)
				_outer_color = Color(1.0, 0.1, 0.0, 0.3)
			EnergyPacket.SynergyType.ICE:
				_inner_color = Color(0.2, 0.8, 1.0, 0.7)
				_outer_color = Color(0.0, 0.4, 1.0, 0.3)
			EnergyPacket.SynergyType.LIGHTNING:
				_inner_color = Color(1.0, 0.9, 0.2, 0.7)
				_outer_color = Color(0.8, 0.6, 0.0, 0.3)
			EnergyPacket.SynergyType.POISON:
				_inner_color = Color(0.3, 0.9, 0.2, 0.7)
				_outer_color = Color(0.1, 0.5, 0.0, 0.3)
			EnergyPacket.SynergyType.VORTEX:
				# No "VOID" synergy exists in this game (the real set is
				# RAW/FIRE/ICE/LIGHTNING/VORTEX/POISON/EXPLOSION/KINETIC/
				# PIERCE/VAMPIRIC) - this match arm referenced a
				# SynergyType.VOID key that doesn't exist on the
				# EnergyPacket.SynergyType dict, which is a runtime "Invalid
				# access to property or key 'VOID'" crash on every single
				# puddle spawn, not a compile-time-caught typo. Vortex was
				# the one real synergy still uncolored, and a
				# purple/void-ish palette fits it reasonably well.
				_inner_color = Color(0.4, 0.0, 0.8, 0.7)
				_outer_color = Color(0.1, 0.0, 0.3, 0.3)
			EnergyPacket.SynergyType.KINETIC:
				_inner_color = Color(0.7, 0.7, 0.7, 0.7)
				_outer_color = Color(0.4, 0.4, 0.4, 0.3)

func _ready():
	collision_layer = 0
	collision_mask = 4 if _by_player else 8
	monitorable = false
	monitoring = true
	# Findable by EnvironmentalRemediationMech.gd's throttled group scan -
	# "cleans up standing residue from missile explosions" (user request
	# 2026-08-10).
	add_to_group("missile_puddle")
	
	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = _radius
	shape.shape = circle
	add_child(shape)
	
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# Create visual circle
	_circle_poly = Polygon2D.new()
	var points = PackedVector2Array()
	var uvs = PackedVector2Array()
	var colors = PackedColorArray()
	
	var segments = 32
	points.append(Vector2.ZERO)
	uvs.append(Vector2(0.5, 0.5))
	colors.append(_inner_color)
	
	for i in range(segments + 1):
		var angle = (float(i) / segments) * TAU
		var p = Vector2(cos(angle), sin(angle)) * _radius
		points.append(p)
		uvs.append(Vector2(0.5, 0.5) + Vector2(cos(angle), sin(angle)) * 0.5)
		colors.append(_outer_color)
		
	var polys = []
	for i in range(1, segments + 1):
		polys.append([0, i, i + 1])
		
	_circle_poly.polygon = points
	_circle_poly.uv = uvs
	_circle_poly.vertex_colors = colors
	_circle_poly.polygons = polys
	add_child(_circle_poly)

func _on_body_entered(body):
	if not _victims.has(body):
		_victims.append(body)

func _on_body_exited(body):
	if _victims.has(body):
		_victims.erase(body)

# EnvironmentalRemediationMech.gd's cleanup aura calls this instead of a
# direct queue_free() - reuses the existing fade-out path (_process's
# alpha tween over the last 40% of _duration) so a cleaned puddle visibly
# fizzles out over a fraction of a second instead of instantly popping.
func remediate():
	_duration = min(_duration, _life_timer + 0.3)

func _process(delta):
	_life_timer += delta
	_tick_timer += delta
	
	# Fade out visual - stay fully opaque for the first 60% of lifetime,
	# then fade over the remaining 40% so puddles are clearly visible.
	if _duration > 0:
		var fade_start = _duration * 0.6
		var alpha = 1.0
		if _life_timer > fade_start:
			alpha = 1.0 - ((_life_timer - fade_start) / (_duration - fade_start))
		if alpha < 0: alpha = 0
		_circle_poly.modulate.a = alpha
	
	if _tick_timer >= TICK_RATE:
		_tick_timer -= TICK_RATE
		_apply_tick()
		
	if _life_timer >= _duration:
		queue_free()

func _apply_tick():
	# apply_damage(amount, element: String, source: Node, ...) - this used
	# to pass the raw _synergies Dictionary as the element arg and
	# global_position (a Vector2) as the source arg, a straight type
	# mismatch on both ("Cannot convert argument 2 from Dictionary to
	# String") that fired on every single tick. _dominant_element is
	# resolved once in setup(); source is null (a lingering DoT puddle
	# doesn't have a single clean "shooter" to attribute a tick to, and
	# null is apply_damage's own default for that param).
	for v in _victims:
		if is_instance_valid(v) and v.has_method("apply_damage") and not v.get("is_dead"):
			v.apply_damage(_base_damage, _dominant_element, null)
