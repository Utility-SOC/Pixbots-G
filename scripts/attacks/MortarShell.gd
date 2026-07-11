extends Node2D

# Remote-payload delivery (fourth-review ruling / Mythic Weapon Mount
# "Mortar" pattern): a lobbed shell that travels to the AIM POINT rather
# than along a firing line - a ground telegraph ring marks the impact zone
# for its whole flight (counterplay: you can see it coming and move), then
# the shell lands and applies elemental AoE. Self-contained: draws its own
# telegraph, shell dot, arc, and impact flash; no physics body (the payload
# is positional, not collisional).

var start_pos: Vector2
var target_pos: Vector2
var flight_time: float = 1.0
var damage: float = 0.0
var synergies: Dictionary = {}
var fired_by_player: bool = true
var source_mech: Node = null

var _elapsed: float = 0.0
var _landed: bool = false
var _impact_elapsed: float = 0.0

const AOE_RADIUS = 95.0
const ARC_HEIGHT = 70.0
const IMPACT_FLASH_TIME = 0.28

func setup(p_start: Vector2, p_target: Vector2, p_flight_time: float, p_damage: float, p_synergies: Dictionary, p_by_player: bool, p_source: Node):
	start_pos = p_start
	target_pos = p_target
	flight_time = max(0.15, p_flight_time)
	damage = p_damage
	synergies = p_synergies
	fired_by_player = p_by_player
	source_mech = p_source
	global_position = p_target # node sits at the impact point; shell is drawn offset

func _process(delta: float):
	if _landed:
		_impact_elapsed += delta
		if _impact_elapsed >= IMPACT_FLASH_TIME:
			queue_free()
		queue_redraw()
		return
	_elapsed += delta
	if _elapsed >= flight_time:
		_landed = true
		_detonate()
	queue_redraw()

func _detonate():
	var dominant = EnergyPacket.SynergyType.RAW
	var best = 0.0
	for k in synergies:
		if synergies[k] > best:
			best = synergies[k]
			dominant = k
	var element = EnergyPacket.element_name(dominant)

	# Positional AoE against the OPPOSING side only.
	var victims: Array = []
	if fired_by_player:
		victims = EntityCache.get_group("enemy")
	else:
		victims = EntityCache.get_group("player")
	for v in victims:
		if not is_instance_valid(v) or v.get("is_dead"):
			continue
		var dist = v.global_position.distance_to(target_pos)
		if dist > AOE_RADIUS:
			continue
		# Full damage at center, 50% at the rim.
		var falloff = 1.0 - 0.5 * (dist / AOE_RADIUS)
		if v.has_method("apply_damage"):
			var src = source_mech if (source_mech and is_instance_valid(source_mech)) else null
			v.apply_damage(damage * falloff, element, src)
		if v.has_method("apply_status"):
			if element == "FIRE":
				v.apply_status("burning", 2.5)
			elif element == "ICE":
				v.apply_status("frozen", 2.0)

func _draw():
	if _landed:
		# Impact flash: expanding filled ring.
		var t = _impact_elapsed / IMPACT_FLASH_TIME
		var color = EnergyPacket.get_color_blend(synergies)
		draw_circle(Vector2.ZERO, AOE_RADIUS * (0.5 + 0.5 * t), Color(color.r, color.g, color.b, 0.45 * (1.0 - t)))
		draw_arc(Vector2.ZERO, AOE_RADIUS, 0, TAU, 24, Color(color.r, color.g, color.b, 0.9 * (1.0 - t)), 3.0)
		return

	var t = _elapsed / flight_time
	# Ground telegraph at the impact point: tightening dashed ring.
	var warn = Color(1.0, 0.35, 0.2, 0.55) if not fired_by_player else Color(0.4, 0.8, 1.0, 0.45)
	draw_arc(Vector2.ZERO, AOE_RADIUS, 0, TAU, 24, warn, 2.0)
	draw_arc(Vector2.ZERO, AOE_RADIUS * (1.0 - t * 0.85), 0, TAU, 20, Color(warn.r, warn.g, warn.b, 0.8), 2.0)

	# The shell itself: straight-line lerp with a fake parabolic height,
	# drawn relative to this node (which sits at the target).
	var flat = start_pos.lerp(target_pos, t) - target_pos
	var height = -sin(t * PI) * ARC_HEIGHT
	var shell_pos = flat + Vector2(0, height)
	draw_circle(shell_pos, 5.0, Color(0.2, 0.21, 0.24))
	draw_circle(shell_pos + Vector2(-1.5, -1.5), 2.0, Color(0.55, 0.58, 0.64))
