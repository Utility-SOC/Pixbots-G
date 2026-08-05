# Was "extends Area2D" - a real per-orb physics body (CollisionShape2D,
# collision_layer/mask, area_entered/body_entered monitoring) registered
# with the physics server for every live orb, every frame. That's the exact
# per-projectile overhead the Rust Phase 3 cutover specifically eliminated
# from Projectile.gd (see that file's header/Status.md - Projectile now
# extends Node2D and reports swept movement to the batched
# ProjectileBroadphase instead of running its own Area2D). OrbitingProjectile
# was added after that cutover and never got the memo, quietly
# reintroducing the same class of cost - and since it's a wholly separate
# script from Projectile, none of that cost ever showed up in any of
# FpsCounter's per-sec breakdown lines (all of which read Projectile/
# ProjectileManager/HexTile counters specifically). A "more built mech"
# running multiple Orbiting Array volleys at once (2026-08-04 user report:
# 5fps/133ms at wave 6, only 6 live enemies) is exactly the scenario where
# several of these silently-expensive orbs stack up unnoticed.
#
# Fix: Node2D + throttled EntityCache group distance-checks (10Hz, same
# spirit as Projectile's HOMING_QUERY_INTERVAL/vortex-pull throttling -
# task #33) instead of continuous physics monitoring. Orb counts and
# EntityCache group sizes are both small, so a throttled O(orbs * group)
# scan is far cheaper than one live Area2D body per orb.
class_name OrbitingProjectile
extends Node2D

const LIFETIME = 14.0
# User report (2026-08-05): "the orbitals aren't worth it for all the cost in
# space and energy" - the same 3-hex/6-faces-@-10000 commitment as a Lance
# Mount, for orbs that in practice almost never actually hit anything. Root
# cause: 14px was the old CollisionShape2D's CircleShape2D radius, on an orb
# sweeping 75-130px from the mech - a victim needed near-pixel-perfect
# overlap with wherever the orb currently was on its orbit, not just "close
# to the mech." Widened so a target that gets near the mech has a real
# chance of catching the ring.
const CONTACT_RADIUS = 45.0
const CONTACT_CHECK_INTERVAL = 0.1
# Same lump-sum-to-DPS conversion LanceBeam.gd's residue chain already uses
# (dps = damage / (residue_lifetime * 0.3)) - _check_contact used to consume
# the orb on its FIRST touch, dealing the full `damage` value once then
# queue_free()-ing. Combined with the 14px radius above, that meant most
# orbs spent their whole 14s LIFETIME never registering a single hit. Now
# the orb survives contact and ticks instead - `damage` is treated as the
# total budget for CONTACT_DPS_WINDOW seconds of sustained contact, same
# "roughly one lump hit's worth over a reasonable engagement window" idea,
# just spread as real orbital-defense DPS instead of a one-shot mine.
const CONTACT_DPS_WINDOW = 2.0
const LIGHTNING_LASH_INTERVAL = 0.2 # was a raw physics shape query every single frame

var source_mech: Node = null
var damage: float = 0.0
var synergies: Dictionary = {}
var by_player: bool = true
var orbit_time: float = 0.0
var base_angle: float = 0.0
var is_active: bool = true
var dominant_synergy: int = EnergyPacket.SynergyType.RAW

var _trail_timer: float = 0.0
var _contact_timer: float = 0.0
var _lash_timer: float = 0.0

func setup(p_source: Node, p_damage: float, p_synergies: Dictionary, p_by_player: bool, p_angle_offset: float = 0.0):
	source_mech = p_source
	damage = p_damage
	synergies = p_synergies
	by_player = p_by_player
	base_angle = p_angle_offset

	# get_dominant_synergy() is an instance method (reads self.synergies);
	# this only ever holds a raw Dictionary, not an EnergyPacket - real bug,
	# found while investigating a perf report: this was previously calling
	# EnergyPacket.get_dominant_synergy(synergies) as if it were static,
	# which errors at runtime and left dominant_synergy stuck at its default
	# (RAW) - orbiting shots never actually got their real elemental orbit
	# pattern/color/lash behavior.
	dominant_synergy = EnergyPacket.dominant_synergy_of(synergies)

func _ready():
	# Deliberately NOT add_to_group("projectile") - MagnetSystem.gd's repel-
	# mode loop treats every member of that group as a real Projectile and
	# mutates fields (fired_by_player, collision_mask, direction) this class
	# doesn't have; joining that group would only accidentally no-op there
	# today (property-name mismatch: by_player vs fired_by_player) and could
	# silently break the moment either script changes its field names.
	# Randomized initial offset, same reason Projectile.gd randomizes
	# _homing_query_timer - staggers a whole simultaneous volley's worth of
	# orbs onto different ticks instead of every one of them re-scanning on
	# the exact same frame.
	_contact_timer = randf() * CONTACT_CHECK_INTERVAL
	_lash_timer = randf() * LIGHTNING_LASH_INTERVAL

	var timer = get_tree().create_timer(LIFETIME)
	timer.timeout.connect(queue_free)

func _process(delta: float):
	if not is_instance_valid(source_mech):
		queue_free()
		return

	orbit_time += delta
	_update_orbital_position(delta)
	_handle_synergy_effects(delta)
	_check_contact(delta)
	queue_redraw()

