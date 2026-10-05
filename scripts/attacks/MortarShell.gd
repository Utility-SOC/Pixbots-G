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
# "Nuke tier" (user ruling, 2026-08-11): 0.0 for a normal missile, ramping
# 0->1 as MissileRackTile._nuke_scale() computes from frame_multiplier/
# per-frame energy - see that function's own comment for the exact
# threshold (>32 frames at 600000+ energy/frame) and ramp (1.0 at the
# frame-multiplier ladder's own 256 ceiling). Drives _wipe_terrain()'s
# radius and ElementalPuddle's "bombed out" color fade, not just a bigger
# explosion number.
var nuke_scale: float = 0.0

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
var _ratios: Dictionary = {}
var _aoe_bonus: float = 0.0
var _is_sword: bool = false
const SWORD_KINETIC_MIN = 0.5
const SWORD_EXPLOSION_MAX = 0.25
const SWORD_RADIUS = 32.0
const SWORD_DIRECT_BONUS = 0.8 # direct-hit damage x (1 + this * kinetic ratio)
# Hunter-mode salvos scatter shells around the aim point; a sword is precision ordnance and keeps
# only this share of that scatter (see MissileRackTile._fire_hunter_salvo).
const SWORD_SCATTER_SHARE = 0.15
# Visual: an 8-pointed asterisk - each blade a little thick at the centre, then a quick taper to a
# spike (one concave star polygon = one draw call). Its size follows the damage in the missile.
const SWORD_STAR_POINTS = 8
const SWORD_STAR_INNER = 0.22 # inner/outer radius ratio: blade thickness at the centre
const SWORD_LEN_BASE = 15.0
const SWORD_LEN_MIN_SCALE = 0.8
const SWORD_LEN_MAX_SCALE = 3.5
const CHAIN_LIGHTNING_MIN = 0.15
const CHAIN_RANGE = 260.0
const CHAIN_DECAY = 0.7
var equal_split_all_victims: bool = false
# See _detonate_equal_split's own comment on the fanout cap this gates.
const MAX_FULL_PIPELINE_VICTIMS_PER_SHELL = 12

func setup(p_start: Vector2, p_target: Vector2, p_flight_time: float, p_damage: float, p_synergies: Dictionary, p_by_player: bool, p_source: Node, p_aoe_bonus: float = 0.0, p_radius_mult: float = 1.0, p_equal_split: bool = false, p_frame_multiplier: int = 1, p_nuke_scale: float = 0.0):
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
	nuke_scale = p_nuke_scale
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
	_ensure_textures()
	_ratios = ratios
	_aoe_bonus = p_aoe_bonus
	var r_exp = ratios.get(EnergyPacket.SynergyType.EXPLOSION, 0.0)
	var r_kin = ratios.get(EnergyPacket.SynergyType.KINETIC, 0.0)
	# Composition decides what kind of missile this is (no named recipes): kinetic-dominant with
	# little explosive = a "sword" (tiny footprint, no splash, no puddle, a much harder direct hit);
	# otherwise the blast radius follows the explosive damage carried.
	_is_sword = r_kin >= SWORD_KINETIC_MIN and r_exp < SWORD_EXPLOSION_MAX
	if _is_sword:
		effective_radius = SWORD_RADIUS
	else:
		effective_radius = max(40.0, Projectile.explosion_radius_for(ratios, p_aoe_bonus, damage) * radius_mult) * fm_scale

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
			if not _is_sword: # a sword leaves no puddle
				_spawn_puddle()
			_deploy_poison_turret()
			_wipe_terrain()
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
		var fire_ratio = _ratios.get(EnergyPacket.SynergyType.FIRE, 0.0)
		if fire_ratio >= Puddle.BURNING_GROUND_THRESHOLD:
			# Area denial: fire leaves burning ground that lasts and covers a little more.
			duration = min(60.0, duration + 9.0 * fire_ratio)
			puddle_radius *= 1.0 + 0.3 * fire_ratio
		
		# A puddle inherits the shell's damage as a DoT. nuke_scale (0.0 for
		# a normal missile) tells the puddle to fade toward a scorched-ash
		# "bombed out" look instead of staying the vibrant synergy color for
		# its whole life - see ElementalPuddle.setup()'s own comment.
		puddle.setup(puddle_radius, duration, damage, synergies, fired_by_player, nuke_scale, _ratios.get(EnergyPacket.SynergyType.FIRE, 0.0))
		puddle.global_position = target_pos
		world.add_child(puddle)

