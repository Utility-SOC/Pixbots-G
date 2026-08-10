class_name MortarShell
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
var frame_multiplier: int = 1

var _elapsed: float = 0.0
var _landed: bool = false
var _impact_elapsed: float = 0.0
# Set instead of detonating when an "anti_missile_aura" member (see
# AntiMissileJammerMech.gd) covers the impact point at landing time - the
# shell still runs its normal landed/impact-flash/release lifecycle, just
# with no damage and no puddle. See _is_neutralized_by_anti_missile_aura().
var _crashed_harmlessly: bool = false

# Node-churn fix (play report: "missiles make big problems (13 missile
# launchers)") - a Missile Rack's Hunter salvo can put up to 5 shells in
# flight per rack per volley, and 13 stacked racks routinely overlap their
# independent charge cycles, so un-pooled shells were accumulating far
# faster than any single direct-fire weapon ever would. Same free-list
# pattern as Projectile.gd's _visual_node_pool (see that file's header
# comment) - acquire()/release() instead of .new()/queue_free(), reusing
# whole MortarShell instances rather than rebuilding one from scratch every
# shot. No request_ready() call needed on reacquire - this script has no
# _ready() to rerun; setup() below already reassigns every field a fresh
# instance would have, including the flight-state fields release() leaves
# mid-impact-flash.
const _POOL_MAX = 64
static var _shell_pool: Array = []

static func acquire() -> Node2D:
	if not _shell_pool.is_empty():
		return _shell_pool.pop_back()
	# load(path), not the bare global class name - see this file's other
	# callers' matching comment (HexTile._fire_mortar, MissileRackTile's
	# two fire functions) for why: referencing the class_name here caused
	# "Identifier not found: MortarShell" at this file's OWN compile time,
	# not just at external call sites.
	return load("res://scripts/attacks/MortarShell.gd").new()


func release():
	if is_inside_tree() and get_parent():
		get_parent().remove_child(self)
	if _shell_pool.size() < _POOL_MAX:
		_shell_pool.append(self)
	else:
		queue_free() # already at cap - let this one go rather than growing unbounded

# Effective blast radius for THIS shell, computed once in setup() from its
# own synergies (see Projectile.explosion_radius_for - shared formula, not
# duplicated) - replaces the old flat AOE_RADIUS=95.0 constant, which never
# reflected the packet's actual Explosion/Kinetic ratio and could silently
# disagree with what _detonate() -> Projectile._trigger_explosion() computes
# for the direct-hit target. Used for BOTH the flight telegraph/impact
# visuals (_draw()) and splash-victim classification (_detonate()), so what
# the player sees warned about during flight is what actually happens on
# impact - the whole point of the telegraph's "you can see it coming" design.
# Floored so a near-zero-Explosion mortar (rare, but PIERCE/LIGHTNING-heavy
# builds can still choose Mortar delivery) still reads as a real, visible
# impact rather than an invisible pinprick.
var effective_radius: float = 40.0
const ARC_HEIGHT = 70.0
const IMPACT_FLASH_TIME = 0.28

# Missile Rack AOE mode only (MissileRackTile.gd, Mythic mythic_mode == 1) -
# every other caller (the Mythic Weapon Mount Mortar pattern, Missile Rack's
# default Hunter mode) leaves both at their defaults and behaves exactly as
# before. radius_mult layers on top of the shared explosion_radius_for()
# formula rather than changing it (that formula is used by every Explosion
# splash in the game, not just mortars). equal_split_all_victims switches
# _detonate() from "one direct-pipeline hit + falloff splash" to "every
# struck target gets an equal share of the total damage, each still run
# through the real hit pipeline" - see _detonate_equal_split() below.
var radius_mult: float = 1.0
var equal_split_all_victims: bool = false
# See _detonate_equal_split's own comment on the fanout cap this gates.
const MAX_FULL_PIPELINE_VICTIMS_PER_SHELL = 12

