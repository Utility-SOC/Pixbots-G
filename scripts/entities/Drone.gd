class_name Drone
extends Mech

# Companion pet spawned when the player has a Drone Bay installed in their
# backpack (see DroneBayTile.gd / ComponentEquipment.create_starter_drone).
# Extends Mech to reuse its entire hex-grid energy-routing/weapon-firing/
# damage pipeline for free (equip_component, _recalculate_grid, _shoot,
# apply_damage, take_damage-on-tiles, the Jumpjet-rarity move-speed hookup)
# but overrides the parts that assume "humanoid body belonging to either the
# player or an AI trying to reach the player":
#   _ready()            - equips ONLY the drone's own small body (no torso/
#                          arms/legs/head/backpack), distinct visual, own HP
#   _physics_process()   - follows its owner instead of pathing, picks the
#                          nearest enemy instead of the player as its target
#   die()                - no loot drop/corpse husk; just tells whoever's
#                          listening (Main.gd) so it can respawn after a
#                          cooldown, per Natalia's "destructible, respawns"
#
# `is_player = true` is a deliberate reuse of Projectile.gd's friendly-fire
# check (fired_by_player and col.is_player -> skip, not fired_by_player and
# not col.is_player -> skip): reading as "the player's side" is exactly what
# makes enemy shots land on the drone while the player's own shots never
# friendly-fire it, without the drone actually being the controlled unit
# (it never joins the "player" group, so nothing that looks up the singular
# player node - camera, extraction-marker direction, HUD - gets confused).

signal drone_died(rarity: int)

var owner_mech: Node2D = null
var drone_loadout_source: ComponentEquipment = null # the DroneBayTile's persistent data
var drone_rarity: int = HexTile.Rarity.COMMON
# Which procedural chassis silhouette DroneRenderer draws - see
# DroneBayTile.visual_class's field comment (chosen once and persisted on
# the bay tile, not re-rolled per spawn, so a drone keeps a stable look
# across deploys/respawns).
var drone_visual_class: int = 0

const FOLLOW_DISTANCE = 90.0
const FOLLOW_LERP_SPEED = 6.0
const TARGET_SEARCH_RADIUS = 800.0
const TARGET_RESCAN_INTERVAL = 0.35
# Sortie behavior (fix for "drone sits idle, never chases or shoots" - the
# old behavior ONLY orbited the owner at FOLLOW_DISTANCE, so in any fight
# happening beyond ~480px of the pet's orbit it never engaged at all): with
# a live target the drone flies out and orbits IT at attack range instead,
# but never strays farther than LEASH_DISTANCE from its owner - it's a pet
# on a leash, not an independent hunter, and losing the target (or the
# target leaving leash reach) snaps it back to the owner orbit.
const ENGAGE_ORBIT_DISTANCE = 180.0
# Playtest ("the drones are all in close rather than behaving as expected"):
# 420 predates central spawns, near-peer squads, and kinetic-range fights -
# engagements now routinely happen 800-1500px out, so a 420px leash clamped
# every sortie back to a huddle around the player while the actual battle
# stayed out of the pets' reach. The leash still exists (a pet, not an
# independent hunter - losing the target still snaps it home), it just now
# covers the ranges fights actually happen at.
const LEASH_DISTANCE = 1000.0

# Recon Plane (DroneRenderer.RECON_CLASS): a scout, not a brawler - much
# longer reach in both directions (spots/engages from farther out, roams
# farther from the owner while doing it), and idles in a slow figure-eight
# instead of a tight orbit when it has nothing to shoot at (Utility-SOC:
# "languidly figure eight over the map").
const RECON_TARGET_SEARCH_RADIUS = 1600.0
const RECON_ENGAGE_ORBIT_DISTANCE = 360.0
const RECON_LEASH_DISTANCE = 2000.0
const RECON_LOITER_RADIUS = 260.0
const RECON_LOITER_SPEED = 0.35 # slow - "languid," not a patrol sweep

func _get_target_search_radius() -> float:
	return RECON_TARGET_SEARCH_RADIUS if drone_visual_class == DroneRenderer.RECON_CLASS else TARGET_SEARCH_RADIUS

func _get_engage_orbit_distance() -> float:
	return RECON_ENGAGE_ORBIT_DISTANCE if drone_visual_class == DroneRenderer.RECON_CLASS else ENGAGE_ORBIT_DISTANCE

