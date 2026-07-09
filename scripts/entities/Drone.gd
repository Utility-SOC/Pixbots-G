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

const FOLLOW_DISTANCE = 90.0
const FOLLOW_LERP_SPEED = 6.0
const TARGET_SEARCH_RADIUS = 480.0
const TARGET_RESCAN_INTERVAL = 0.35

var _target_rescan_timer: float = 0.0
var _current_target: Node2D = null
var _orbit_angle: float = 0.0

# Must be called (by whoever instantiates this, e.g. Main.gd) before
# add_child(), same pattern as combat_role/base_rarity/spawn_profile on
# regular Mech instances - _ready() reads these to build the drone's body.
func setup(p_owner: Node2D, p_loadout: ComponentEquipment, p_rarity: int):
	owner_mech = p_owner
	drone_loadout_source = p_loadout
	drone_rarity = p_rarity
	_orbit_angle = randf() * TAU

func _ready():
	is_player = true # see file header comment - damage-target semantics only
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

	# Same layer as the player so every existing "hits the player" collision
	# mask on enemy weapons also hits the drone with zero extra plumbing -
	# genuinely destructible without the drone joining any group that would
	# make game systems mistake it for the actual player.
	collision_layer = 8
	collision_mask = 1 | 2 | 4 # Env, Water, Enemy

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

	# Lazy trailing orbit around the owner rather than a rigid fixed offset -
	# reads as "a pet keeping pace," not a bolted-on turret.
	_orbit_angle += delta * 1.2
	var desired = owner_mech.global_position + Vector2(cos(_orbit_angle), sin(_orbit_angle) * 0.6) * FOLLOW_DISTANCE
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

# `drone_loadout_source` is the DroneBayTile's own persistent data (the
# player's saved drone build), not something this disposable node owns -
# equip_component() reparented it onto us via add_child() (same as any
# body-slot component on a real Mech). Without detaching it first, freeing
# this node (on death via die(), OR a plain despawn like Main._despawn_drone
# on returning to the Garage) would cascade-free it right along with us,
# corrupting the saved loadout so the next respawn/deploy has nothing to
# re-equip. _exit_tree() fires for every removal path uniformly, so this is
# the one place that needs to know about the hazard rather than every
# caller that might ever free this node.
func _exit_tree():
	if drone_loadout_source and is_instance_valid(drone_loadout_source) and drone_loadout_source.get_parent() == self:
		remove_child(drone_loadout_source)

func _find_nearest_enemy() -> Node2D:
	var best: Node2D = null
	var best_dist = TARGET_SEARCH_RADIUS
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or e.get("is_dead"):
			continue
		var d = global_position.distance_to(e.global_position)
		if d < best_dist:
			best_dist = d
			best = e
	return best

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