func setup(p_start: Vector2, p_target: Vector2, p_flight_time: float, p_damage: float, p_synergies: Dictionary, p_by_player: bool, p_source: Node, p_aoe_bonus: float = 0.0, p_radius_mult: float = 1.0, p_equal_split: bool = false, p_frame_multiplier: int = 1):
	start_pos = p_start
	target_pos = p_target
	flight_time = max(0.15, p_flight_time)
	damage = p_damage
	synergies = p_synergies
	fired_by_player = p_by_player
	source_mech = p_source
	source_label = Mech.resolve_attacker_label(p_source)
	radius_mult = p_radius_mult
	equal_split_all_victims = p_equal_split
	frame_multiplier = p_frame_multiplier
	global_position = p_target # node sits at the impact point; shell is drawn offset

	# Reset flight state - required for pooled reuse (see acquire()/release()
	# above): a shell handed back by acquire() is, by construction, always
	# one that just finished its impact flash (_landed true, _impact_elapsed
	# past IMPACT_FLASH_TIME), so without this reset a reused shell would
	# immediately re-trigger release() on its very next _process() instead
	# of actually flying. Harmless no-op for a genuinely fresh instance,
	# whose fields all already start at these same defaults.
	_elapsed = 0.0
	_landed = false
	_impact_elapsed = 0.0
	_crashed_harmlessly = false

	# Point-defense target group (AntiMissileJammerMech.gd) - safe to call
	# unconditionally on every setup(), including pooled reacquires; Godot
	# re-registers a node's groups automatically on tree re-entry, and
	# add_to_group() itself is a no-op if already a member.
	add_to_group("mortar_shell")

	var total_mag = 0.0
	for k in synergies:
		total_mag += synergies[k]
	var ratios = {}
	if total_mag > 0.0:
		for k in synergies:
			ratios[k] = synergies[k] / total_mag
	var fm_scale = sqrt(max(1.0, float(frame_multiplier)))
	effective_radius = max(40.0, Projectile.explosion_radius_for(ratios, p_aoe_bonus) * radius_mult) * fm_scale

func _process(delta: float):
	if _landed:
		_impact_elapsed += delta
		if _impact_elapsed >= IMPACT_FLASH_TIME:
			release()
			return
		queue_redraw()
		return
	_elapsed += delta
	if _elapsed >= flight_time:
		_landed = true
		if _is_neutralized_by_anti_missile_aura():
			_crashed_harmlessly = true
		else:
			_detonate()
			_spawn_puddle()
	queue_redraw()

# Point-defense counter (AntiMissileJammerMech.gd, user request 2026-08-10):
# a shell landing within an active "anti_missile_aura" member's radius
# crashes harmlessly instead of detonating - no damage, no puddle. Mirrors
# the existing "pierce_immunity_aura" group-scan pattern (Mech._is_pierce_
# execution_exempt()). Checked against target_pos, not global_position -
# this node sits at the impact point for its whole flight (see the class
# header comment), so that's the same point AntiMissileJammerMech's own
# active in-flight scan is already defending. Only defends its own side:
# an aura mech only neutralizes shells fired by the OTHER side.
func _is_neutralized_by_anti_missile_aura() -> bool:
	if not is_inside_tree():
		return false
	for aura in get_tree().get_nodes_in_group("anti_missile_aura"):
		if not is_instance_valid(aura):
			continue
		if aura.get("is_player") == fired_by_player:
			continue # defends its own side only, not friendly fire
		if aura.global_position.distance_to(target_pos) <= aura.jammer_radius:
			return true
	return false