# "Wipe out terrain in the blast area" (user ruling, 2026-08-11, missiles
# past the nuke-tier threshold - see nuke_scale's own field comment). The
# map's own terrain grid is a static array baked once at generation time
# (MapGenerator.gd) - not something safe to mutate at runtime without also
# touching pathfinding/movement, so this reaches for the thing that's
# ALREADY a real, damageable, runtime-destructible presence on the map
# instead: every DestructibleObstacle (trees, rocks, ruins - see
# MapGenerator.gd's own "obstacle" group) inside the blast radius gets
# destroyed outright. Radius scales past the shell's own effective_radius
# with nuke_scale so a 256-frame charge visibly clears a wider area than
# its own blast ring, not just a bigger number on the same ring.
func _wipe_terrain():
	if nuke_scale <= 0.0 or not is_inside_tree():
		return
	var wipe_radius = effective_radius * (1.0 + 1.5 * nuke_scale)
	for obs in get_tree().get_nodes_in_group("obstacle"):
		if not is_instance_valid(obs) or not obs.has_method("apply_damage"):
			continue
		if obs.global_position.distance_to(target_pos) <= wipe_radius:
			obs.apply_damage(999999.0, "RAW", null, false, source_label)

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
		proj.damage = damage * ((1.0 + SWORD_DIRECT_BONUS * _ratios.get(EnergyPacket.SynergyType.KINETIC, 0.0)) if _is_sword else 1.0)
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
			proj.queue_free() # chain lightning is handled explicitly below (_chain_lightning)

	if _ratios.get(EnergyPacket.SynergyType.LIGHTNING, 0.0) >= CHAIN_LIGHTNING_MIN:
		_chain_lightning(direct_target, src)

	# Splash ring: falloff damage only - elemental spread (arcs, explosion
	# radius, residues) already came from the direct hit above.
	var element = EnergyPacket.element_name(_dominant_synergy())
	for v in (splash if not _is_sword else []):
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

# Real bug, found 2026-08-11 (user report: "missiles are still pretty
# white"). Real Projectile.gd/ProjectileBatchPool deliberately never
# blend a shot's main visual color - see GarageTestRange.
# _fire_via_batch_pool's own matching comment: "get_color_blend() washes
# toward gray/white for anything with real RAW content blended in -
# exactly the 'large grey ox' a 600k-energy multi-element shot rendered
# as." _draw() below was still calling get_color_blend(synergies)
# directly, reproducing that exact bug a second time - any real,
# multi-element missile loadout (the normal case, not an edge case)
# washed toward white/grey instead of reading as its dominant element.
func _dominant_color() -> Color:
	var c = EnergyPacket.get_color_for_synergy(_dominant_synergy()) * 1.5
	c.a = 1.0
	return c

# Shared ring/disc textures: every shell draws from the same two textures, so all missiles' rings and
# dots merge into one batched draw (a shell in flight was 5 separate draws: 2 arcs + 3 circles).
static var _fx_atlas: ImageTexture = null # left half: ring, right half: disc - ONE texture so ring and dot quads merge
const TEX_SIZE = 64
const RING_THICKNESS = 0.045 # fraction of the diameter
const RING_REGION = Rect2(0, 0, 64, 64)
const DISC_REGION = Rect2(64, 0, 64, 64)

static func _ensure_textures() -> void:
	if _fx_atlas != null:
		return
	var img = Image.create(TEX_SIZE * 2, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var c = (TEX_SIZE - 1) / 2.0
	for y in range(TEX_SIZE):
		for x in range(TEX_SIZE):
			var d = Vector2(x - c, y - c).length() / (TEX_SIZE / 2.0)
			var disc_a = clamp((1.0 - d) * (TEX_SIZE / 2.0), 0.0, 1.0)
			var ring_a = clamp(1.0 - abs(d - (1.0 - RING_THICKNESS * 2.0)) / (RING_THICKNESS * 2.0), 0.0, 1.0)
			ring_a = clamp(ring_a * 1.6, 0.0, 1.0) * (1.0 if d <= 1.0 else 0.0)
			img.set_pixel(x, y, Color(1, 1, 1, ring_a))
			img.set_pixel(TEX_SIZE + x, y, Color(1, 1, 1, disc_a))
	_fx_atlas = ImageTexture.create_from_image(img)

func _quad_disc(center: Vector2, radius: float, col: Color) -> void:
	draw_texture_rect_region(_fx_atlas, Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), DISC_REGION, col)