func _get_leash_distance() -> float:
	return RECON_LEASH_DISTANCE if drone_visual_class == DroneRenderer.RECON_CLASS else LEASH_DISTANCE

var _target_rescan_timer: float = 0.0
var _current_target: Node2D = null
var _orbit_angle: float = 0.0

# Chinook (DroneRenderer.CHINOOK_CLASS): support drone that carries and
# pulses a real Heal Beacon rather than a generic numeric "support tile
# bonus" stat (Utility-SOC: "a bonus to support tiles like the healing
# one, that pulses heals at regular interval to an area to allied
# forces"). Deliberately NOT routed through Mech._update_healer/
# _emit_heal_pulse - that pair is guarded `if ... or is_player: return` and
# only ever heals the "enemy" group, both wrong for a PLAYER-owned drone
# (is_player would be true, and "allied forces" for a player means the
# player/other drones, not the AI squad group). This is its own small,
# side-aware tick instead.
var _chinook_heal_timer: float = 0.0

# Must be called (by whoever instantiates this, e.g. Main.gd) before
# add_child(), same pattern as combat_role/base_rarity/spawn_profile on
# regular Mech instances - _ready() reads these to build the drone's body.
func setup(p_owner: Node2D, p_loadout: ComponentEquipment, p_rarity: int, p_visual_class: int = 0):
	owner_mech = p_owner
	drone_loadout_source = p_loadout
	drone_rarity = p_rarity
	drone_visual_class = p_visual_class
	_orbit_angle = randf() * TAU

func _ready():
	# Reads as "the owner's side," not always the player's - an enemy-owned
	# drone (Commander default, or a per-role chance on other roles - see
	# Mech._create_role_backpack) needs friendly-fire semantics flipped the
	# other way: the player's shots should hit it, its own squad's shouldn't.
	is_player = owner_mech and "is_player" in owner_mech and owner_mech.is_player
	combat_role = "drone"
	base_rarity = drone_rarity
	_target_rescan_timer = randf() * TARGET_RESCAN_INTERVAL # desync - see Mech.gd/Projectile.gd's matching fix

	if drone_loadout_source:
		equip_component(drone_loadout_source)
	else:
		equip_component(ComponentEquipment.create_starter_drone(drone_rarity))

	visual_seed = randi()

	var renderer = load("res://scripts/visuals/DroneRenderer.gd").new()
	renderer.name = "DroneRenderer"
	renderer.drone_ref = self
	add_child(renderer)
	_renderer = renderer
	renderer._rebuild_visuals()

	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 16.0
	collision.shape = shape
	add_child(collision)

	# Same layer as its owner's side so every existing "hits the player"/
	# "hits an enemy" collision mask on the OTHER side's weapons also hits
	# the drone with zero extra plumbing - genuinely destructible without
	# the drone joining the "player"/"enemy" GROUP, which would make other
	# game systems (wave-clear counting, squad AI coordination) mistake it
	# for a full mech they need to track.
	if is_player:
		collision_layer = 8 # Player layer
		collision_mask = 1 | 2 | 4 # Env, Water, Enemy - NO 32: drones fly over terrain obstacles
	else:
		collision_layer = 4 # Enemy layer
		collision_mask = 1 | 2 | 8 # Env, Water, Player - NO 32: drones fly over terrain obstacles

	# Projectile._on_body_entered deliberately skips any CharacterBody2D that
	# has apply_part_damage (see PartHitbox.gd's comment) - every regular
	# Mech relies on its per-part PartHitbox Area2D children (built by
	# MechRenderer) to actually catch hits instead. Drone doesn't use
	# MechRenderer (distinct visual - see DroneRenderer.gd) so without one of
	# these it would inherit that skip with NOTHING to catch the hit
	# instead - completely undamageable, contradicting "destructible,
	# respawns." One hitbox covering the whole small body is enough (no
	# per-limb granularity needed for something this size).
	var hitbox = load("res://scripts/entities/PartHitbox.gd").new()
	hitbox.name = "Hitbox"
	hitbox.mech = self
	hitbox.body_slot = HexTile.BodySlot.TORSO
	hitbox.collision_layer = collision_layer
	hitbox.collision_mask = 0 # it just receives hits
	var hitbox_shape = CollisionShape2D.new()
	var hitbox_circle = CircleShape2D.new()
	hitbox_circle.radius = 16.0
	hitbox_shape.shape = hitbox_circle
	hitbox.add_child(hitbox_shape)
	add_child(hitbox)

	max_hp = 40.0 + drone_rarity * 35.0
	hp = max_hp

	if drone_visual_class == DroneRenderer.CHINOOK_CLASS:
		_ensure_heal_beacon_for_chinook()

	is_grid_dirty = true
	_recalculate_grid()

