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
# Snapshot of Mech.resolve_attacker_label(source_mech) taken in setup(),
# while the shooter is still guaranteed alive - mortars have a flight-time
# delay before impact, making the shooter dying mid-flight even more likely
# than for a direct-fire Projectile. See Projectile.gd's source_label
# comment for the full story.
var source_label: String = ""

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
	source_label = Mech.resolve_attacker_label(p_source)
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

# Design ruling: the payload does exactly what DIRECT FIRE of this packet
# would do on impact. Implemented literally - a real (movement-neutered)
# Projectile is spawned at the impact point and its actual _handle_hit
# pipeline is driven against the victim nearest the aim point, so chain
# lightning arcs, explosion AoE, vampiric lifesteal, biome combos, oil
# ignition, statuses, pierce rend - present and future - all fire from the
# landing zone with zero reimplementation. Other victims inside the ring
# take falloff splash (the element's own spread mechanics - arcs, blasts -
# already reach them the same way direct fire would).
func _detonate():
	var world = get_parent()

	# Feed the director's mortar counter-doctrine (cloaks/jammers answer
	# artillery) - player shots only; the AI countering itself is silly.
	if fired_by_player:
		var main = get_tree().current_scene if is_inside_tree() else null
		if main and "world" in main and main.world and main.world.has_node("SquadDirector"):
			main.world.get_node("SquadDirector").log_mortar_shot()
	var victims: Array = []
	if fired_by_player:
		victims = EntityCache.get_group("enemy")
	else:
		victims = EntityCache.get_group("player")

	var direct_target = null
	var direct_dist = AOE_RADIUS
	var splash: Array = []
	for v in victims:
		if not is_instance_valid(v) or v.get("is_dead"):
			continue
		var dist = v.global_position.distance_to(target_pos)
		if dist > AOE_RADIUS:
			continue
		if dist < direct_dist:
			if direct_target:
				splash.append(direct_target)
			direct_target = v
			direct_dist = dist
		else:
			splash.append(v)

	var src = source_mech if (source_mech and is_instance_valid(source_mech)) else null

	if direct_target and world:
		var proj = load("res://scripts/entities/Projectile.gd").new()
		proj.synergies = synergies.duplicate()
		proj.damage = damage
		proj.fired_by_player = fired_by_player
		proj.source_mech = src
		proj.source_label = source_label
		proj.direction = Vector2.DOWN # payload arrives from above
		proj.global_position = target_pos
		# Combat-correct collision MASK even though the projectile never
		# flies: the chain-lightning hop query derives its target layer
		# from it (mask & 4 -> hunt enemies). Monitoring stays off, so the
		# mask never causes contact hits.
		proj.collision_mask = (4 | 1) if fired_by_player else (8 | 1)
		world.add_child(proj) # _ready computes ratios/stats
		ProjectileManager.unregister(proj)
		proj.set_physics_process(false)
		proj.monitoring = false
		proj.monitorable = false
		proj._handle_hit(direct_target) # the entire direct-fire impact pipeline
		if not proj.is_queued_for_deletion():
			if proj._lightning_hops_left > 0 or proj.ratios.get(EnergyPacket.SynergyType.LIGHTNING, 0.0) > 0.05:
				# Lightning payload survives the impact by design (blink
				# re-targeting) - RE-ARM it as a live projectile so it
				# teleport-hops onward from the crater, exactly like
				# direct-fire lightning would.
				proj.set_physics_process(true)
				proj.monitoring = true
				proj.monitorable = true
				ProjectileManager.register(proj)
			else:
				proj.queue_free()

	# Splash ring: falloff damage only - elemental spread (arcs, explosion
	# radius, residues) already came from the direct hit above.
	var element = EnergyPacket.element_name(_dominant_synergy())
	for v in splash:
		if not is_instance_valid(v) or not v.has_method("apply_damage"):
			continue
		var falloff = 1.0 - 0.5 * (v.global_position.distance_to(target_pos) / AOE_RADIUS)
		v.apply_damage(damage * 0.6 * falloff, element, src, false, source_label)

func _dominant_synergy() -> int:
	var dominant = EnergyPacket.SynergyType.RAW
	var best = 0.0
	for k in synergies:
		if synergies[k] > best:
			best = synergies[k]
			dominant = k
	return dominant

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