func _quad_ring(center: Vector2, radius: float, col: Color) -> void:
	draw_texture_rect_region(_fx_atlas, Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), RING_REGION, col)

# Blade length (px) of this sword's star: grows with the damage it carries (200 dmg = 1.0x).
func sword_length() -> float:
	return SWORD_LEN_BASE * clamp(pow(max(damage, 1.0) / 200.0, 0.3), SWORD_LEN_MIN_SCALE, SWORD_LEN_MAX_SCALE)

static func star_points(length: float, rot: float) -> PackedVector2Array:
	var pts = PackedVector2Array()
	var n = SWORD_STAR_POINTS
	for k in range(n * 2):
		var a = rot + PI * float(k) / float(n)
		var r = length if k % 2 == 0 else length * SWORD_STAR_INNER
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts

func _draw_sword_star(center: Vector2, length: float, rot: float, color: Color, alpha: float):
	draw_colored_polygon(star_points(length, rot).duplicate(), Color(color.r, color.g, color.b, 0.85 * alpha)) if center == Vector2.ZERO else _draw_star_at(center, length, rot, color, alpha)
	# bright core
	_quad_disc(center, max(2.0, length * 0.16), Color(1, 1, 1, alpha))

func _draw_star_at(center: Vector2, length: float, rot: float, color: Color, alpha: float):
	var pts = star_points(length, rot)
	for i in range(pts.size()):
		pts[i] += center
	draw_colored_polygon(pts, Color(color.r, color.g, color.b, 0.85 * alpha))

func _draw():
	if _landed and _is_sword and not _crashed_harmlessly:
		var ts = _impact_elapsed / IMPACT_FLASH_TIME
		var cs = _dominant_color()
		_draw_sword_star(Vector2.ZERO, sword_length() * (1.0 + 0.9 * ts), _elapsed * 4.0 + ts * 0.8, cs, 1.0 - ts)
		return
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
		var color = _dominant_color()
		_quad_disc(Vector2.ZERO, effective_radius * (0.5 + 0.5 * t), Color(color.r, color.g, color.b, 0.45 * (1.0 - t)))
		_quad_ring(Vector2.ZERO, effective_radius, Color(color.r, color.g, color.b, 0.9 * (1.0 - t)))
		return

	var t = _elapsed / flight_time
	# Ground telegraph at the impact point: tightening dashed ring.
	var warn = Color(1.0, 0.2, 0.2, 0.9) if not fired_by_player else Color(0.2, 1.0, 0.5, 0.9)
	_quad_ring(Vector2.ZERO, effective_radius, warn)
	_quad_ring(Vector2.ZERO, effective_radius * (1.0 - t * 0.85), Color(warn.r, warn.g, warn.b, 0.9))

	# The physical shell arcing through the air.
	var shell_pos = start_pos.lerp(target_pos, t)
	shell_pos.y -= sin(t * PI) * ARC_HEIGHT
	# Draw relative to the MortarShell's position (which is target_pos)
	shell_pos -= target_pos
	
	if _is_sword:
		# In flight: the spinning star itself, not a round shell.
		_draw_star_at(shell_pos, sword_length() * 0.7, _elapsed * 7.0, _dominant_color(), 1.0)
		_quad_disc(shell_pos, max(2.0, sword_length() * 0.12), Color(1, 1, 1, 0.95))
		return
	if equal_split_all_victims:
		var color = _dominant_color()
		_quad_disc(shell_pos, 12.0, color)
		_quad_disc(shell_pos, 6.0, Color(1, 1, 1, 0.9))
	else:
		var color = _dominant_color()
		_quad_disc(shell_pos, 10.0, color)
		_quad_disc(shell_pos, 5.0, Color(1, 1, 1, 0.9))
	_quad_disc(shell_pos + Vector2(-1.5, -1.5), 2.0, Color(0.55, 0.58, 0.64))