# NOTE: Drone deliberately never calls Mech._physics_process/_execute_ai_tactics/
# update_status_effects (this override replaces all of it), so it never
# lazily constructs boss_brain/status_runner/player_controller (see Mech.gd's
# composed-object split) - they just stay null, which is inert and matches
# Drone's pre-existing behavior (it never ticked status effects before
# either). If drones ever need status-effect ticking, this _physics_process
# must call update_status_effects() itself.
func _physics_process(delta: float):
	current_jammer_debuff = 1.0
	if is_dead:
		return
	if not is_instance_valid(owner_mech):
		die()
		return

	#_update_heat(delta) # Thermal system commented out in Mech.gd - see there.
	_tick_weapon_charges(delta)

	# Lazy trailing orbit rather than a rigid fixed offset - reads as "a pet
	# keeping pace," not a bolted-on turret. Anchors on the current target
	# when it has one (sortie - see the constants block above), the owner
	# otherwise.
	_orbit_angle += delta * 1.2
	var desired: Vector2
	if is_instance_valid(_current_target):
		desired = _current_target.global_position + Vector2(cos(_orbit_angle), sin(_orbit_angle) * 0.6) * _get_engage_orbit_distance()
		var from_owner = desired - owner_mech.global_position
		var leash = _get_leash_distance()
		if from_owner.length() > leash:
			desired = owner_mech.global_position + from_owner.normalized() * leash
	elif drone_visual_class == DroneRenderer.RECON_CLASS:
		# Languid figure-eight (Lissajous) loiter around the owner instead
		# of the tight default orbit - Utility-SOC: "languidly figure eight
		# over the map." A slow x=sin(t), y=sin(2t) parametric curve traces
		# a real figure-8 shape rather than a simple circle.
		var t = _orbit_angle * (RECON_LOITER_SPEED / 1.2) # _orbit_angle already advances at 1.2/sec
		desired = owner_mech.global_position + Vector2(sin(t), sin(t * 2.0) * 0.6) * RECON_LOITER_RADIUS
	else:
		desired = owner_mech.global_position + Vector2(cos(_orbit_angle), sin(_orbit_angle) * 0.6) * FOLLOW_DISTANCE
	global_position = global_position.lerp(desired, clamp(FOLLOW_LERP_SPEED * delta, 0.0, 1.0))

	_target_rescan_timer -= delta
	if _target_rescan_timer <= 0.0:
		_target_rescan_timer = TARGET_RESCAN_INTERVAL
		_current_target = _find_nearest_enemy()

	if fire_cooldown > 0.0:
		fire_cooldown -= delta

	if is_instance_valid(_current_target):
		last_aim_position = _current_target.global_position
		if fire_cooldown <= 0.0:
			_shoot(last_aim_position, true)
			fire_cooldown = fire_rate

	if drone_visual_class == DroneRenderer.CHINOOK_CLASS:
		_update_chinook_heal(delta)

# `drone_loadout_source` is the DroneBayTile's own persistent data (the
# player's saved drone build), not something this disposable node owns -
# equip_component() reparented it onto us via add_child() (same as any
# body-slot component on a real Mech). Without detaching it first, freeing
# this node (on death via die(), OR a plain despawn like Main._despawn_all_drones
# on returning to the Garage) would cascade-free it right along with us,
# corrupting the saved loadout so the next respawn/deploy has nothing to
# re-equip. _exit_tree() fires for every removal path uniformly, so this is
# the one place that needs to know about the hazard rather than every
# caller that might ever free this node.
func _exit_tree():
	if drone_loadout_source and is_instance_valid(drone_loadout_source) and drone_loadout_source.get_parent() == self:
		remove_child(drone_loadout_source)