func _spawn_puddle():
	var world = get_parent()
	if not world:
		return
	var Puddle = load("res://scripts/attacks/ElementalPuddle.gd")
	if Puddle:
		var puddle = Puddle.new()
		# Puddle radius matches the missile's full blast radius - the area
		# that got hit should be visibly hazardous afterward.
		# Duration scales aggressively with frame multiplier: 3s base + 0.8s per extra frame, max 60s.
		# (e.g. 64x frame_multiplier -> ~53 second puddle)
		var duration = min(60.0, 3.0 + (frame_multiplier - 1) * 0.8)
		var puddle_radius = effective_radius
		
		# A puddle inherits the shell's damage as a DoT.
		puddle.setup(puddle_radius, duration, damage, synergies, fired_by_player)
		puddle.global_position = target_pos
		world.add_child(puddle)

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

	if equal_split_all_victims:
		_detonate_equal_split(victims, world)
		return

	var direct_target = null
	var direct_dist = effective_radius
	var splash: Array = []
	for v in victims:
		if not is_instance_valid(v) or v.get("is_dead"):
			continue
		var dist = v.global_position.distance_to(target_pos)
		if dist > effective_radius:
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
		world.add_child(proj) # _ready computes ratios/stats - also auto-registers it with ProjectileBroadphase unconditionally, harmless while set_physics_process(false) below means it never reports movement
		ProjectileManager.unregister(proj)
		proj.set_physics_process(false)
		proj._handle_hit(direct_target) # the entire direct-fire impact pipeline
		if not proj.is_queued_for_deletion():
			if proj._lightning_hops_left > 0 or proj.ratios.get(EnergyPacket.SynergyType.LIGHTNING, 0.0) > 0.05:
				# Lightning payload survives the impact by design (blink
				# re-targeting) - RE-ARM it as a live projectile so it
				# teleport-hops onward from the crater, exactly like
				# direct-fire lightning would. Already registered with
				# ProjectileBroadphase since _ready() - only flight-math
				# registration and physics processing need re-enabling here.
				proj.set_physics_process(true)
				ProjectileManager.register(proj)
			else:
				proj.queue_free()

	# Splash ring: falloff damage only - elemental spread (arcs, explosion
	# radius, residues) already came from the direct hit above.
	var element = EnergyPacket.element_name(_dominant_synergy())
	for v in splash:
		if not is_instance_valid(v) or not v.has_method("apply_damage"):
			continue
		var falloff = 1.0 - 0.5 * (v.global_position.distance_to(target_pos) / effective_radius)
		v.apply_damage(damage * 0.6 * falloff, element, src, false, source_label)