func _update_orbital_position(delta: float):
	var center = source_mech.global_position
	var target_pos = center
	
	match dominant_synergy:
		EnergyPacket.SynergyType.KINETIC, EnergyPacket.SynergyType.PIERCE:
			# Fast, tight elliptical orbit spinning rapidly around the Mech
			var speed = 4.5
			var angle = base_angle + orbit_time * speed
			var rx = 120.0 + 35.0 * cos(orbit_time * 2.5)
			var ry = 75.0 + 25.0 * sin(orbit_time * 2.5)
			target_pos = center + Vector2(cos(angle) * rx, sin(angle) * ry)
			
		EnergyPacket.SynergyType.VORTEX:
			# Eccentric Bezier-blob orbit with fluid, organic distance shifts
			var speed = 2.2
			var angle = base_angle + orbit_time * speed
			var r = 110.0 + 45.0 * sin(orbit_time * 1.8) + 25.0 * cos(orbit_time * 3.3)
			target_pos = center + Vector2(cos(angle), sin(angle)) * r
			
		EnergyPacket.SynergyType.LIGHTNING:
			# Orbiting bolt stays close (75px). Lashes out when enemy nearby.
			var speed = 3.0
			var angle = base_angle + orbit_time * speed
			target_pos = center + Vector2(cos(angle), sin(angle)) * 75.0
			_lash_timer -= delta
			if _lash_timer <= 0.0:
				_lash_timer = LIGHTNING_LASH_INTERVAL
				_check_lightning_lash()

		EnergyPacket.SynergyType.POISON:
			# Sweeping orbit leaving decaying poison trails behind it
			var speed = 2.0
			var angle = base_angle + orbit_time * speed
			var r = 130.0 + 20.0 * sin(orbit_time * 1.4)
			target_pos = center + Vector2(cos(angle), sin(angle)) * r
			
		_:
			# Default smooth circular/elliptical orbital defense
			var speed = 2.8
			var angle = base_angle + orbit_time * speed
			target_pos = center + Vector2(cos(angle), sin(angle)) * 105.0
			
	global_position = target_pos

func _handle_synergy_effects(delta: float):
	if dominant_synergy == EnergyPacket.SynergyType.POISON:
		_trail_timer += delta
		if _trail_timer >= 0.2:
			_trail_timer = 0.0
			_spawn_poison_pool()

func _spawn_poison_pool():
	var world = get_parent()
	if not world: return
	var OilSlickScript = load("res://scripts/hazards/OilSlickHazard.gd")
	if OilSlickScript:
		var pool = OilSlickScript.new()
		pool.global_position = global_position
		world.add_child(pool)

# Was a raw PhysicsShapeQueryParameters2D.intersect_shape() call every
# single frame this orb was Lightning-dominant - now throttled
# (LIGHTNING_LASH_INTERVAL) and reads the same EntityCache-cached group
# snapshot every other per-frame enemy/player scan in this codebase already
# uses, instead of hitting the physics server directly.
func _check_lightning_lash():
	var victims = EntityCache.get_group("enemy" if by_player else "player")
	for v in victims:
		if not is_instance_valid(v) or v == source_mech:
			continue
		if v.has_method("apply_damage") and global_position.distance_to(v.global_position) <= 220.0:
			v.apply_damage(damage * 0.4, "LIGHTNING", source_mech)

# Replaces the old body_entered/area_entered Area2D signals (contact damage
# only - the interception half, "destroy incoming enemy projectiles" via
# area_entered, had already been silent dead code since Projectile.gd
# stopped being an Area2D in the Rust Phase 3 cutover: an Area2D's
# area_entered only ever fires for other Area2D shapes, and Projectile is a
# plain Node2D now, so it could never have fired here in current gameplay.
# Not reimplemented against the new throttled-scan approach - restoring
# gameplay behavior that's been off for a while is a separate,
# player-visible decision, not a side effect of a performance fix).
func _check_contact(delta: float):
	_contact_timer -= delta
	if _contact_timer > 0.0:
		return
	_contact_timer = CONTACT_CHECK_INTERVAL
	var victims = EntityCache.get_group("enemy" if by_player else "player")
	for v in victims:
		if v == source_mech or not is_instance_valid(v) or not v.has_method("apply_damage"):
			continue
		if global_position.distance_to(v.global_position) <= CONTACT_RADIUS:
			# synergy_name() doesn't exist on EnergyPacket (element_name()
			# does) - another pre-existing bug in this file, same class of
			# mistake as the dominant_synergy_of() one above. Since this ran
			# inside the old body_entered signal handler, a bad static call
			# here would have errored out before apply_damage() ever ran -
			# orb contact damage has likely never actually landed.
			#
			# No more queue_free() on hit, and no more per-tick `damage` -
			# see CONTACT_DPS_WINDOW's own comment above. A one-shot 14px
			# contact mine essentially never triggered in real play; this
			# orb now keeps orbiting and ticking real DPS to anything that
			# stays within CONTACT_RADIUS for its whole LIFETIME instead.
			v.apply_damage(damage * (CONTACT_CHECK_INTERVAL / CONTACT_DPS_WINDOW), EnergyPacket.element_name(dominant_synergy), source_mech)

func _draw():
	var color = EnergyPacket.get_color_blend(synergies) if not synergies.is_empty() else Color(0.2, 0.8, 1.0)
	draw_circle(Vector2.ZERO, 14.0, Color(color.r, color.g, color.b, 0.4))
	draw_circle(Vector2.ZERO, 9.0, Color(color.r, color.g, color.b, 0.85))
	draw_circle(Vector2.ZERO, 4.0, Color(1.0, 1.0, 1.0, 0.95))