func _find_nearest_enemy() -> Node2D:
	var search_radius = _get_target_search_radius()
	if not is_player:
		# Enemy-owned drone: its "enemy" is specifically the player, matching
		# what every other enemy Mech's AI targets (see Mech._get_player_ref,
		# inherited from the base class this extends) - not the "enemy" group,
		# which from this drone's own side means its squadmates.
		var p = _get_player_ref()
		if p and is_instance_valid(p) and global_position.distance_to(p.global_position) <= search_radius:
			return p
		return null

	var best: Node2D = null
	var best_dist = search_radius
	for e in EntityCache.get_group("enemy"):
		if not is_instance_valid(e) or e.get("is_dead"):
			continue
		var d = global_position.distance_to(e.global_position)
		if d < best_dist:
			best_dist = d
			best = e
	return best

# Places a HealBeaconTile on the drone's own tiny grid at deploy time if
# its loadout doesn't already have one (a hand-customized loadout keeps
# whatever the player actually built) - and, unlike create_starter_drone's
# "first free hex anywhere in valid_hexes" placement for the pre-installed
# Jumpjet/Weapon Mount, places it DIRECTLY ADJACENT to the Core Reactor and
# force-activates that face. CoreTile.active_faces defaults to just [0]
# (see CoreTile.gd) - a tile placed further out in valid_hexes order has no
# guarantee the Core is actually routing energy toward it at all. That's an
# acceptable "might be a dud placement" risk for a bonus starter weapon
# mount, but not for a support tile whose entire job is "always healing" -
# so this guarantees single-hop delivery instead of trusting placement
# order to land somewhere reachable.
func _ensure_heal_beacon_for_chinook():
	var torso = components.get(HexTile.BodySlot.TORSO)
	if not torso:
		return
	for t in torso.hex_grid.get_all_tiles():
		if t.tile_type == "Heal Beacon":
			return

	var core_coord = HexCoord.new(0, 0)
	if not torso.hex_grid.has_tile(core_coord):
		return
	var core_tile = torso.hex_grid.get_tile(core_coord)

	for d in range(6):
		var n = core_coord.neighbor(d)
		if torso.hex_grid.has_tile(n):
			continue
		if not _hex_in_valid_set(torso, n):
			continue
		var beacon = load("res://scripts/tiles/HealBeaconTile.gd").new()
		beacon.rarity = drone_rarity
		beacon.body_slot = HexTile.BodySlot.TORSO
		torso.hex_grid.add_tile(n, beacon)
		if "active_faces" in core_tile and not core_tile.active_faces.has(d) and core_tile.has_method("toggle_face"):
			core_tile.toggle_face(d)
		return

func _hex_in_valid_set(comp, h: HexCoord) -> bool:
	for v in comp.valid_hexes:
		if v.q == h.q and v.r == h.r:
			return true
	return false

# has_healer/heal_pulse_power/radius/interval are populated generically by
# _recalculate_grid() (see Mech.gd) regardless of is_player - only
# HealBeaconSystem.tick()'s USE of them (see Mech._update_healer's thin
# wrapper) is player-gated (and hardcoded to heal the "enemy" AI group,
# wrong for a player-owned drone's "allied forces" - see this var's own
# comment above). Deliberately scoped to just
# owner_mech (the single most meaningful ally for a companion drone) rather
# than building a full squad/ally-group system nothing else in the game has
# yet - a real AoE pulse centered on whoever it's actually escorting, not a
# generic numeric buff.
func _update_chinook_heal(delta: float):
	if not has_healer:
		return
	_chinook_heal_timer -= delta
	if _chinook_heal_timer > 0.0:
		return
	_chinook_heal_timer = heal_pulse_interval

	if not is_instance_valid(owner_mech) or not ("hp" in owner_mech) or not ("max_hp" in owner_mech):
		return
	if global_position.distance_to(owner_mech.global_position) > heal_pulse_radius:
		return
	var healed = min(owner_mech.max_hp, owner_mech.hp + heal_pulse_power) - owner_mech.hp
	if healed > 0.0:
		owner_mech.hp += healed
		if owner_mech.has_method("_show_floating_text"):
			owner_mech._show_floating_text("+%d" % int(healed), Color(0.2, 0.9, 0.5))

# Overrides Mech.die() entirely (no super call): no loot drop, no corpse
# husk, no SquadDirector kill-telemetry - none of that applies to a
# player-side companion. Just cleans up and lets whoever's listening
# (Main.gd) know so it can respawn the drone after a cooldown.
func die():
	if is_dead or is_queued_for_deletion():
		return
	is_dead = true
	drone_died.emit(drone_rarity)
	queue_free()