# AOE mode's detonation (Missile Rack Mythic mythic_mode == 1 only): every
# valid target within effective_radius gets an EQUAL SHARE of the total
# damage - "the totality of damage the missile would have done, spread
# equally over all targets struck," not the direct-hit/falloff-splash split
# every other MortarShell caller uses. Each victim still gets a real,
# independent Projectile._handle_hit() pass (not a plain apply_damage) so
# elemental statuses/procs land properly per target - the "aesthetic of the
# given synergies onboard" reading MORE strongly across a wide burst is
# exactly the point of this mode. Deliberately skips the direct-hit-only
# lightning re-arm special case in _detonate() above - chaining onward from
# an already-divided AOE burst isn't this mode's identity, that's Hunter
# mode's.
func _detonate_equal_split(victims: Array, world: Node) -> void:
	var struck: Array = []
	for v in victims:
		if not is_instance_valid(v) or v.get("is_dead"):
			continue
		if v.global_position.distance_to(target_pos) <= effective_radius:
			struck.append(v)

	if struck.is_empty() or not world:
		return

	var src = source_mech if (source_mech and is_instance_valid(source_mech)) else null
	var share = damage / float(struck.size())
	var ProjScript = load("res://scripts/entities/Projectile.gd")
	var element = EnergyPacket.element_name(_dominant_synergy())
	for i in range(struck.size()):
		var v = struck[i]
		# Fanout cap (play report: "missiles make big problems (13 missile
		# launchers)") - a wide AOE burst catching a big on-screen crowd
		# used to spin up one full, brand-new Projectile object PER victim
		# with no ceiling at all; with several Mythic racks stacked and all
		# in AOE mode, that's O(shells x victims) transient allocations in
		# a single frame. Every struck victim still gets the exact same
		# equal damage share either way - only the first
		# MAX_FULL_PIPELINE_VICTIMS_PER_SHELL (by no particular order,
		# EntityCache's own group order) get the full _handle_hit() pass
		# for proper elemental status/procs; the rest take a plain
		# apply_damage() call, same lightweight path the falloff-splash
		# ring above already uses.
		if i >= MAX_FULL_PIPELINE_VICTIMS_PER_SHELL:
			if is_instance_valid(v) and v.has_method("apply_damage"):
				v.apply_damage(share, element, src, false, source_label)
			continue
		var proj = ProjScript.new()
		proj.synergies = synergies.duplicate()
		proj.damage = share
		proj.fired_by_player = fired_by_player
		proj.source_mech = src
		proj.source_label = source_label
		proj.direction = Vector2.DOWN
		proj.global_position = target_pos
		proj.collision_mask = (4 | 1) if fired_by_player else (8 | 1)
		world.add_child(proj)
		ProjectileManager.unregister(proj)
		proj.set_physics_process(false)
		proj._handle_hit(v)
		if not proj.is_queued_for_deletion():
			proj.queue_free()

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
		if _crashed_harmlessly:
			# Neutralized by an anti-missile aura: a small fizzling puff
			# instead of the colorful impact flash - reads as "shot down /
			# crashed" rather than "detonated."
			var ct = _impact_elapsed / IMPACT_FLASH_TIME
			draw_circle(Vector2.ZERO, 12.0 * (1.0 - ct), Color(0.55, 0.55, 0.58, 0.6 * (1.0 - ct)))
			draw_arc(Vector2.ZERO, 16.0 * (0.5 + 0.5 * ct), 0, TAU, 12, Color(0.8, 0.8, 0.8, 0.5 * (1.0 - ct)), 2.0)
			return
		# Impact flash: expanding filled ring.
		var t = _impact_elapsed / IMPACT_FLASH_TIME
		var color = EnergyPacket.get_color_blend(synergies)
		draw_circle(Vector2.ZERO, effective_radius * (0.5 + 0.5 * t), Color(color.r, color.g, color.b, 0.45 * (1.0 - t)))
		draw_arc(Vector2.ZERO, effective_radius, 0, TAU, 24, Color(color.r, color.g, color.b, 0.9 * (1.0 - t)), 3.0)
		return

	var t = _elapsed / flight_time
	# Ground telegraph at the impact point: tightening dashed ring.
	var warn = Color(1.0, 0.2, 0.2, 0.9) if not fired_by_player else Color(0.2, 1.0, 0.5, 0.9)
	draw_arc(Vector2.ZERO, effective_radius, 0, TAU, 24, warn, 4.0)
	draw_arc(Vector2.ZERO, effective_radius * (1.0 - t * 0.85), 0, TAU, 20, Color(warn.r, warn.g, warn.b, 0.9), 4.0)

	# The physical shell arcing through the air.
	var shell_pos = start_pos.lerp(target_pos, t)
	shell_pos.y -= sin(t * PI) * ARC_HEIGHT
	# Draw relative to the MortarShell's position (which is target_pos)
	shell_pos -= target_pos
	
	if equal_split_all_victims:
		var color = EnergyPacket.get_color_blend(synergies)
		draw_circle(shell_pos, 12.0, color)
		draw_circle(shell_pos, 6.0, Color(1, 1, 1, 0.9))
	else:
		var color = EnergyPacket.get_color_blend(synergies)
		draw_circle(shell_pos, 10.0, color)
		draw_circle(shell_pos, 5.0, Color(1, 1, 1, 0.9))
	draw_circle(shell_pos + Vector2(-1.5, -1.5), 2.0, Color(0.55, 0.58, 0.64))