# Lightning missiles are a small impact that chains out: from the impact point to the nearest enemy
# in range, then onward from each to the next nearest, up to 2 + 6*lightning-ratio hops, each hop
# at CHAIN_DECAY of the last, paralysing what it touches.
static func is_sword_composition(syn: Dictionary) -> bool:
	var total = 0.0
	for k in syn:
		total += syn[k]
	if total <= 0.0:
		return false
	return syn.get(EnergyPacket.SynergyType.KINETIC, 0.0) / total >= SWORD_KINETIC_MIN \
		and syn.get(EnergyPacket.SynergyType.EXPLOSION, 0.0) / total < SWORD_EXPLOSION_MAX

func _chain_lightning(direct_target, src) -> void:
	var r_ltg = _ratios.get(EnergyPacket.SynergyType.LIGHTNING, 0.0)
	var hops = 2 + int(6.0 * r_ltg)
	var victims: Array = EntityCache.get_group("enemy") if fired_by_player else EntityCache.get_group("player")
	var hit: Array = []
	if direct_target != null and is_instance_valid(direct_target):
		hit.append(direct_target)
	var points: Array = [target_pos]
	var from_pos = target_pos
	var dmg = damage * r_ltg * 0.8
	for h in range(hops):
		var best = null
		var best_d = CHAIN_RANGE
		for v in victims:
			if not is_instance_valid(v) or v.get("is_dead") == true or hit.has(v):
				continue
			var d = v.global_position.distance_to(from_pos)
			if d < best_d:
				best_d = d
				best = v
		if best == null:
			break
		hit.append(best)
		points.append(best.global_position)
		if best.has_method("apply_damage"):
			best.apply_damage(dmg, "LIGHTNING", src, false, source_label)
		if is_instance_valid(best) and best.has_method("apply_status"):
			best.apply_status("paralyzed", 0.6)
		dmg *= CHAIN_DECAY
		from_pos = best.global_position
	if points.size() > 1 and get_parent():
		var arc = load("res://scripts/visuals/LightningChainVisual.gd").new()
		get_parent().add_child(arc)
		arc.setup(points, EnergyPacket.get_color_for_synergy(EnergyPacket.SynergyType.LIGHTNING) * 1.5)

# Poison missiles turn the impact into a turret: the same emitter the poison mines leave behind
# (flame from fire, sub-shots from kinetic/pierce/poison), so poison -> turret is the same rule
# everywhere. A pure-poison missile gets a poison-bolt turret.
func _deploy_poison_turret() -> void:
	if _is_sword or _ratios.get(EnergyPacket.SynergyType.POISON, 0.0) < Projectile.MINE_POISON_THRESHOLD:
		return
	var emitter_script = load("res://scripts/attacks/MineEmitter.gd")
	if not emitter_script.can_deploy() or not get_parent():
		return
	var profile = Projectile.mine_profile(_ratios)
	var field_share = float(profile["field_share"])
	var volley_share = float(profile["volley_share"])
	if field_share + volley_share <= 0.0:
		volley_share = 0.6 # no sustain/volley element mixed in: a poison-bolt turret
	var total_damage = damage * 1.5
	var sub_ratios = Projectile._sub_shot_ratios(_ratios)
	var dom = Projectile._dominant_of(sub_ratios)
	var col = EnergyPacket.get_color_for_synergy(dom) * 1.5
	col.a = 1.0
	var pool = _emitter_pool()
	var emitter = emitter_script.new()
	emitter.global_position = target_pos
	get_parent().add_child(emitter)
	var src = source_mech if (source_mech and is_instance_valid(source_mech)) else null
	emitter.setup(Projectile.FLAME_TURRET_SECONDS, total_damage * field_share, Projectile.FLAME_TURRET_RANGE * (1.0 + 0.5 * _aoe_bonus), total_damage * volley_share, Projectile.SUB_SHOT_RANGE, 4 if fired_by_player else 8, pool, {
		"color": col, "dominant": dom, "ratios": sub_ratios, "by_player": fired_by_player, "source": src,
	})

func _emitter_pool() -> Node:
	if ProjectileManager.should_use_batch_pool():
		return ProjectileManager.live_batch_pool
	if not is_instance_valid(Projectile._fallback_pool) and get_parent():
		Projectile._fallback_pool = load("res://scripts/entities/ProjectileBatchPool.gd").new()
		get_parent().add_child(Projectile._fallback_pool)
	if is_instance_valid(Projectile._fallback_pool):
		Projectile._fallback_pool.sync_targets_from_groups()
	return Projectile._fallback_pool
