class_name JumpjetResidue
extends Node2D

var lifetime: float = 3.0
var timer: float = 0.0
var damage_per_sec: float = 10.0
var synergies: Dictionary = {}
# Was a hardcoded 25.0 - now settable so a caller spawning many of these
# (LanceBeam's residue chain) can shrink the COUNT under saturation by
# growing each individual zone's radius instead, keeping total coverage
# roughly constant. Every other caller (PlayerController's jumpjet trail,
# BossBrain's Incinerator drop) never sets this, so they're unaffected.
var radius: float = 25.0
# Replaces collision_mask (4=Enemies/8=Player under the old Area2D) - true
# damages the "enemy" group (player-sourced residue, the default - matches
# the old collision_mask=4 default), false damages "player" (enemy-sourced,
# e.g. BossBrain's Incinerator drop). See _physics_process's EntityCache
# scan below for why this replaced a real physics body entirely.
var by_player: bool = true

# Perf audit (2026-08-01): damage/overlap check was running unthrottled
# every physics tick (60Hz) - a real physics-server get_overlapping_bodies()
# round-trip per live zone per tick, same category of cost the broadphase/
# separation Rust ports eliminated elsewhere this session. Throttled to
# 10Hz (audit's own suggested 5-10Hz range) via the same elapsed-accumulator
# pattern used for status-effect/weapon-charge LOD throttling - damage_per_sec
# is scaled by the real accumulated elapsed time each tick, so total damage
# over the zone's lifetime is unchanged, only chunked into fewer/bigger hits.
#
# Perf audit #2 (2026-08-05): the 10Hz throttle above only cut the
# get_overlapping_bodies() CALL rate - this was still a real Area2D
# registered with the physics server every physics tick regardless of query
# rate (broadphase still has to track it), the same cost category
# OrbitingProjectile.gd was already converted away from on 2026-08-04.
# LanceBeam's residue chain is the volume driver - a single Lance shot can
# spawn dozens of these at once, each living up to 25s - and a live 3fps/
# 133ms wave-57 playtest report ("updated performance telemetry in a bad
# lag") with a long visible residue trail confirmed it's still a real cost
# even with the query throttle in place. Converted extends Area2D -> Node2D;
# damage now reads the same throttled EntityCache group snapshot every other
# hot-path scan in this codebase already uses (by_player selects "enemy" vs
# "player"), with a plain distance-to-radius check standing in for the old
# circle-overlap query - equivalent for this shape, no physics-server
# round-trip or broadphase registration at all.
const DAMAGE_TICK_INTERVAL = 0.1
var _damage_tick_elapsed: float = 0.0

# Optional - set by Mech._do_fire_pool (Incinerator boss ability) so the
# per-tick damage this zone deals gets credited to the spawning mech's
# dealt_damage signal (and therefore its boss fitness tracking). Null for
# the player's own jumpjet residue, which doesn't need this.
var source_mech: Node = null

var visual: Polygon2D
var particles: CPUParticles2D

func setup(_damage: float, _synergies: Dictionary):
	damage_per_sec = _damage
	synergies = _synergies.duplicate()
	
	var base_color = EnergyPacket.get_color_blend(synergies)
	
	if visual:
		visual.color = Color(base_color.r, base_color.g, base_color.b, 0.5)
	
	if particles:
		particles.color = Color(base_color.r, base_color.g, base_color.b, 0.8)

func _ready():
	visual = Polygon2D.new()
	var base_color = EnergyPacket.get_color_blend(synergies) if not synergies.is_empty() else Color.WHITE
	visual.color = Color(base_color.r, base_color.g, base_color.b, 0.5)
	var points = PackedVector2Array()
	for j in range(12):
		var angle = j * (PI / 6.0)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	visual.polygon = points
	add_child(visual)
	
	particles = CPUParticles2D.new()
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = radius * 0.8
	particles.direction = Vector2(0, -1)
	particles.spread = 20.0
	particles.initial_velocity_min = 10.0
	particles.initial_velocity_max = 30.0
	particles.gravity = Vector2(0, -50)
	particles.color = Color(base_color.r, base_color.g, base_color.b, 0.8)
	particles.amount = 15
	particles.lifetime = 0.5
	add_child(particles)

func _physics_process(delta: float):
	timer += delta
	if timer > lifetime:
		# Fade out
		visual.modulate.a -= delta * 2.0
		particles.emitting = false
		if visual.modulate.a <= 0:
			queue_free()
		return

	_damage_tick_elapsed += delta
	if _damage_tick_elapsed < DAMAGE_TICK_INTERVAL:
		return
	var elapsed = _damage_tick_elapsed
	_damage_tick_elapsed = 0.0

	var victims = EntityCache.get_group("enemy" if by_player else "player")
	for body in victims:
		if not is_instance_valid(body) or not body.has_method("apply_damage"):
			continue
		if global_position.distance_to(body.global_position) > radius:
			continue
		# Find dominant synergy for damage type - by magnitude, not by a
		# fixed FIRE>ICE>LIGHTNING presence check (a 99%-Lightning/
		# 1%-Fire blend was always reporting FIRE). Mirrors
		# MortarShell.gd's _dominant_synergy().
		var dominant_synergy = EnergyPacket.SynergyType.RAW
		var best_magnitude = 0.0
		for k in synergies:
			if synergies[k] > best_magnitude:
				best_magnitude = synergies[k]
				dominant_synergy = k
		var element = EnergyPacket.element_name(dominant_synergy)

		var dmg = damage_per_sec * elapsed
		body.apply_damage(dmg, element)
		if source_mech and is_instance_valid(source_mech) and source_mech.has_signal("dealt_damage"):
			source_mech.dealt_damage.emit(dmg)

		if body.has_method("apply_status"):
			if synergies.has(EnergyPacket.SynergyType.FIRE):
				body.apply_status("burning", 2.0)
			if synergies.has(EnergyPacket.SynergyType.ICE):
				body.apply_status("frozen", 2.0)
