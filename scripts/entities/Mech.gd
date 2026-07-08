class_name Mech
extends CharacterBody2D

const CoreTile = preload("res://scripts/tiles/CoreTile.gd")
const ComponentEquipment = preload("res://scripts/core/ComponentEquipment.gd")
const ComponentLinkTile = preload("res://scripts/tiles/ComponentLinkTile.gd")
const JumpjetResidue = preload("res://scripts/attacks/JumpjetResidue.gd")
# Explicit preload rather than relying on the global class_name cache -
# SolverProfile is used below as a bare type hint (var spawn_profile:
# SolverProfile), which needs this to resolve reliably even if the editor's
# global script class cache hasn't been refreshed since the file was added.
const SolverProfile = preload("res://scripts/ai/SolverProfile.gd")
const BossProfile = preload("res://scripts/ai/BossProfile.gd")

# Cached lookups for two effectively-singleton nodes (the map and the
# player) - both are created once at game start and outlive every mech that
# queries them, so re-fetching via get_tree().get_nodes_in_group(...) from
# scratch every time (including from the unconditional per-physics-frame AI
# tactics path, run by every one of up to 80 enemies) was pure waste. These
# re-resolve automatically if the cached reference ever actually goes stale
# (freed/invalid), which in practice only happens around scene teardown.
var _cached_map_ref: Node = null
var _cached_player_ref: Node = null

func _get_map_ref() -> Node:
	if not is_instance_valid(_cached_map_ref):
		var maps = get_tree().get_nodes_in_group("map_generator")
		_cached_map_ref = maps[0] if maps.size() > 0 else null
	return _cached_map_ref

func _get_player_ref() -> Node:
	if not is_instance_valid(_cached_player_ref):
		var players = get_tree().get_nodes_in_group("player")
		_cached_player_ref = players[0] if players.size() > 0 else null
	return _cached_player_ref

var max_hp: float = 100.0
var hp: float = 100.0
var shield_hp: float = 0.0
var max_shield_hp: float = 0.0
var shield_synergies: Dictionary = {}
var dominant_shield_synergy: String = ""

var shield_recharge_delay: float = 3.0
var time_since_last_hit: float = 0.0
var shield_recharge_rate: float = 0.0
var has_shield_generator: bool = false

var current_move_speed: float = 200.0
var base_move_speed: float = 200.0

# Melee/mass physics pillar - total weight of every equipped hex tile (see
# HexTile.get_weight() and the per-tile overrides), recomputed in
# _recalculate_grid(). Drives the movement-speed penalty/bonus in
# update_status_effects() and the ramming damage formula in _process_ramming().
var total_mass: float = 0.0
var combat_role: String = "melee"

# Water-capable movement variant: normally ANY mech standing over water
# drowns unless it happens to have jumpjets equipped (see _check_drowning/
# _has_jumpjets) - a happy accident of loadout, not a real trait. Amphibious
# mechs (the "diver" role, see SquadDirector._spawn_bot_for_role) are never
# affected by the water check at all regardless of loadout, and get a
# genuine speed bonus while over water rather than just "not dying" - an
# actual water specialist, not merely water-immune.
var is_amphibious: bool = false
var _in_water: bool = false
const AMPHIBIOUS_WATER_SPEED_MULT = 1.3

var status_effects: Dictionary = {}
var stat_modifiers: Dictionary = {}
# Element of the most recent damaging hit - reported by die() as the
# player's kill method (see SquadDirector.log_player_kill).
var last_damage_element: String = "RAW"
# Rolling "how did I die" log - only meaningfully populated for is_player,
# but harmless/unused on enemy mechs. Each entry is one damaging hit in the
# seconds leading up to death: {"role", "name", "is_boss", "element",
# "amount", "time"}. Trimmed to a fixed lookback window in apply_damage() so
# it reflects "what actually killed me" rather than the whole fight's
# history. Read by Main._on_player_died() right when death happens (see
# Mech.die()) to build the death-report summary shown on the Game Over
# screen - see Main.gd/_build_death_report().
var recent_damage_log: Array = []
const DEATH_LOG_LOOKBACK_SEC = 8.0
# Where a VORTEX hit is dragging us toward (see "vortexed" status).
var vortex_drag_point: Vector2 = Vector2.ZERO
# Mythic tile modes collected during _recalculate_grid:
var magnet_repel_mode: bool = false   # Mythic Magnet flipped to Repel
var jumpjet_blink_mode: bool = false  # Mythic Jumpjet set to Blink
var actuator_school: int = -1 # Mythic Actuator "school" (-1 = no Mythic actuator equipped); 0=Velocity, 1=Ember, 2=Balanced - see ActuatorTile.gd
var shield_mythic_mode: int = -1 # Mythic Shield Generator mode (-1 = no Mythic shield equipped); 0=Aegis (tank), 1=Deflector (overflow eject) - see ShieldTile.gd/ShieldGeneratorTile.gd
var _blink_cooldown: float = 0.0
var jumpjet_rarity: int = -1
var jumpjet_energy = null
var actuator_energy = null

# --- Cloak (Ambusher backpack ability) ---
# Capacity/recharge-rate are sized once per _recalculate_grid() from
# CloakTile energy (same pattern as the shield generator); the actual
# charge/drain while playing is a simple runtime timer, independent of the
# hex-grid packet simulation (unlike jumpjet_energy, which only refills on
# equip changes - not something we want cloak to inherit).
var has_cloak_generator: bool = false
var max_cloak_charge: float = 0.0
var cloak_charge: float = 0.0
var cloak_recharge_rate: float = 0.0
var cloak_recharge_delay: float = 1.0
var cloak_drain_rate: float = 0.0
var is_cloaked: bool = false
var time_since_cloak_break: float = 999.0

# Ambush bonus window: any damage dealt within AMBUSH_WINDOW_DURATION
# seconds of a decloak event (from any cause - firing, taking a hit, or
# cloak charge running out, since _break_cloak() is the one chokepoint all
# three funnel through) gets AMBUSH_MULTIPLIER applied. Replaces the old
# "only the exact shot that broke cloak gets the bonus" behavior with a
# proper timed window per Natalia's request.
var _ambush_window_timer: float = 0.0
const AMBUSH_WINDOW_DURATION = 0.25
const AMBUSH_MULTIPLIER = 2.5

# --- Jammer Module (equippable pulse ability - distinct from the JammerMech
# role, which is a whole separate continuous-aura mech class) ---
var has_jammer_module: bool = false
var jammer_pulse_radius: float = 0.0
var jammer_pulse_interval: float = 8.0
var jammer_effect_duration: float = 2.0
var jammer_mode: int = 0 # 0 = VISION (blackout player screen), 1 = SYNERGY (mute one element)
var jammer_target_synergy: int = 0
var jammer_pulse_timer: float = 0.0

# --- Heal Beacon (Support backpack ability) ---
var has_healer: bool = false
var heal_pulse_power: float = 0.0
var heal_pulse_radius: float = 0.0
var heal_pulse_interval: float = 4.0
var heal_pulse_timer: float = 0.0

# Synergies actively muted on THIS mech by an enemy Jammer Module, mapped to
# remaining duration. Consulted when firing to suppress that element.
var jammed_synergies: Dictionary = {}

signal vision_jammed(duration: float)

func apply_shield_energy(amount: float):
	max_shield_hp += amount # Max shield grows based on energy it processes!
	shield_hp = max_shield_hp

var is_player: bool = false
var is_firing_outward: bool = false
var last_aim_position: Vector2 = Vector2.ZERO

var current_jammer_debuff: float = 1.0 # 1.0 is no debuff. 0.1 is 90% power reduction

var jumpjet_trail = null
var jumpjet_residue_timer: float = 0.0
var magnet_visual: Line2D = null

# Magnet enemy/loot group scans used to run every single physics frame
# (60Hz) - unlike the minimap/pathing throttle patterns elsewhere, nothing
# here caps how often get_nodes_in_group("enemy")/("loot") get walked and
# distance-checked against every entity. Throttled to MAGNET_UPDATE_HZ, with
# the skipped time accumulated into the effective delta passed to
# pull_towards()/external_force so pull strength over time is unchanged -
# only the sampling rate drops, not the total effect.
const MAGNET_UPDATE_HZ = 15.0
var _magnet_update_timer: float = 0.0
var _magnet_accum_delta: float = 0.0


var fire_cooldown: float = 0.0
var fire_rate: float = 0.25 # 4 shots per second

var components: Dictionary = {} # Dict of HexTile.BodySlot -> ComponentEquipment
var is_grid_dirty: bool = true
var precalculated_weapons: Array = []
var _renderer: Node2D = null # cached MechRenderer child, set in _ready()

var is_drowning: bool = false
var drown_timer: float = 1.0

# current_path/path_update_timer (per-mech AStarGrid2D path) removed -
# movement direction now comes from MapGenerator's shared flow field, see
# _execute_ai_tactics/MapGenerator.get_flow_direction().

# Advanced AI Tactics
var target: Node2D = null
var speed_modifier: float = 1.0
var engagement_distance: float = 200.0 # How close to get before strafing
var rotational_direction: float = 1.0 # 1.0 for clockwise, -1.0 for counter-clockwise
var base_speed: float = 150.0

# Separation steering (Natalia: "mostly shuffling around really close to one
# another"): every enemy independently approaches the SAME shared flow-field
# corridor toward the player, then orbits at the same engagement_distance
# ring with no awareness of each other - with a big enough wave, that ring's
# circumference just doesn't fit everyone, so they stack up and visibly jam/
# jostle against each other's collision shapes instead of spreading into an
# actual surrounding formation. A small, throttled repulsion-from-neighbors
# nudge (classic boid "separation") blended into velocity fixes the clumping
# without touching the approach/orbit logic itself.
const SEPARATION_QUERY_INTERVAL = 0.2
const SEPARATION_RADIUS = 70.0
const SEPARATION_WEIGHT = 0.7
var _separation_query_timer: float = 0.0
var _cached_separation: Vector2 = Vector2.ZERO

var separate_arm_firing: bool = false
var base_rarity: int = 0 # HexTile.Rarity.COMMON
# Set by SquadDirector before add_child() (same pattern as combat_role/
# base_rarity below) so build_loadout_for_role() can hand it to
# AutoEquipSolver. Null means "use the solver's old fixed-priority
# behavior" - safe default for anything that doesn't set this.
var spawn_profile: SolverProfile = null
# Back-reference to the Squad.gd instance this mech was recruited into (set
# by Squad.add_member()) - null for bosses and anything spawned outside the
# normal squad-assembly path. Used by the sight-sharing system below: a
# mech that spots the player broadcasts to squad.members ONLY, never
# globally, so different squads never leak sight info to each other.
var squad: Node = null
var is_boss: bool = false
# Set by Main._spawn_boss right after director._spawn_bot_for_role (same
# pattern as spawn_profile above). Drives which enrage style/ability
# pool/position style this specific boss uses - see the Boss Enrage &
# Signature Abilities section below. Null-safe everywhere it's read (falls
# back to role-based defaults) so a debug-menu-spawned or profile-less boss
# still works.
var boss_profile: BossProfile = null
var total_magnetic_power: float = 0.0
# -1 = attract loot of any rarity (default). Set by a Mythic Magnet's
# min_attract_rarity filter - see MagnetTile.gd.
var min_loot_attract_rarity: int = -1
var visual_seed: int = 0

signal dealt_damage(amount: float)
signal died()
signal fled_to_wild(bot: Node)

var is_dead: bool = false

# TEMPORARY diagnostic aid (not a real feature - easy to strip once the
# "enemies not chasing" report is actually pinned down): a small label above
# every non-boss enemy showing whether it currently thinks it has sight of
# the player or is searching, so the NEXT time this happens we can see
# directly which state they're stuck in instead of guessing from the code.
var _ai_state_label: Label = null


func apply_jammer_debuff(power_multiplier: float):
	# Take the most severe debuff if multiple jammers are present
	current_jammer_debuff = min(current_jammer_debuff, power_multiplier)

func _ready():
	# Build default body
	equip_component(ComponentEquipment.create_starter_torso(combat_role if not is_player else "", base_rarity))
	equip_component(ComponentEquipment.create_starter_arm(true, combat_role if not is_player else "", base_rarity))
	equip_component(ComponentEquipment.create_starter_arm(false, combat_role if not is_player else "", base_rarity))
	equip_component(ComponentEquipment.create_starter_leg(true, combat_role if not is_player else "", base_rarity))
	equip_component(ComponentEquipment.create_starter_leg(false, combat_role if not is_player else "", base_rarity))
	equip_component(ComponentEquipment.create_starter_head(combat_role if not is_player else "", base_rarity))
	equip_component(_create_role_backpack(combat_role if not is_player else "", base_rarity))

	if not is_player:
		visual_seed = randi()

		# Desync throttled per-mech timers (Natalia: "freezing is still
		# happening regularly"). Every one of these defaulted to 0.0, which
		# means every mech fires its FIRST throttled check on the very same
		# tick it spawns, and since they all reset to the same fixed
		# interval afterward, an entire wave's worth of mechs stays
		# perfectly synchronized forever - a thundering herd where up to 80
		# enemies' sight-check raycasts (or separation-steering shape
		# queries) all land on the exact same frame every ~0.2-0.33s instead
		# of being spread out. Randomizing the STARTING value only changes
		# WHEN each mech's timer first fires, not what it does once it
		# does - purely a scheduling fix.
		_sight_check_timer = randf() * (1.0 / SIGHT_CHECK_HZ)
		_separation_query_timer = randf() * SEPARATION_QUERY_INTERVAL
		_search_waypoint_timer = randf() * SEARCH_WAYPOINT_INTERVAL

	if not is_player:
		build_loadout_for_role(combat_role)
	
	# Attach Visual Renderer
	var renderer = load("res://scripts/visuals/MechRenderer.gd").new()
	renderer.name = "MechRenderer"
	add_child(renderer)
	_renderer = renderer

	# Pass the full components dict so the renderer can draw each piece
	renderer.components = components
	renderer._rebuild_visuals()
	
	# Collision shape - sized to match this mech's actual visual scale
	# (role-based, e.g. scout renders ~0.8x, brawler ~1.2x, boss up to 1.8x
	# before the extra mega/regular boss node-scale on top) rather than
	# every role sharing the same fixed 40x40 box regardless of how big or
	# small it actually looks on screen.
	var hitbox_scale = renderer.get_role_scale(combat_role, is_player)
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(40, 40) * hitbox_scale
	collision.shape = shape
	add_child(collision)
	
	if is_player:
		collision_layer = 8 # Layer 4 (Player)
		collision_mask = 1 | 2 | 4 | 16 # Env, Water, Enemy, Loot
	else:
		collision_layer = 4 # Layer 3 (Enemy)
		collision_mask = 1 | 2 | 8 # Env, Water, Player
		# NOTE: this was previously missing entirely, which silently broke
		# every system that looks up get_nodes_in_group("enemy"): Main.gd's
		# enemy cleanup on player death, Projectile.gd's lightning-arc
		# targeting, and now the Heal Beacon's ally lookup.
		add_to_group("enemy")

		_ai_state_label = Label.new()
		_ai_state_label.name = "AIStateLabel_DEBUG"
		_ai_state_label.position = Vector2(-30, -72)
		_ai_state_label.add_theme_font_size_override("font_size", 11)
		_ai_state_label.text = "?"
		add_child(_ai_state_label)

		# Boss fitness tracking (see get_boss_fitness/BossProfile evolution).
		# Connected for every non-player mech, not just is_boss ones - at this
		# point in _ready(), is_boss hasn't been set yet (Main._spawn_boss
		# flips it AFTER _spawn_bot_for_role's add_child returns), and the
		# handler itself is just a couple of counter increments, cheap enough
		# to leave on for regular grunts even though only bosses ever read it.
		dealt_damage.connect(_on_self_dealt_damage)

# Main._spawn_boss sets is_boss/boss_profile AFTER _spawn_bot_for_role's
# add_child already ran _ready() (and therefore already built the renderer
# once with is_boss still false) - call this right after to make the
# boss-only visual accents in MechRenderer actually appear.
func refresh_boss_visuals():
	if _renderer:
		_renderer._rebuild_visuals()

# Special-ability backpacks for specific roles (cloak for ambushers, an
# occasional jammer module for scouts, heal beacon for support). Falls back
# to the plain default backpack otherwise. Kept as a thin dispatcher so
# adding a new role ability later is a one-line match arm.
func _create_role_backpack(role: String, p_rarity: int) -> ComponentEquipment:
	var forced_synergy = _get_reactive_jam_synergy()
	match role:
		"ambusher":
			if randf() < 0.85: # not guaranteed, keeps some loot variety
				return ComponentEquipment.create_cloak_backpack(max(p_rarity, HexTile.Rarity.UNCOMMON))
		"scout":
			# Base chance is low (infrequent, per the original design request),
			# but jumps way up once the director's flagged the player leaning
			# on one synergy for kills - "jammers spawn in response to player
			# tactics," not just at a fixed background rate.
			var chance = 0.25 if forced_synergy < 0 else 0.65
			if randf() < chance:
				return ComponentEquipment.create_dual_utility_backpack(max(p_rarity, HexTile.Rarity.UNCOMMON), forced_synergy)
		"support":
			return ComponentEquipment.create_support_backpack(max(p_rarity, HexTile.Rarity.UNCOMMON), forced_synergy)
		"commander":
			return ComponentEquipment.create_command_backpack(max(p_rarity, HexTile.Rarity.RARE))
	return ComponentEquipment.create_starter_backpack(role, p_rarity)

# -1 if no over-reliance is currently flagged, or no director exists yet
# (e.g. very first spawns before any kills have been logged).
func _get_reactive_jam_synergy() -> int:
	var main = get_tree().current_scene
	if main and "world" in main and main.world and main.world.has_node("SquadDirector"):
		var director = main.world.get_node("SquadDirector")
		if "counter_jam_synergy" in director:
			return director.counter_jam_synergy
	return -1

func equip_component(comp: ComponentEquipment):
	if comp.slot_type == HexTile.BodySlot.TORSO:
		var h0 = HexCoord.new(0, 0)
		var has_core = false
		if comp.hex_grid.has_tile(h0):
			var existing = comp.hex_grid.get_tile(h0)
			if existing and existing.tile_type == "Core Reactor":
				has_core = true
			else:
				comp.hex_grid.remove_tile(h0)
		if not has_core:
			var core_tile = load("res://scripts/tiles/CoreTile.gd").new()
			core_tile.body_slot = HexTile.BodySlot.TORSO
			comp.hex_grid.add_tile(h0, core_tile)
			
	components[comp.slot_type] = comp
	add_child(comp)
	is_grid_dirty = true
	
func unequip_component(slot: HexTile.BodySlot) -> ComponentEquipment:
	if components.has(slot):
		var comp = components[slot]
		components.erase(slot)
		remove_child(comp)
		is_grid_dirty = true
		return comp
	return null

func _physics_process(delta: float):
	current_jammer_debuff = 1.0 # Reset every frame, JammerMech will re-apply it before we shoot if near
	_refresh_water_state()

	if is_drowning:
		drown_timer -= delta
		scale = Vector2.ONE * (drown_timer)
		modulate.a = drown_timer
		if drown_timer <= 0:
			die()
		return
		
	update_status_effects(delta)

	if fire_cooldown > 0:
		fire_cooldown -= delta

	_tick_weapon_charges(delta)
	_update_heat(delta)
		
	time_since_last_hit += delta
	if has_shield_generator and max_shield_hp > 0 and time_since_last_hit >= shield_recharge_delay:
		if shield_hp < max_shield_hp:
			shield_hp = min(max_shield_hp, shield_hp + shield_recharge_rate * delta)

	if is_boss:
		_boss_time_alive += delta
		if _boss_first_engagement >= 0.0:
			_boss_time_since_hit += delta
			if _boss_time_since_hit > BOSS_FLEE_GRACE:
				_boss_flee_penalty += BOSS_FLEE_RATE * delta

	_update_cloak(delta)
	_update_jammer_module(delta)
	_update_healer(delta)

	if is_player:
		_handle_player_input(delta)
		velocity += external_force
		move_and_slide()
		_process_ramming(delta)
		var lerp_weight = 10.0 * delta
		if lerp_weight > 1.0: lerp_weight = 1.0
		external_force = external_force.lerp(Vector2.ZERO, lerp_weight)

		# Magnet Logic
		if total_magnetic_power > 0.0:
			var pull_radius = 150.0 + (total_magnetic_power * 10.0)
			_update_magnet_visual(pull_radius)

			_magnet_accum_delta += delta
			_magnet_update_timer -= delta
			# Mythic Repel mode (design ruling): the field REFLECTS enemy
			# projectiles instead of shoving mechs - ownership flips so the
			# reflected shot hunts enemies and credits us for the damage.
			# Runs per-frame, NOT on the 10Hz throttle: a fast bolt covers
			# 40-400px between 10Hz ticks and would tunnel straight through
			# the field. The "projectile" group is small; this stays cheap.
			if magnet_repel_mode:
				for proj in get_tree().get_nodes_in_group("projectile"):
					if not is_instance_valid(proj):
						continue
					if proj.get("fired_by_player") != false:
						continue # only enemy shots get turned
					if proj.global_position.distance_to(global_position) > pull_radius:
						continue
					proj.fired_by_player = true
					proj.collision_mask = 4 | 1 # now hunts enemies + world
					proj.source_mech = self # damage credit / lifesteal to us
					var away = (proj.global_position - global_position).normalized()
					if away == Vector2.ZERO:
						away = -proj.direction
					proj.direction = away
					if "target_direction" in proj:
						proj.target_direction = away
					proj.modulate = Color(1.6, 1.6, 2.2) # flash so the turn reads

			if _magnet_update_timer <= 0.0:
				_magnet_update_timer = 1.0 / MAGNET_UPDATE_HZ
				var eff_delta = _magnet_accum_delta
				_magnet_accum_delta = 0.0

				var loot_nodes = get_tree().get_nodes_in_group("loot")
				for loot in loot_nodes:
					if min_loot_attract_rarity >= 0 and loot.has_method("get_rarity") and loot.get_rarity() < min_loot_attract_rarity:
						continue # Mythic Magnet filter - not shiny enough to bother with
					if loot.global_position.distance_to(global_position) < pull_radius:
						# Pull strength scales with power
						loot.pull_towards(global_position, eff_delta * (0.5 + total_magnetic_power * 0.02))
		elif magnet_visual:
			magnet_visual.visible = false
		
		# Drowning check
		if not Input.is_action_pressed("ui_select"):
			_check_drowning()
		
		if _renderer:
			_renderer.rotate_arms(get_global_mouse_position(), global_position)
			_renderer.animate_legs(velocity, Time.get_ticks_msec() / 1000.0)
	else:
		_execute_ai_tactics(delta)
		velocity += external_force
		move_and_slide()
		_process_ramming(delta)
		var lerp_weight = 10.0 * delta
		if lerp_weight > 1.0: lerp_weight = 1.0
		external_force = external_force.lerp(Vector2.ZERO, lerp_weight)
		
		var is_jumping = false
		if components.has(HexTile.BodySlot.BACKPACK):
			if components[HexTile.BodySlot.BACKPACK].component_name == "Jetpack":
				is_jumping = true
		if not is_jumping:
			_check_drowning()
		
		if target:
			if _renderer:
				_renderer.rotate_arms(target.global_position, global_position)
				_renderer.animate_legs(velocity, Time.get_ticks_msec() / 1000.0)

var external_force: Vector2 = Vector2.ZERO

# Melee/mass physics pillar: automatic contact damage on a fast enough
# collision with an opposing mech - no dedicated input, matches Natalia's
# "automatic on fast contact" call. mass x speed x coefficient, using THIS
# mech's own mass/speed (the other mech gets its own independent ram roll
# out of its own _process_ramming call the same frame, so a head-on
# collision between two heavy/fast mechs hurts both sides).
const RAM_MIN_SPEED = 220.0 # below this a bump is just a bump, not a ram
const RAM_DAMAGE_COEFF = 0.0006
const RAM_KNOCKBACK_COEFF = 1.0
const RAM_COOLDOWN = 0.75 # per-target, so sustained shoving doesn't melt someone in one second

var _ram_cooldowns: Dictionary = {} # other's instance_id -> seconds remaining

# Balanced-school Mythic Actuator's post-ram damage-reduction window (see
# apply_damage above and _process_ramming below).
const BRACE_DURATION = 0.5
var _brace_timer: float = 0.0

func _process_ramming(delta: float):
	if not _ram_cooldowns.is_empty():
		for id in _ram_cooldowns.keys():
			_ram_cooldowns[id] -= delta
			if _ram_cooldowns[id] <= 0.0:
				_ram_cooldowns.erase(id)

	var speed = velocity.length()
	if speed < RAM_MIN_SPEED:
		return

	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)
		var other = collision.get_collider()
		if not other or not is_instance_valid(other) or other == self:
			continue
		# Only opposing mechs - not obstacles/loot, and not friendly-fire
		# between two enemy squadmates that happen to jostle each other.
		if not ("combat_role" in other and "is_player" in other):
			continue
		if other.is_player == is_player:
			continue
		if not other.has_method("apply_damage"):
			continue

		var id = other.get_instance_id()
		if _ram_cooldowns.has(id):
			continue

		var dmg = total_mass * speed * RAM_DAMAGE_COEFF
		var knockback_coeff = RAM_KNOCKBACK_COEFF
		var ram_element = "RAW"
		var ram_label = "RAM!"

		# Mythic Actuator school flavor (see ActuatorTile.gd/update_status_effects):
		match actuator_school:
			0: # Velocity - fast, but pulls its punches
				dmg *= 0.7
			1: # Ember - slower mech, but a much harder, fire-tagged hit
				dmg *= 1.3
				ram_element = "FIRE"
				ram_label = "SEARING RAM!"
				if other.has_method("apply_status"):
					other.apply_status("burning", 3.0)
			2: # Balanced - normal damage, but extra shove out + a brief
				# self damage-reduction window right after landing the hit.
				knockback_coeff *= 1.5
				_brace_timer = BRACE_DURATION

		other.apply_damage(dmg, ram_element, self)
		_ram_cooldowns[id] = RAM_COOLDOWN

		if "external_force" in other:
			var away = other.global_position - global_position
			away = away.normalized() if away.length() > 0.01 else -collision.get_normal()
			other.external_force += away * speed * knockback_coeff

		if other.has_method("_show_floating_text"):
			other._show_floating_text(ram_label, Color(1.0, 0.6, 0.2))

func pull_towards(target_pos: Vector2, delta: float, strength: float = 600.0):
	var dir = (target_pos - global_position).normalized()
	external_force += dir * strength * delta

# Visual feedback for how far the Magnet is currently reaching - previously
# the pull radius had zero on-screen representation, so there was no way to
# tell how strong/far a magnet build actually was without guessing from feel.
# Gold tint when a Mythic Magnet's rarity filter is active, cyan otherwise.
func _update_magnet_visual(pull_radius: float):
	if not magnet_visual:
		magnet_visual = Line2D.new()
		magnet_visual.z_index = -1
		var pts = PackedVector2Array()
		for i in range(33):
			var a = i * TAU / 32.0
			pts.append(Vector2(cos(a), sin(a)))
		magnet_visual.points = pts
		add_child(magnet_visual)

	magnet_visual.visible = true
	magnet_visual.scale = Vector2.ONE * pull_radius
	var is_filtered = min_loot_attract_rarity >= 0
	var base_color = Color(1.0, 0.85, 0.2) if is_filtered else Color(0.3, 0.9, 1.0)
	var pulse = 0.35 + sin(Time.get_ticks_msec() / 200.0) * 0.15
	magnet_visual.default_color = Color(base_color.r, base_color.g, base_color.b, pulse)
	# The node itself is scaled up to pull_radius to draw the ring at the
	# right size, which would also scale up the line width - counteract
	# that so the ring reads as a consistent ~2px outline regardless of how
	# large the pull radius is.
	magnet_visual.width = 2.0 / max(1.0, pull_radius)

# Refreshes _in_water via an O(1) terrain-array lookup (same data source
# die()'s water check reads). Called once at the very top of
# _physics_process, BEFORE update_status_effects() - previously _in_water
# was only (re)computed inside _check_drowning(), which runs AFTER
# update_status_effects() in physics-process order, so the amphibious
# water-speed bonus was always reading the PREVIOUS frame's water state
# (a one-frame lag on entering/exiting water). Splitting the terrain lookup
# out and moving it earlier fixes the ordering; _check_drowning() below now
# just reuses the already-current _in_water instead of recomputing it.
func _refresh_water_state():
	var is_over_water = false
	var map = _get_map_ref()
	if map and "terrain" in map:
		var grid_pos = Vector2i(int(floor(global_position.x / map.tile_size)), int(floor(global_position.y / map.tile_size)))
		if grid_pos.x >= 0 and grid_pos.x < map.width and grid_pos.y >= 0 and grid_pos.y < map.height:
			is_over_water = map.terrain[grid_pos.y][grid_pos.x] == map.BiomeType.WATER
	_in_water = is_over_water

func _check_drowning():
	var is_over_water = _in_water
	if is_over_water:
		# Amphibious mechs (the "diver" role) are a genuine water-capable
		# variant, not a loadout accident - never affected by the water
		# check at all, and get a real speed bonus (see update_status_effects)
		# rather than merely surviving.
		if is_amphibious:
			return
		# Locked design rule (FEATURE_ROADMAP.md): a mech with jumpjets never
		# drowns - the jets kick on automatically the moment it's over water
		# (including spawning directly onto it) and stay on until dry land.
		if _has_jumpjets():
			_force_jumpjets_on()
			return
		is_drowning = true
		velocity = Vector2.ZERO
	elif _water_hover_active:
		_water_hover_active = false
		if jumpjet_trail:
			for p in jumpjet_trail.get_children():
				p.emitting = false

# Trail creation, shared between sprint (player input) and water-hover
# (both player and AI) - was inlined in _handle_player_input, which meant
# AI mechs could never show a jet trail at all.
func _ensure_jumpjet_trail():
	if jumpjet_trail != null:
		return
	jumpjet_trail = Node2D.new()
	jumpjet_trail.show_behind_parent = true

	var p_l = CPUParticles2D.new()
	p_l.local_coords = false
	p_l.lifetime = 0.5
	p_l.explosiveness = 0.0
	p_l.spread = 180.0
	p_l.initial_velocity_min = 10.0
	p_l.initial_velocity_max = 30.0
	p_l.scale_amount_min = 4.0
	p_l.scale_amount_max = 8.0
	p_l.amount = 10
	p_l.position = Vector2(-14, 44) # Left foot
	jumpjet_trail.add_child(p_l)

	var p_r = p_l.duplicate()
	p_r.position = Vector2(14, 44) # Right foot
	jumpjet_trail.add_child(p_r)

	add_child(jumpjet_trail)

func _has_jumpjets() -> bool:
	if jumpjet_rarity >= 0:
		return true
	if jumpjet_energy and jumpjet_energy.magnitude > 0:
		return true
	if components.has(HexTile.BodySlot.BACKPACK):
		if components[HexTile.BodySlot.BACKPACK].component_name == "Jetpack":
			return true
	return false

# Auto-hover over water: light the jet trail so the save reads visually
# ("why am I not drowning?" - because your jets are visibly firing).
# Runs after _handle_player_input in the frame, so it wins over the
# sprint-off branch while over water; _check_drowning's elif above hands
# control back to the normal sprint logic once on dry land.
var _water_hover_active: bool = false

func _force_jumpjets_on():
	_water_hover_active = true
	_ensure_jumpjet_trail()
	var new_color = EnergyPacket.get_color_blend(jumpjet_energy.synergies) if jumpjet_energy else Color.WHITE
	for p in jumpjet_trail.get_children():
		if p.color != new_color: p.color = new_color
		p.emitting = true

func _handle_player_input(delta: float):
	if jumpjet_energy and jumpjet_energy.magnitude > 0:
		jumpjet_energy.magnitude *= exp(-2.0 * delta) # Decay energy smoothly
		if jumpjet_energy.magnitude < 0.1: jumpjet_energy.magnitude = 0.0
		
	if actuator_energy and actuator_energy.magnitude > 0:
		actuator_energy.magnitude *= exp(-2.0 * delta) # Decay energy smoothly
		if actuator_energy.magnitude < 0.1: actuator_energy.magnitude = 0.0

	# Simple WASD movement
	var input_dir = Vector2.ZERO
	input_dir.x = Input.get_axis("ui_left", "ui_right")
	input_dir.y = Input.get_axis("ui_up", "ui_down")
	
	if input_dir.length() > 0:
		input_dir = input_dir.normalized()
		
	# Calculate base walk multiplier from Actuators
	var actuator_mult = 1.0
	if actuator_energy and actuator_energy.magnitude > 0:
		actuator_mult += (actuator_energy.magnitude / 200.0)
		actuator_mult = min(actuator_mult, 3.5) # User requested max 3.5x for actuator

	# Calculate sprint multiplier from Jumpjets
	var sprint_mult = 0.0
	if Input.is_key_pressed(KEY_SHIFT):
		sprint_mult = 0.5 # Base sprint is +0.5x speed
		if jumpjet_energy and jumpjet_energy.magnitude > 0:
			sprint_mult += (jumpjet_energy.magnitude / 200.0)
			sprint_mult = min(sprint_mult, 2.5) # Up to +2.5x from jumpjets, so jumpjets alone = 3.5x walking speed max
			
		if is_player:
			_ensure_jumpjet_trail()

			var new_color = EnergyPacket.get_color_blend(jumpjet_energy.synergies) if jumpjet_energy else Color.WHITE
			for p in jumpjet_trail.get_children():
				if p.color != new_color: p.color = new_color
				p.emitting = true
				
			if jumpjet_energy and jumpjet_energy.magnitude > 0:
				jumpjet_residue_timer -= delta
				if jumpjet_residue_timer <= 0.0:
					jumpjet_residue_timer = 0.15 # Spawn residue periodically
					var residue = JumpjetResidue.new()
					residue.global_position = global_position
					var dmg = max(10.0, jumpjet_energy.magnitude * 0.1)
					residue.setup(dmg, jumpjet_energy.synergies)
					get_parent().add_child(residue)
	else:
		if jumpjet_trail:
			for p in jumpjet_trail.get_children():
				p.emitting = false

	# Combine multipliers and enforce absolute cap
	var total_mult = actuator_mult + sprint_mult
	total_mult = min(total_mult, 3.8) # User requested max 3.8x for both combined
	
	var actual_move_speed = current_move_speed * total_mult
	var target_vel = input_dir * actual_move_speed
	
	# Scale acceleration much slower to give a feeling of weight
	var accel = 600.0
	if jumpjet_rarity >= 0:
		accel += (jumpjet_rarity * 150.0)
	
	if target_vel == Vector2.ZERO:
		velocity = velocity.move_toward(Vector2.ZERO, accel * delta)
	else:
		velocity = velocity.move_toward(target_vel, accel * delta)
	
	# JumpJets automatically hover over Water (Mask 2) and some obstacles
	if jumpjet_rarity >= 0:
		collision_mask = 1 | 4 | 16 # Only collide with walls/obstacles, Enemy, Loot
	else:
		collision_mask = 1 | 2 | 4 | 16 # Collide with water too
		
	# Mouse Aiming
	var mouse_pos = get_global_mouse_position()
	
	# Firing logic
	var is_left_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var is_right_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	
	# 1/2/3 ARE the fire buttons for the big charged shots (and only those).
	# Edge-triggered: one press = one big hit, if it's ready. The mouse
	# never fires these; they never fire from the mouse. See _fire_charged.
	for key_pair in [[KEY_1, "1"], [KEY_2, "2"], [KEY_3, "3"]]:
		var held = Input.is_key_pressed(key_pair[0])
		if held and not _terakey_held.get(key_pair[1], false):
			_fire_charged(key_pair[1], mouse_pos)
		_terakey_held[key_pair[1]] = held

	# Mythic Jumpjet Blink: Space teleports toward the cursor, capped range,
	# landing snapped to valid ground, on a cooldown.
	if jumpjet_blink_mode:
		_blink_cooldown -= delta
		if Input.is_action_just_pressed("ui_select") and _blink_cooldown <= 0.0:
			_blink_cooldown = 3.0
			var to_cursor = get_global_mouse_position() - global_position
			if to_cursor.length() > 4.0:
				var dest = global_position + to_cursor.normalized() * min(to_cursor.length(), 240.0)
				var map = _get_map_ref()
				if map and map.has_method("get_valid_spawn_position"):
					dest = map.get_valid_spawn_position(dest)
				_ensure_jumpjet_trail()
				for p in jumpjet_trail.get_children():
					p.emitting = true
				global_position = dest
	
	var is_firing = false
	if is_left_pressed and is_right_pressed and not separate_arm_firing:
		_shoot(mouse_pos, true, true, delta)
		is_firing = true
	elif is_left_pressed:
		_shoot(mouse_pos, true, true, delta)
		is_firing = true
	elif is_right_pressed:
		if separate_arm_firing:
			_shoot(mouse_pos, true, false, delta)
		else:
			_shoot(mouse_pos, false, false, delta)
		is_firing = true
		
	# NOTE: no release-fire anymore. Under the pre-prime model charge builds
	# passively, so the old "fire partial charge on mouse release" behavior
	# turned into constant unprompted spray (charge crossed the 10% floor
	# while idling and the next mouse-up frame fired it). Releasing the
	# mouse now does nothing; charge just holds at cap until you shoot.

# Passive background charging - the "pre-prime" model. Every weapon's
# accumulator charge builds all the time, whether or not anyone is holding
# the trigger, capped at one full shot. _shoot() then releases on demand
# like a completely normal gun, and the 1/2/3 keys become an optional
# early dump (fire a partial charge NOW) rather than the only release.
# Bosses charge Accumulator banks on a flat recharge TIME instead of the
# normal rate (delta / fire_rate) - a heavily-Accumulator-equipped mount's
# `required` charge can be large enough that a regular mech waits a very
# long time between big volleys. "Unlimited accumulator shots if equipped
# with them" per design: a boss isn't gated by that scarcity at all, it
# just fires its full-power banked volley on a short, flat cadence instead
# - full power preserved (this only changes TIMING, not magnitude).
const BOSS_BANK_RECHARGE_TIME = 2.5

func _tick_weapon_charges(delta: float):
	for data in precalculated_weapons:
		var mount = data.mount
		var required = data.packet.charge_required
		if data.get("bank_mode", "") == "bank":
			if is_boss:
				mount.bank_current_charge = min(required, mount.bank_current_charge + delta * (required / BOSS_BANK_RECHARGE_TIME))
			elif mount.bank_current_charge < required:
				mount.bank_current_charge = min(required, mount.bank_current_charge + delta / max(0.01, fire_rate))
			if mount.bank_current_charge >= required:
				# AI never clicks a mouse: auto-release the bank when full.
				if not is_player:
					var packet_to_fire = data.packet.copy()
					packet_to_fire.magnitude *= current_jammer_debuff
					for k in packet_to_fire.synergies:
						packet_to_fire.synergies[k] *= current_jammer_debuff
					_apply_synergy_jamming(packet_to_fire)
					mount._fire_combined_projectile(self, packet_to_fire, data.step)
					mount.bank_current_charge = 0.0
					heat = max(0.0, heat - required * 0.6) # AI vents on auto-release too
		else:
			if mount.current_charge < required:
				mount.current_charge = min(required, mount.current_charge + delta / max(0.01, fire_rate))

func _shoot(target_pos: Vector2, is_outward: bool, fire_left_arm: bool = true, delta: float = 0.0):
	last_aim_position = target_pos
	is_firing_outward = is_outward

	if is_grid_dirty:
		_recalculate_grid()

	var was_cloaked = is_cloaked
	var fired_a_shot = false

	for data in precalculated_weapons:
		if is_player and separate_arm_firing and data.slot_type != HexTile.BodySlot.BACKPACK:
			if fire_left_arm and data.slot_type == HexTile.BodySlot.ARM_R:
				continue
			if not fire_left_arm and data.slot_type == HexTile.BodySlot.ARM_L:
				continue

		var mount = data.mount
		var bank_mode = data.get("bank_mode", "")
		var required_charge = data.packet.charge_required

		# Charging happens passively in _tick_weapon_charges(). The mouse
		# fires ONLY normal entries - the big charged shot belongs to its
		# 1/2/3 key exclusively (_fire_charged). Two independent weapons
		# sharing one barrel.
		if bank_mode == "bank":
			continue

		if mount.current_charge < required_charge:
			continue

		# While the big shot is still charging, the accumulator siphons
		# HALF of every normal shot's payload. Once the bank sits full
		# (waiting on its key), the siphon stops - full-strength fire.
		var siphon = 1.0
		if bank_mode == "normal":
			var bank_required = float(data.get("bank_required", 0.0))
			if bank_required > 0.0 and mount.bank_current_charge < bank_required:
				siphon = 0.5

		var packet_to_fire = data.packet.copy()
		# The "almost as if there were no accumulator": normal fire pays
		# the small quality tax (shrinks with accumulator rarity/level).
		var tax = data.packet.accumulator_quality * current_jammer_debuff * siphon
		packet_to_fire.magnitude *= tax
		for k in packet_to_fire.synergies:
			packet_to_fire.synergies[k] *= tax
		_apply_synergy_jamming(packet_to_fire)
		packet_to_fire.magnitude *= _get_ambush_multiplier()

		mount._fire_combined_projectile(self, packet_to_fire, data.step)
		mount.current_charge -= required_charge
		# Thermal venting: firing sheds heat proportional to the volley
		heat = max(0.0, heat - required_charge * 0.6)
		fired_a_shot = true

	if fired_a_shot and was_cloaked:
		_break_cloak()

# Last-frame state of the 1/2/3 keys for edge detection (one press = one
# big shot, see _fire_charged / _handle_player_input).
var _terakey_held: Dictionary = {}

# Fire the big charged accumulator shot bound to `key`. This is the ONLY
# player-side release path for bank entries: press once, it fires if fully
# charged; if it isn't ready yet you get a charge readout instead of a
# wasted squib. No quality tax here - the big hit always lands full value.
func _fire_charged(key: String, target_pos: Vector2):
	last_aim_position = target_pos
	is_firing_outward = true

	for data in precalculated_weapons:
		if data.get("bank_mode", "") != "bank":
			continue
		if data.packet.trigger_key != key:
			continue
		var mount = data.mount
		var required = data.packet.charge_required

		if mount.bank_current_charge < required:
			_show_floating_text("Charging %d%%" % int(100.0 * mount.bank_current_charge / max(0.001, required)), Color(0.6, 0.8, 1.0))
			continue

		var packet_to_fire = data.packet.copy()
		packet_to_fire.magnitude *= current_jammer_debuff
		for k in packet_to_fire.synergies:
			packet_to_fire.synergies[k] *= current_jammer_debuff
		_apply_synergy_jamming(packet_to_fire)
		packet_to_fire.magnitude *= _get_ambush_multiplier()
		if is_cloaked:
			_break_cloak()

		mount._fire_combined_projectile(self, packet_to_fire, 0)
		mount.bank_current_charge = 0.0
		heat = max(0.0, heat - required * 0.6) # big shot = big heat dump

# --- Lightweight heat, v1 (FEATURE_ROADMAP.md group 5, locked spec) --------
# No live packet simulation: heat is ONE scalar per mech, derived from the
# static grid sim. Everything is proportional to totals (Natalia's ruling):
#   - generation rate ~ sum of charge_required across armed weapons
#   - venting ~ the volley just released
#   - volatility severity ~ current heat
# ICE-dominant circuits actively cool (can fully solve heat); LIGHTNING-
# heavy circuits arc into adjacent tiles when hot; hitting the cap knocks
# out an Accumulator via the existing disable/reboot machinery.
const HEAT_CAPACITY = 100.0
var heat: float = 0.0
var heat_rate: float = 0.0      # computed in _recalculate_grid
var heat_ice_frac: float = 0.0
var heat_ltg_frac: float = 0.0
var _heat_arc_timer: float = 0.0

func _update_heat(delta: float):
	if precalculated_weapons.is_empty():
		heat = max(0.0, heat - 10.0 * delta)
		return

	# Generation minus constant ambient dissipation. heat_rate can already
	# be negative (ICE cooling), so heavily iced builds pin to 0 here.
	heat = clamp(heat + (heat_rate - 2.0) * delta, 0.0, HEAT_CAPACITY)

	# LIGHTNING volatility: above 70% heat, lightning-heavy storage arcs
	# into the grid - severity proportional to current heat.
	if heat > HEAT_CAPACITY * 0.7 and heat_ltg_frac > 0.3:
		_heat_arc_timer -= delta
		if _heat_arc_timer <= 0.0:
			_heat_arc_timer = 2.0
			_heat_arc_damage()

	if heat >= HEAT_CAPACITY:
		_overheat()

func _heat_arc_damage():
	# Shock a random tile in a random component - reuses the standard
	# take_damage -> disable/reboot pipeline, no new failure states.
	var comps = components.values()
	if comps.is_empty():
		return
	var comp = comps[randi() % comps.size()]
	var tiles = comp.hex_grid.get_all_tiles()
	if tiles.is_empty():
		return
	var tile = tiles[randi() % tiles.size()]
	tile.take_damage(heat * 0.1) # proportional to heat, not flat
	if is_player:
		_show_floating_text("ARC!", Color(1.0, 1.0, 0.3))

func _overheat():
	# Knock out one Accumulator (the thing storing all that energy) via the
	# existing disable machinery, shed a big chunk of heat, carry on.
	for comp in components.values():
		for tile in comp.hex_grid.get_all_tiles():
			if tile.tile_type == "Accumulator" and not tile.is_disabled:
				tile.take_damage(tile.hp + 1.0)
				heat = HEAT_CAPACITY * 0.55
				if is_player:
					_show_floating_text("OVERHEAT!", Color(1.0, 0.35, 0.2))
				is_grid_dirty = true
				# Pay the recalculation cost RIGHT NOW instead of leaving
				# is_grid_dirty lazy for whatever _shoot() call happens to
				# come next - same class of bug, same fix, as the deploy-time
				# freeze (see Main._close_garage's comment). An overheat can
				# happen mid-fight and then the player stops firing for a
				# while (repositioning, or just noticing they're overheated);
				# without this, THAT much-later shot is the one that
				# synchronously eats the recalc - "hesitation when shooting
				# the first time after not shooting for some interval." Doing
				# it here instead bundles the cost into a moment that's
				# already visually busy (the OVERHEAT! text/heat spike),
				# where a brief hitch is far less jarring.
				_recalculate_grid()
				return
	# No accumulator to sacrifice: vent hard instead (raw/kinetic builds
	# shouldn't really get here - they generate almost nothing).
	heat = HEAT_CAPACITY * 0.4

# _shoot_release() is gone. Under the old hold-to-charge model it fired
# the partial charge when the mouse was released; under the pre-prime model
# (passive charging) it fired unprompted every idle frame the moment charge
# crossed its 10% floor - the "shooting randomly" playtest bug. Partial
# releases are now exclusively the hold-1/2/3 dump in _shoot().

func _recalculate_grid():
	precalculated_weapons.clear()
	max_shield_hp = 0.0 # Reset shield HP
	has_shield_generator = false
	shield_recharge_delay = 3.0
	shield_recharge_rate = 0.0
	base_move_speed = 150.0 # Reset base speed for Jumpjets to calculate
	jumpjet_rarity = -1
	magnet_repel_mode = false
	jumpjet_blink_mode = false
	actuator_school = -1
	shield_mythic_mode = -1

	if jumpjet_energy == null:
		jumpjet_energy = EnergyPacket.new(0.0, null)
	jumpjet_energy.magnitude = 0.0
	jumpjet_energy.synergies.clear()

	# Reset cloak/jammer-module/healer capability flags; they get rebuilt
	# below from whatever tiles are actually equipped this recalculation.
	has_cloak_generator = false
	max_cloak_charge = 0.0
	cloak_recharge_rate = 0.0
	cloak_recharge_delay = 1.0
	has_jammer_module = false
	has_healer = false
	heal_pulse_power = 0.0

	total_magnetic_power = 0.0
	min_loot_attract_rarity = -1
	stat_modifiers.clear()

	# Melee/mass physics pillar: total mass drives the movement-speed
	# penalty/bonus below (see update_status_effects) and the ramming
	# damage formula (see _process_ramming). Recomputed here rather than
	# every frame since it only changes on loadout edits, same as every
	# other grid-derived stat in this function.
	total_mass = 0.0
	for comp in components.values():
		if comp.get("hex_grid"):
			for t in comp.hex_grid.get_all_tiles():
				total_mass += t.get_weight()

	# Aggregate all component stat modifiers
	for comp in components.values():
		if comp.get("stat_modifiers"):
			for k in comp.stat_modifiers:
				if stat_modifiers.has(k):
					stat_modifiers[k] += comp.stat_modifiers[k] - 1.0 # Additive percentage bonuses
				else:
					stat_modifiers[k] = comp.stat_modifiers[k]
	
	if not components.has(HexTile.BodySlot.TORSO):
		return
		
	var torso = components[HexTile.BodySlot.TORSO]
	
	# Collect energy from ALL generators in the Torso
	var initial_packets: Array[EnergyPacket] = []
	for coord in torso.hex_grid.grid.keys():
		var t = torso.hex_grid.get_tile(coord)
		if t.has_method("generate_energy"):
			var pkts = t.generate_energy(torso.hex_grid)
			for p in pkts:
				p.position = HexCoord.new(coord.x, coord.y)
			initial_packets.append_array(pkts)
	
	# PHASE 1: Route through Torso grid
	_simulate_grid(torso.hex_grid, initial_packets)
	
	# PHASE 2: Collect transferred packets from Sinks and route into peripheral grids
	var peripheral_transfer = _collect_transfers(torso)
	# Simulate HEAD and BACKPACK first so they can return energy
	var return_pkts: Array[EnergyPacket] = []
	for accessory_slot in [HexTile.BodySlot.HEAD, HexTile.BodySlot.BACKPACK]:
		if peripheral_transfer.has(accessory_slot) and components.has(accessory_slot):
			var accessory_comp = components[accessory_slot]
			var a_pkts = peripheral_transfer[accessory_slot]
			_route_to_peripheral(a_pkts, accessory_comp)
			
			for coord in accessory_comp.hex_grid.grid.keys():
				var t = accessory_comp.hex_grid.get_tile(coord)
				if t.has_method("generate_energy"):
					var pkts = t.generate_energy(accessory_comp.hex_grid)
					for p in pkts:
						p.position = HexCoord.new(coord.x, coord.y)
					a_pkts.append_array(pkts)
					
			_simulate_grid(accessory_comp.hex_grid, a_pkts)
			
			# Collect return packets
			var accessory_return = _collect_transfers(accessory_comp)
			if accessory_return.has(HexTile.BodySlot.TORSO):
				return_pkts.append_array(accessory_return[HexTile.BodySlot.TORSO])

	if return_pkts.size() > 0:
		var return_pos = HexCoord.new(0, 0)
		var return_tile = null
		# Find the Accessory Return node
		for coord_v in torso.hex_grid.grid.keys():
			var t = torso.hex_grid.grid[coord_v]
			if t.tile_type == "Accessory Return":
				return_pos = HexCoord.new(coord_v.x, coord_v.y)
				return_tile = t
				break
		
		var final_return_pkts: Array[EnergyPacket] = []
		for pkt in return_pkts:
			if return_tile:
				# Process it through the Return Link
				var out = return_tile.process_energy(pkt, 0, torso.hex_grid)
				for p in out:
					p.position = return_pos
					p.is_active = true
					final_return_pkts.append(p)
			else:
				pkt.position = return_pos
				pkt.is_active = true
				final_return_pkts.append(pkt)
				
		# Re-simulate Torso with returned energy!
		_simulate_grid(torso.hex_grid, final_return_pkts)
		
		# Add any new transfers from Torso back into the peripheral pools
		var second_transfers = _collect_transfers(torso)
		for slot in second_transfers:
			if not peripheral_transfer.has(slot):
				peripheral_transfer[slot] = []
			peripheral_transfer[slot].append_array(second_transfers[slot])

	# Simulate remaining peripherals (Arms, Legs)
	for slot in components.keys():
		if slot == HexTile.BodySlot.HEAD or slot == HexTile.BodySlot.BACKPACK or slot == HexTile.BodySlot.TORSO: 
			continue # Already simulated
			
		var comp = components[slot]
		var pkts: Array[EnergyPacket] = []
		if peripheral_transfer.has(slot):
			pkts.append_array(peripheral_transfer[slot])
			_route_to_peripheral(pkts, comp)
			
		for coord in comp.hex_grid.grid.keys():
			var t = comp.hex_grid.get_tile(coord)
			if t.has_method("generate_energy"):
				var generated = t.generate_energy(comp.hex_grid)
				for p in generated:
					p.position = HexCoord.new(coord.x, coord.y)
				pkts.append_array(generated)
				
		_simulate_grid(comp.hex_grid, pkts)
			
	for comp in components.values():
		for tile in comp.hex_grid.get_all_tiles():
			if (tile.tile_type == "Weapon Mount" or tile.tile_type == "Accessory Return" or tile.tile_type == "Torso Return") and "pending_packets" in tile and tile.pending_packets.size() > 0:
				# Accumulator split-fire model (Natalia's locked design):
				# whenever accumulators feed this mount - routed THROUGH the
				# circuit (packet.acc_*_mult) or sitting adjacent (bank) -
				# the mount gets TWO fully independent weapons:
				#   - NORMAL entry: the un-boosted packet. Mouse-fired,
				#     behaves almost as if no accumulator existed (small
				#     quality tax) - EXCEPT that while the big shot is still
				#     charging, the accumulator siphons HALF the payload.
				#     Once the big shot sits full, the siphon stops and
				#     normal shots return to full strength.
				#   - BANK entry: the big charged shot. Charges passively,
				#     fired ONLY by pressing its 1/2/3 key - one press, one
				#     big hit. Clicking never touches it.
				var bank_charge = 0.0
				var bank_amplify = 0.0
				var bank_quality = 1.0
				if tile.tile_type == "Weapon Mount" and tile.grid_position:
					var bank = _get_adjacent_accumulator_bonus(comp.hex_grid, tile.grid_position)
					bank_charge = bank.charge
					bank_amplify = bank.amplify
					bank_quality = bank.quality

				# Detect routed-through accumulators via the recorded mults
				var probe = tile.pending_packets[0].packet
				for i in range(1, tile.pending_packets.size()):
					if tile.pending_packets[i].packet.acc_damage_mult > probe.acc_damage_mult:
						probe = tile.pending_packets[i].packet
				var has_routed_acc = probe.acc_damage_mult > 1.001

				if bank_charge > 0.0 or has_routed_acc:
					var combined = tile.pending_packets[0].packet.copy()
					for i in range(1, tile.pending_packets.size()):
						combined.merge(tile.pending_packets[i].packet)
					# Adjacent (bank) accumulators tax normal fire the same
					# way routed-through ones do - worst neighbor wins.
					combined.accumulator_quality = min(combined.accumulator_quality, bank_quality)

					# Bank entry: the big charged shot. Boosts from routed
					# accumulators (acc_damage_mult) and adjacent bank
					# accumulators (bank_amplify) combine; charge time is the
					# base cost scaled by acc_charge_mult plus the adjacency
					# bank's own charge. Fired ONLY by pressing its 1/2/3 key
					# (_fire_charged); AI auto-releases on full
					# (_tick_weapon_charges). The mouse never fires this.
					var enhanced = combined.copy()
					enhanced.amplify(combined.acc_damage_mult * (1.0 + bank_amplify))
					enhanced.charge_required = combined.charge_required * combined.acc_charge_mult + bank_charge
					enhanced.trigger_key = combined.trigger_key if combined.trigger_key != "None" else "1"

					# Normal-fire entry: the base (unamplified) packet, at
					# whatever charge_required routing naturally gave it.
					# While the bank below is still charging, _shoot() halves
					# this entry's payload (the accumulator is siphoning);
					# bank_required is stashed here so _shoot can tell.
					precalculated_weapons.append({
						"mount": tile,
						"packet": combined.copy(),
						"step": 0,
						"slot_type": comp.slot_type,
						"bank_mode": "normal",
						"bank_required": enhanced.charge_required
					})

					precalculated_weapons.append({
						"mount": tile,
						"packet": enhanced,
						"step": 0,
						"slot_type": comp.slot_type,
						"bank_mode": "bank"
					})
				else:
					var step_groups = {}
					for item in tile.pending_packets:

						var step = item.step
						if not step_groups.has(step):
							step_groups[step] = item.packet.copy()
						else:
							step_groups[step].merge(item.packet)

					for step in step_groups:
						precalculated_weapons.append({
							"mount": tile,
							"packet": step_groups[step],
							"step": step,
							"slot_type": comp.slot_type
						})
				tile.clear_pending()
				
			if tile.has_method("get_speed_bonus"):
				base_move_speed += tile.get_speed_bonus()
				
			if tile.has_method("get_magnetic_power"):
				total_magnetic_power += tile.get_magnetic_power()

			if tile.has_method("get_min_attract_rarity"):
				var filter_rarity = tile.get_min_attract_rarity()
				if filter_rarity >= 0:
					# Most permissive combination if multiple magnets disagree
					min_loot_attract_rarity = filter_rarity if min_loot_attract_rarity < 0 else min(min_loot_attract_rarity, filter_rarity)

			# Mythic Magnet in Repel mode / Mythic Jumpjet in Blink mode
			if tile.tile_type == "Magnet" and tile.rarity == HexTile.Rarity.MYTHIC and tile.get("repel_mode") == true:
				magnet_repel_mode = true
			if tile.tile_type == "Jumpjet" and tile.rarity == HexTile.Rarity.MYTHIC and int(tile.get("mythic_mode")) == 1:
				jumpjet_blink_mode = true

			if tile.tile_type == "Actuator" and tile.rarity == HexTile.Rarity.MYTHIC:
				actuator_school = int(tile.get("mythic_mode"))
				
			if tile.tile_type == "Shield Generator" and tile.rarity == HexTile.Rarity.MYTHIC:
				shield_mythic_mode = int(tile.get("mythic_mode"))

			if tile.tile_type == "Shield Generator" and tile.has_method("get_shield_energy"):
				has_shield_generator = true
				var shield_energy = tile.get_shield_energy()
				# Scale directly 1:1 with energy to allow tanking own hits
				max_shield_hp += shield_energy
				# Mythic takes .25s, Legendary takes 0.5s, Rare takes 1.0s, Uncommon 2.0s, Common 3.0s
				if tile.rarity == HexTile.Rarity.MYTHIC:
					shield_recharge_delay = min(shield_recharge_delay, 0.25)
				elif tile.rarity == HexTile.Rarity.LEGENDARY:
					shield_recharge_delay = min(shield_recharge_delay, 0.5)
				elif tile.rarity == HexTile.Rarity.RARE:
					shield_recharge_delay = min(shield_recharge_delay, 1.0)
				elif tile.rarity == HexTile.Rarity.UNCOMMON:
					shield_recharge_delay = min(shield_recharge_delay, 2.0)
				else:
					shield_recharge_delay = min(shield_recharge_delay, 3.0)
					
				# Rapidly recharge (e.g. fully recharge in 2 seconds)
				shield_recharge_rate += max_shield_hp * 0.5
				
				if tile.has_method("get_shield_synergies"):
					var syns = tile.get_shield_synergies()
					for k in syns:
						if shield_synergies.has(k):
							shield_synergies[k] += syns[k]
						else:
							shield_synergies[k] = syns[k]

			if tile.tile_type == "Cloak Generator" and tile.has_method("get_cloak_energy"):
				has_cloak_generator = true
				var cloak_energy_amount = tile.get_cloak_energy()
				max_cloak_charge += cloak_energy_amount
				var duration = tile.get_cloak_duration() if tile.has_method("get_cloak_duration") else 3.0
				var recharge_time = tile.get_recharge_time() if tile.has_method("get_recharge_time") else 6.0
				cloak_drain_rate = max_cloak_charge / max(0.1, duration)
				cloak_recharge_rate += max_cloak_charge / max(0.1, recharge_time)

			if tile.tile_type == "Jammer Module" and tile.has_method("get_jam_energy"):
				if not has_jammer_module: # first module found sets the profile
					has_jammer_module = true
					tile.get_jam_energy() # consume so it doesn't pile up unread
					jammer_pulse_radius = tile.get_pulse_radius()
					jammer_pulse_interval = tile.get_pulse_interval()
					jammer_effect_duration = tile.get_effect_duration()
					jammer_mode = tile.jam_mode
					jammer_target_synergy = tile.target_synergy
					if jammer_pulse_timer <= 0.0:
						jammer_pulse_timer = jammer_pulse_interval

			if tile.tile_type == "Heal Beacon" and tile.has_method("get_heal_energy"):
				has_healer = true
				heal_pulse_power += tile.get_heal_energy() * 0.1
				heal_pulse_radius = tile.get_pulse_radius()
				heal_pulse_interval = tile.get_pulse_interval()

	# Find dominant shield synergy
	var max_syn_val = 0.0
	for k in shield_synergies:
		if shield_synergies[k] > max_syn_val:
			max_syn_val = shield_synergies[k]
			dominant_shield_synergy = str(k)
				
	# Keep shield HP within bounds
	shield_hp = min(shield_hp, max_shield_hp)
	if not has_shield_generator:
		shield_hp = 0.0

	# Heat profile of this circuit (see the heat block near _update_heat):
	# generation proportional to total armed charge_required; ICE share
	# actively cools (2x weight, so ~50% ice storage fully solves heat);
	# LIGHTNING share drives the hot-arcing volatility.
	heat_rate = 0.0
	var _syn_totals: Dictionary = {}
	var _syn_sum: float = 0.0
	for data in precalculated_weapons:
		heat_rate += data.packet.charge_required * 0.03
		for k in data.packet.synergies:
			_syn_totals[k] = _syn_totals.get(k, 0.0) + data.packet.synergies[k]
			_syn_sum += data.packet.synergies[k]
	heat_ice_frac = (_syn_totals.get(EnergyPacket.SynergyType.ICE, 0.0) / _syn_sum) if _syn_sum > 0.0 else 0.0
	heat_ltg_frac = (_syn_totals.get(EnergyPacket.SynergyType.LIGHTNING, 0.0) / _syn_sum) if _syn_sum > 0.0 else 0.0
	heat_rate *= (1.0 - 2.0 * heat_ice_frac)

	# Enemies deploy mostly pre-primed (70-100% charged): a fresh squad
	# shouldn't spend its opening seconds unable to shoot, and the player
	# shouldn't get a free alpha-strike window on every spawn. Once only -
	# mid-fight grid recalcs (damage, jamming) must NOT re-fill charges.
	if not is_player and not _spawn_primed:
		_spawn_primed = true
		for data in precalculated_weapons:
			var frac = randf_range(0.7, 1.0)
			if data.get("bank_mode", "") == "bank":
				data.mount.bank_current_charge = data.packet.charge_required * frac
			else:
				data.mount.current_charge = data.packet.charge_required * frac

	is_grid_dirty = false

var _spawn_primed: bool = false

# Sums get_bank_charge()/get_bank_amplify() from every Accumulator tile
# directly hex-adjacent to `coord` within `grid` - see AccumulatorTile.gd
# and the capacitor-bank branch in the precalculated_weapons loop above.
func _get_adjacent_accumulator_bonus(grid: HexGridComponent, coord: HexCoord) -> Dictionary:
	var total_charge = 0.0
	var total_amplify = 0.0
	var worst_quality = 1.0
	for d in range(6):
		var n = coord.neighbor(d)
		if grid.has_tile(n):
			var neighbor_tile = grid.get_tile(n)
			if neighbor_tile.tile_type == "Accumulator" and neighbor_tile.has_method("get_bank_charge"):
				total_charge += neighbor_tile.get_bank_charge()
				total_amplify += neighbor_tile.get_bank_amplify()
				if neighbor_tile.has_method("get_quality_factor"):
					worst_quality = min(worst_quality, neighbor_tile.get_quality_factor())
	return {"charge": total_charge, "amplify": total_amplify, "quality": worst_quality}

func _collect_transfers(comp) -> Dictionary:
	var result = {}
	for t in comp.hex_grid.get_all_tiles():
		if t.tile_type.ends_with("Link") or t.tile_type == "Accessory Return" or t.tile_type == "Torso Return":
			if t.has_method("get_pending_transfers"):
				var transfer_pkts = t.get_pending_transfers()
				if transfer_pkts.size() > 0:
					if not result.has(t.target_slot):
						result[t.target_slot] = []
					result[t.target_slot].append_array(transfer_pkts)
	return result

func _route_to_peripheral(pkts: Array, comp):
	for pkt in pkts:
		var opp_dir = (pkt.direction + 3) % 6
		pkt.position = HexCoord.new(0, 0).neighbor(opp_dir)
		pkt.is_active = true

func _simulate_grid(grid: HexGridComponent, starting_packets: Array):
	var active_packets: Array[EnergyPacket] = []
	for pkt in starting_packets:
		if pkt.position == null:
			pkt.position = HexCoord.new(0, 0)
		pkt.traversal_steps = 0
		active_packets.append(pkt)
		
	var steps = 0
	# Max 100 routing steps to prevent infinite loops from closed circuits
	while active_packets.size() > 0 and steps < 100:
		steps += 1
		var next_packets: Array[EnergyPacket] = []
		
		for p in active_packets:
			if not p.is_active: continue
			var dir = p.direction
			var next_pos = p.position.neighbor(dir)
			
			if grid.has_tile(next_pos):
				var tile = grid.get_tile(next_pos)
				p.traversal_steps += 1
				if "sync_adjustment" in tile:
					p.traversal_steps += tile.sync_adjustment
					p.traversal_steps = max(0, p.traversal_steps)
					
				var out_pkts = tile.process_energy(p, (dir + 3) % 6, grid)
				for out in out_pkts:
					out.position = next_pos
					out.traversal_steps = p.traversal_steps
				next_packets.append_array(out_pkts)
			else:
				var comp = grid.get_parent()
				var is_valid_empty = false
				# O(1) membership check via ComponentEquipment's _valid_hex_set
				# mirror instead of a linear valid_hexes scan - this runs every
				# routing step for every packet crossing an empty hex, so on a
				# 72-100 hex Mythic component this was a real per-step cost.
				if comp and "_valid_hex_set" in comp and comp.has_method("_hex_key"):
					is_valid_empty = comp._valid_hex_set.has(comp._hex_key(next_pos.q, next_pos.r))
				elif comp and "valid_hexes" in comp:
					for h in comp.valid_hexes:
						if h.q == next_pos.q and h.r == next_pos.r:
							is_valid_empty = true
							break
							
				if is_valid_empty:
					# Pass straight through empty hex with 5% energy loss
					var pass_p = p.copy()
					pass_p.position = next_pos
					pass_p.traversal_steps += 1
					pass_p.magnitude *= 0.95
					for k in pass_p.synergies.keys():
						pass_p.synergies[k] *= 0.95
					next_packets.append(pass_p)
				else:
					# Edge bounce: reflect 180 degrees
					var bounce_p = p.copy()
					bounce_p.direction = (dir + 3) % 6
					bounce_p.position = p.position # Stay on the current tile
					bounce_p.traversal_steps = p.traversal_steps
					next_packets.append(bounce_p)
		
		var merged_packets = {}
		for p in next_packets:
			if not p.is_active: continue
			# Merge packets arriving at same tile with same direction. Packed
			# into a single int key instead of a concatenated String - this
			# runs every routing step for every active packet (up to 100
			# steps x every packet on the grid), and integer hashing/equality
			# is far cheaper than allocating+hashing a new String each time.
			# Offset is generous headroom well beyond any real mech's hex
			# grid extents, so q/r never collide even if negative.
			var key = ((p.position.q + 4096) * 8192 + (p.position.r + 4096)) * 8 + p.direction
			if merged_packets.has(key):
				merged_packets[key].merge(p)
			else:
				merged_packets[key] = p
				
		active_packets.assign(merged_packets.values())

# --- Player Sight/Detection (non-boss only) --------------------------------
# Previously every enemy just always knew exactly where the player was and
# beelined toward them forever, regardless of range or obstacles - per
# Natalia: "enemies off screen don't seem to see/acknowledge me... their
# sight should be broken by range and obstacles." SIGHT_RANGE is
# deliberately a bit past the flow field's own bounded radius (896 units,
# see MapGenerator.FLOW_FIELD_RADIUS) - "I'd like them to see a little bit
# further."
#
# Bosses are deliberately EXEMPT (is_boss check in _execute_ai_tactics below)
# - their positioning/enrage/cloak-hit-and-run behavior is already carefully
# tuned assuming constant awareness, and gating that risks breaking those
# fights for a feature that's really about rank-and-file squad members.
#
# Checked on a timer (SIGHT_CHECK_HZ), not every physics frame - a
# raycast per mech per frame across a full wave is real cost for something
# that doesn't need frame-perfect precision.
const SIGHT_RANGE = 1000.0
const SIGHT_CHECK_HZ = 3.0
# Per Natalia: lost (or never-had) sight should trigger an ONGOING search,
# not a freeze - "enemies don't seem to be searching at all... they should
# search aware of their vision." There's deliberately no give-up/idle state
# anymore: a mech without current sight is ALWAYS either searching near the
# last place it actually saw the player, or - if it's never seen them at
# all - searching around wherever it currently is (see
# _update_player_sight's first-run initialization below). "using a low
# compute search pattern" - no pathfinding calls during search, just
# straight-line moves to randomly offset points, independently per mech
# (each squad member rolls its own waypoint, so a squad doesn't all pile
# onto the exact same spot even when they share the same last-known intel).
const SEARCH_WANDER_RADIUS = 220.0
const SEARCH_WAYPOINT_INTERVAL = 1.3
# Scout role: "can go three times further, and see 1.25x further than other
# enemy units" per Natalia - wider patrol/search footprint plus modestly
# better eyesight, matching a recon archetype.
const SCOUT_SIGHT_MULT = 1.25
const SCOUT_SEARCH_MULT = 3.0

# --- Expanding Square Search (Natalia: "us coast guard search pattern...
# more aggressive and aware of line of sight") ---------------------------
# Rank-and-file squad members now run a real expanding-square (ES) sweep
# instead of hopping to random points: legs of length 1,1,2,2,3,3... units
# outward from the datum (last_known_player_pos), turning 90 degrees each
# leg - the actual USCG pattern for searching around a last-known position
# with no other intel, which guarantees full coverage of an ever-growing
# area instead of random sampling that can revisit the same spot for free.
# A fresh sighting anywhere in the squad "redatums" the pattern (restarts it
# centered on the new position), matching real SAR practice. Scouts instead
# run _execute_scout_search below - genuine frontier exploration, not a
# datum search, per "scouts optimize for seeing unseen map."
const SEARCH_LEG_UNIT = 110.0 # world units per "1" of expanding-square leg length
const SEARCH_MAX_LEG_UNITS = 8 # restart nearer the datum rather than spiral forever
const SEARCH_REDATUM_DIST = 150.0 # datum drift beyond this restarts the pattern
const _SEARCH_HEADINGS = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)] # N, E, S, W

var has_sight_of_player: bool = false
var last_known_player_pos: Vector2 = Vector2.ZERO
var _search_pos_initialized: bool = false
var _sight_check_timer: float = 0.0
var _search_waypoint: Vector2 = Vector2.ZERO
var _search_waypoint_timer: float = 0.0

var _search_pattern_initialized: bool = false
var _search_datum: Vector2 = Vector2.ZERO
var _search_leg_len_units: int = 1
var _search_legs_done_at_this_len: int = 0
var _search_heading_idx: int = 0
var _search_leg_start: Vector2 = Vector2.ZERO
var _search_leg_target: Vector2 = Vector2.ZERO

func _effective_sight_range() -> float:
	return SIGHT_RANGE * (SCOUT_SIGHT_MULT if combat_role == "scout" else 1.0)

func _effective_search_radius() -> float:
	return SEARCH_WANDER_RADIUS * (SCOUT_SEARCH_MULT if combat_role == "scout" else 1.0)

# Range + line-of-sight gate. Only updates has_sight_of_player/
# last_known_player_pos - _execute_ai_tactics decides what to actually DO
# with that state (chase vs. search).
func _update_player_sight(delta: float):
	if not _search_pos_initialized:
		# Nothing better to go on yet - search near where it woke up rather
		# than freezing until the first lucky spot.
		last_known_player_pos = global_position
		_search_pos_initialized = true

	_sight_check_timer -= delta
	if _sight_check_timer > 0.0:
		return
	_sight_check_timer = 1.0 / SIGHT_CHECK_HZ

	var dist = global_position.distance_to(target.global_position)
	var visible = false
	if dist <= _effective_sight_range():
		var space_state = get_world_2d().direct_space_state
		# Collision mask 1 = World/obstacles only (same convention as the
		# strafe-into-walls and boss-retreat-clearance raycasts elsewhere in
		# this file) - other mechs don't block sight, only terrain/obstacles.
		var query = PhysicsRayQueryParameters2D.create(global_position, target.global_position, 1)
		visible = space_state.intersect_ray(query).is_empty()

	if visible:
		_gain_sight(target.global_position)
		# Per Natalia: "if any squad member sees me the whole squad sees
		# me. BUT other squads do not get that freebie." - only broadcasts
		# to THIS mech's own squad.members, never anything global.
		_share_sight_with_squad(target.global_position)
	else:
		has_sight_of_player = false

func _gain_sight(player_pos: Vector2):
	has_sight_of_player = true
	last_known_player_pos = player_pos

func _share_sight_with_squad(player_pos: Vector2):
	if not squad or not is_instance_valid(squad):
		return
	for mate in squad.members:
		if mate == self or not is_instance_valid(mate):
			continue
		if mate.has_method("_gain_sight"):
			mate._gain_sight(player_pos)

# What a non-boss mech does while it doesn't have sight of the player -
# always ACTIVELY searching (no idle/give-up state - see the block comment
# above). Scouts run a frontier-exploration search (see
# _execute_scout_search); everyone else runs the expanding-square pattern
# (see the block comment above _SEARCH_HEADINGS). No shooting while
# searching - it doesn't know where you are, it shouldn't be able to hit you.
func _execute_search(delta: float):
	if squad and is_instance_valid(squad):
		# "Everyone in the squad knows where everyone in the squad has
		# looked" - mark the ground actually under us as covered. This is a
		# deliberately cheap stand-in for a full LOS sweep (a real
		# multi-directional raycast fan per mech per tick would be the
		# "more precise" version, but at wave-scale enemy counts that's
		# exactly the kind of per-tick physics query this session already
		# found and fixed for projectiles/homing) - standing somewhere and
		# not immediately spotting the player from here still means this
		# immediate area has been looked at.
		squad.mark_explored(global_position)

	if combat_role == "scout":
		_execute_scout_search(delta)
		return

	if not _search_pattern_initialized or _search_datum.distance_to(last_known_player_pos) > SEARCH_REDATUM_DIST:
		_start_search_pattern(last_known_player_pos)

	if global_position.distance_to(_search_leg_target) < 24.0:
		_advance_search_leg()

	# Skip legs the squad has already cleared recently rather than
	# dutifully re-walking ground a squadmate just covered - bounded
	# iteration count so a small/crowded search area can't loop forever.
	var skip_guard = 0
	while squad and is_instance_valid(squad) and squad.is_recently_explored(_search_leg_target) and skip_guard < 6:
		_advance_search_leg()
		skip_guard += 1

	var search_dir = global_position.direction_to(_search_leg_target)
	# More committed than the old passive wander (0.6x) - "more aggressive"
	# per Natalia, though still a notch under a full chase (1.0x) since it's
	# still just a hunch, not a confirmed sighting.
	velocity = search_dir * current_move_speed * speed_modifier * 0.85

# (Re)centers the expanding-square pattern on `datum` - called on first
# search and again whenever a fresh sighting moves the datum meaningfully
# ("redatum-ing", same term SAR crews use for this). Starting heading is
# randomized per mech so squadmates searching the same datum fan out in
# different initial directions instead of all walking the same spiral
# single-file.
func _start_search_pattern(datum: Vector2):
	_search_datum = datum
	_search_leg_len_units = 1
	_search_legs_done_at_this_len = 0
	_search_heading_idx = randi() % 4
	_search_leg_start = global_position
	_search_pattern_initialized = true
	_search_leg_target = _next_leg_target()

func _next_leg_target() -> Vector2:
	var heading = _SEARCH_HEADINGS[_search_heading_idx % 4]
	var length = _search_leg_len_units * SEARCH_LEG_UNIT * (SCOUT_SEARCH_MULT if combat_role == "scout" else 1.0)
	var target = _search_leg_start + heading * length

	# Line-of-sight/obstacle awareness: don't commit to a leg that just
	# marches straight into a wall - try rotating through the other 3
	# headings first (same mask-1/Env-only raycast convention as the
	# player-sight check above) before giving up and using it anyway.
	var space_state = get_world_2d().direct_space_state
	var attempts = 0
	while attempts < 3:
		var query = PhysicsRayQueryParameters2D.create(_search_leg_start, target, 1)
		if space_state.intersect_ray(query).is_empty():
			break
		attempts += 1
		heading = _SEARCH_HEADINGS[(_search_heading_idx + attempts) % 4]
		target = _search_leg_start + heading * length

	return target

# Advances to the next leg of the expanding square: turn 90 degrees, and
# every 2 legs the leg length grows by one unit (the classic 1,1,2,2,3,3...
# ES pattern). Past SEARCH_MAX_LEG_UNITS the pattern has grown too large
# without success - recenter on the same datum and start over small rather
# than spiraling toward the edge of the map forever.
func _advance_search_leg():
	_search_leg_start = _search_leg_target
	_search_heading_idx = (_search_heading_idx + 1) % 4
	_search_legs_done_at_this_len += 1
	if _search_legs_done_at_this_len >= 2:
		_search_legs_done_at_this_len = 0
		_search_leg_len_units += 1
	if _search_leg_len_units > SEARCH_MAX_LEG_UNITS:
		_start_search_pattern(_search_datum)
		return
	_search_leg_target = _next_leg_target()

# Scouts don't hunt for one specific last-known spot - per Natalia, "scouts
# optimize for seeing unseen map": push outward into whichever nearby
# direction the squad HASN'T already marked explored, continually
# expanding the squad's collective vision instead of converging on a single
# point. Genuine reconnaissance rather than a wider version of the same
# datum search everyone else runs.
func _execute_scout_search(delta: float):
	_search_waypoint_timer -= delta
	if _search_waypoint_timer <= 0.0 or global_position.distance_to(_search_waypoint) < 40.0:
		_search_waypoint_timer = SEARCH_WAYPOINT_INTERVAL * 1.5
		_search_waypoint = _pick_frontier_point()

	var search_dir = global_position.direction_to(_search_waypoint)
	velocity = search_dir * current_move_speed * speed_modifier # scouts commit fully - no caution discount

# Cheap frontier-exploration heuristic: sample a ring of candidate points
# around the scout, favor ones further out, and heavily discount any the
# squad has already covered recently - a bounded-cost stand-in for a full
# unexplored-region search that still reliably pushes toward genuinely new
# ground instead of re-treading it.
func _pick_frontier_point() -> Vector2:
	var best = Vector2.ZERO
	var best_score = -1.0
	for i in range(8):
		var ang = (TAU / 8.0) * i + randf_range(-0.3, 0.3)
		var dist = randf_range(250.0, _effective_search_radius())
		var candidate = global_position + Vector2(cos(ang), sin(ang)) * dist
		var score = dist
		if squad and is_instance_valid(squad) and squad.is_recently_explored(candidate):
			score *= 0.15
		if score > best_score:
			best_score = score
			best = candidate
	if best == Vector2.ZERO:
		best = global_position + Vector2(1, 0).rotated(randf() * TAU) * 300.0
	return best

func _execute_ai_tactics(delta):
	if not target:
		target = _get_player_ref()

	# Boss enrage/ability dispatch happens BEFORE the normal movement logic
	# below so a just-triggered teleport (blink-strike) or windup-freeze
	# (shockwave/railgun) takes effect this same frame rather than a frame
	# late. A telegraphed ability roots the boss for its windup - returning
	# early here (with velocity zeroed) is what sells "channeling."
	if is_boss:
		if _ai_state_label:
			_ai_state_label.text = "BOSS"
			_ai_state_label.modulate = Color(1.0, 0.3, 0.3)
		_update_boss_enrage()
		if boss_ability_state != "":
			_continue_boss_ability(delta)
			velocity = Vector2.ZERO
			return
		if target and is_instance_valid(target):
			boss_ability_cooldown -= delta
			if boss_ability_cooldown <= 0.0:
				_start_boss_ability()
				if boss_ability_state != "":
					velocity = Vector2.ZERO
					return

	if target:
		# Sight/detection gate - bosses are exempt (see the block comment
		# above _execute_search) and always fall straight through.
		if not is_boss:
			_update_player_sight(delta)
			if _ai_state_label:
				_ai_state_label.text = "CHASE" if has_sight_of_player else "SEARCH"
				_ai_state_label.modulate = Color(0.3, 1.0, 0.3) if has_sight_of_player else Color(1.0, 0.6, 0.2)
			if not has_sight_of_player:
				_execute_search(delta)
				return

		var dist = global_position.distance_to(target.global_position)
		var dir = global_position.direction_to(target.global_position)

		# Cloak hit-and-run takes priority over position_style for any boss
		# that actually has a Cloak Generator equipped (regardless of
		# archetype/ability_pool) - "liberally use the cloak" per design,
		# not just the one-shot Specter blink-strike ability.
		if is_boss and _boss_hit_and_run(delta, dist, dir):
			return

		# Boss position_style ("kiter"/"circler") takes over movement
		# entirely when it applies; "aggressive" (and every non-boss mech)
		# falls through to the shared approach/orbit logic below, unchanged.
		if is_boss and _boss_reposition(delta, dist, dir):
			return

		# Movement direction toward the target now comes from the shared
		# MapGenerator flow field (one BFS shared across every enemy,
		# refreshed on its own timer) instead of this mech running its own
		# independent AStarGrid2D.get_id_path() search every ~0.5-0.7s - see
		# MapGenerator.get_flow_direction()/_rebuild_flow_field() for why:
		# up to 80 concurrent full-grid A* searches on a 400x250 grid was the
		# actual algorithmic cost, not just something to call less often.
		# get_flow_direction() itself falls back to a straight line when this
		# mech is outside the field's bounded radius, so there's no separate
		# "no path found" branch needed here anymore.
		var path_dir = dir
		# Amphibious mechs deliberately skip the shared flow field - it's
		# built with every water tile marked solid (see MapGenerator.
		# _build_navigation), so it would route a water-capable mech around
		# lakes/rivers exactly like every other mech, wasting the whole
		# point of the trait. Straight-line steering is the correct
		# "ignore terrain that isn't actually an obstacle for me" behavior.
		if not is_amphibious:
			var map = _get_map_ref()
			if map and map.has_method("get_flow_direction"):
				path_dir = map.get_flow_direction(global_position, target.global_position)

		if dist > engagement_distance:
			# Approach full speed
			velocity = path_dir * current_move_speed * speed_modifier
		else:
			# Reached engagement distance, strafe/orbit at half speed
			var tangent = Vector2(-dir.y, dir.x) * rotational_direction
			# Raycast to prevent strafing into walls
			var space_state = get_world_2d().direct_space_state
			var query = PhysicsRayQueryParameters2D.create(global_position, global_position + tangent * 50.0, 1)
			if space_state.intersect_ray(query):
				rotational_direction *= -1 # Reverse orbit
				tangent = Vector2(-dir.y, dir.x) * rotational_direction

			velocity = tangent * current_move_speed * (speed_modifier * 0.5)

		# Separation nudge - see the field comment above for why this exists.
		# Re-queried on its own throttle (not every tick - same perf pattern
		# as the projectile homing/vortex throttling elsewhere) but blended
		# into velocity every frame so it stays smooth rather than snapping.
		if not is_boss:
			_separation_query_timer -= delta
			if _separation_query_timer <= 0.0:
				_separation_query_timer = SEPARATION_QUERY_INTERVAL
				_cached_separation = _compute_separation()
			if _cached_separation != Vector2.ZERO:
				velocity += _cached_separation * current_move_speed * SEPARATION_WEIGHT

		# AI combat shooting (out of range = hold charge, same as the player)
		if dist < engagement_distance + 150.0:
			_shoot(target.global_position, true, true, delta)

# Cheap "push away from nearby same-side neighbors" query, throttled via
# _separation_query_timer above rather than run every physics tick - a
# PhysicsShapeQueryParameters2D.intersect_shape() call per enemy per tick is
# exactly the kind of cost this session already found and fixed for
# projectiles (see Projectile.gd's HOMING_QUERY_INTERVAL). Masked to the
# Enemy layer only, so this never pushes a mech away from the player it's
# actually trying to reach.
func _compute_separation() -> Vector2:
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = SEPARATION_RADIUS
	query.shape = shape
	query.transform = global_transform
	query.collision_mask = 4 # Enemy layer only
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var results = space_state.intersect_shape(query, 8)
	var push = Vector2.ZERO
	var count = 0
	for res in results:
		var col = res["collider"]
		if col == self:
			continue
		var away = global_position - col.global_position
		var d = away.length()
		if d > 0.001 and d < SEPARATION_RADIUS:
			push += away.normalized() * (1.0 - d / SEPARATION_RADIUS)
			count += 1
	if count > 0:
		push /= count
	return push

# Falls back to the pre-profile hardcoded rule (sniper/jammer kite,
# everything else aggressive) for a profile-less boss, e.g. one spawned
# directly from the debug menu without going through Main._spawn_boss.
func _get_position_style() -> String:
	if boss_profile and boss_profile.position_style != "":
		return boss_profile.position_style
	if combat_role == "sniper" or combat_role == "jammer":
		return "kiter"
	return "aggressive"

# Returns true if it fully handled movement+shooting this frame (caller
# skips the shared approach/orbit logic below in that case). "aggressive"
# (and every non-boss mech) always returns false and falls through to that
# shared logic, unchanged from before position styles existed.
func _boss_reposition(delta: float, dist: float, dir: Vector2) -> bool:
	var style = _get_position_style()

	if style == "kiter" and dist < engagement_distance * 0.6:
		# Backs off when the player closes to melee range instead of
		# orbiting in place at whatever (now too close) distance -
		# otherwise a kiter just stands there tanking hits like a Brawler
		# once you're in its face.
		var retreat_dir = _boss_pick_retreat_dir(dir)
		velocity = retreat_dir * current_move_speed * speed_modifier
		if dist < engagement_distance + 150.0:
			_shoot(target.global_position, true, true, delta)
		return true

	if style == "circler":
		# Continuously strafes around the target while smoothly correcting
		# back toward its preferred engagement_distance band, instead of
		# the binary "approach until in range, then orbit" default - reads
		# as constantly repositioning rather than beelining in and parking.
		var radius_error = dist - engagement_distance
		var tangent = Vector2(-dir.y, dir.x) * rotational_direction
		var radial = dir * clamp(radius_error / 100.0, -1.0, 1.0)
		var move_dir = tangent + radial
		move_dir = move_dir.normalized() if move_dir.length() > 0.01 else tangent
		velocity = move_dir * current_move_speed * speed_modifier * 0.8
		if dist < engagement_distance + 150.0:
			_shoot(target.global_position, true, true, delta)
		return true

	return false

# Smarter-than-straight-back retreat: samples several candidate angles off
# directly-away-from-target and raycasts each, picking whichever has the
# most open space before hitting something - so a kiting boss backs into
# open ground instead of blindly reversing into whatever's directly behind
# it (a wall, a corner, another obstacle).
func _boss_pick_retreat_dir(dir: Vector2) -> Vector2:
	var space_state = get_world_2d().direct_space_state
	var candidate_offsets_deg = [0.0, 25.0, -25.0, 50.0, -50.0]
	var probe_dist = 150.0
	var best_dir = -dir
	var best_clearance = -1.0
	for deg in candidate_offsets_deg:
		var candidate = (-dir).rotated(deg_to_rad(deg))
		var query = PhysicsRayQueryParameters2D.create(global_position, global_position + candidate * probe_dist, 1)
		var result = space_state.intersect_ray(query)
		var clearance = probe_dist if result.is_empty() else global_position.distance_to(result.position)
		if clearance > best_clearance:
			best_clearance = clearance
			best_dir = candidate
	return best_dir

# --- Boss Cloak Hit-and-Run ------------------------------------------------
# Any boss with a Cloak Generator equipped (has_cloak_generator - whichever
# role rolled it, not just an ambusher-based Specter) cycles advance ->
# strike -> retreat -> advance instead of the plain per-mech cloak AI's
# one-shot "stay hidden while closing, reveal once close, then stay
# revealed" behavior. This is what makes cloak usage read as deliberate
# hit-and-run rather than a single ambush per fight.
#
# It doesn't fight _update_cloak's own is_cloaked bookkeeping - it just
# controls MOVEMENT so the boss's distance from the player naturally walks
# through _update_cloak's existing thresholds (wants_cloak = dist >
# engagement_distance*0.9) at the right times: cloaked while advancing,
# revealed by firing during the strike (which is what _shoot's
# _get_ambush_multiplier() check turns into the 2.5x ambush bonus, both for
# that shot and for anything else landed within the following 0.25s window),
# then forced back out past the recloak threshold during retreat.
var _hitrun_phase: String = "advance"
var _hitrun_timer: float = 0.0
const HITRUN_STRIKE_DURATION = 0.4

func _boss_hit_and_run(delta: float, dist: float, dir: Vector2) -> bool:
	if not has_cloak_generator:
		return false
	match _hitrun_phase:
		"advance":
			velocity = dir * current_move_speed * speed_modifier
			if dist <= engagement_distance * 0.7:
				_hitrun_phase = "strike"
				_hitrun_timer = HITRUN_STRIKE_DURATION
		"strike":
			velocity = Vector2.ZERO
			if dist < engagement_distance + 150.0:
				_shoot(target.global_position, true, true, delta)
			_hitrun_timer -= delta
			if _hitrun_timer <= 0.0:
				_hitrun_phase = "retreat"
		"retreat":
			var retreat_dir = _boss_pick_retreat_dir(dir)
			velocity = retreat_dir * current_move_speed * speed_modifier
			if dist > engagement_distance * 1.3:
				_hitrun_phase = "advance"
		_:
			_hitrun_phase = "advance"
	return true

var elemental_resistances: Dictionary = {}

# Shared shield-mitigation step used by both apply_damage() and
# apply_part_damage() (previously duplicated verbatim in both - a fix to
# one would silently desync from the other). Mutates shield_hp directly and
# returns the amount of damage that should still be applied to HP/parts
# (0.0 if the shield fully absorbed the hit).
func _apply_shield_mitigation(amount: float, element: String) -> float:
	if shield_hp <= 0 or amount <= 0:
		return amount

	# RPG Shield Logic
	if element == "LIGHTNING":
		amount *= 1.5 # Base 1.5x against any shield

	var shield_str = ""
	var syn_id = 0
	if typeof(dominant_shield_synergy) == TYPE_INT:
		syn_id = dominant_shield_synergy
	elif typeof(dominant_shield_synergy) == TYPE_STRING and dominant_shield_synergy != "":
		syn_id = int(dominant_shield_synergy)

	if syn_id == 1: shield_str = "FIRE"
	elif syn_id == 2: shield_str = "ICE"
	elif syn_id == 3: shield_str = "POISON"
	elif syn_id == 4: shield_str = "LIGHTNING"
	elif syn_id == 5: shield_str = "VORTEX"
	elif syn_id == 6: shield_str = "VAMPIRIC"

	if shield_str != "":
		if element == "FIRE" and shield_str == "ICE": amount *= 2.0
		elif element == "ICE" and shield_str == "FIRE": amount *= 2.0
		elif element == "POISON" and shield_str == "VAMPIRIC": amount *= 2.0
		elif element == "VAMPIRIC" and shield_str == "POISON": amount *= 2.0
		elif element == "KINETIC" and shield_str == "LIGHTNING": amount *= 2.0
		elif element == "LIGHTNING" and shield_str == "KINETIC": amount *= 2.0
		elif element == "VORTEX" and shield_str == "KINETIC": amount *= 2.0

	# MYTHIC Shield - Aegis: a hard per-hit damage cap while shields hold,
	# turning big alpha-strikes into a multi-hit whittling fight instead.
	# Pure tank/absorb - no offensive payoff, unlike Deflector below.
	if shield_mythic_mode == 0 and max_shield_hp > 0:
		amount = min(amount, max_shield_hp * AEGIS_HIT_CAP_RATIO)

	shield_hp -= amount
	if shield_hp < 0:
		var overflow = -shield_hp
		shield_hp = 0
		# MYTHIC Shield - Deflector: "very effective defense tool if used
		# properly" per Natalia - overflow that would otherwise bleed
		# through to HP instead gets ejected as an offensive burst in a
		# random direction, fully absorbing the hit (no HP damage taken)
		# at the cost of not being an AIMED counterattack.
		if shield_mythic_mode == 1:
			_deflect_overflow(overflow)
			return 0.0
		return overflow
	return 0.0 # Shields absorbed all damage

const AEGIS_HIT_CAP_RATIO = 0.15 # Aegis: no single hit can exceed 15% of max shield HP
const DEFLECTOR_BURST_RADIUS = 220.0

# Ejects `amount` of absorbed overflow energy as a random-direction AoE
# burst - reuses the same PhysicsShapeQueryParameters2D/intersect_shape
# pattern Projectile._trigger_biome_explosion already uses for its own AoE
# hits, rather than inventing a second implementation of "damage everyone
# in a radius."
func _deflect_overflow(amount: float):
	var burst_dir = Vector2.RIGHT.rotated(randf() * TAU)
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = DEFLECTOR_BURST_RADIUS
	query.shape = shape
	query.transform = Transform2D(0.0, global_position + burst_dir * (DEFLECTOR_BURST_RADIUS * 0.5))
	query.collision_mask = 4 | 8 # enemy + player layers, same convention as OilSlickHazard._tick_damage
	var results = space_state.intersect_shape(query)
	for res in results:
		var col = res["collider"]
		if col != self and col.has_method("apply_damage"):
			col.apply_damage(amount, "RAW")
	if get_parent():
		var ring = load("res://scripts/visuals/BossTelegraphRing.gd").new()
		get_parent().add_child(ring)
		ring.global_position = global_position + burst_dir * (DEFLECTOR_BURST_RADIUS * 0.5)
		ring.burst(15.0, DEFLECTOR_BURST_RADIUS, 0.2, Color(0.3, 0.6, 1.0, 1.0))

# Flat per-hit chance, same for everyone - deliberately simple/predictable
# rather than scaling with PIERCE stacking, per Natalia's call. Easy for a
# player to learn ("pierce hits sometimes just end the fight") and easy for
# the existing AI counter-pressure (SquadDirector.player_kill_methods /
# _apply_kill_method_counter_pressure) to detect and counter if the player
# leans on it too hard.
const PIERCE_EXECUTION_CHANCE = 0.04

# Locked exemption list (FEATURE_ROADMAP.md Decision Log): bosses,
# Commanders, Piercing Jammers, and anyone standing in a Piercing Jammer's
# aura are immune to the instant-execution roll above. PiercingJammerMech
# (scripts/entities/PiercingJammerMech.gd) adds itself to the
# "piercing_jammer_aura" group on _ready(); the aura check below is a plain
# distance test against every live one, done only at execution-roll time
# (a PIERCE hit that got past shields) rather than every frame - this is a
# rare event, so an O(k) scan over however many piercing jammers are alive
# is cheap and avoids any per-frame cached-flag sync complexity.
func _is_pierce_execution_exempt() -> bool:
	if is_boss:
		return true
	if combat_role == "commander" or combat_role == "piercing_jammer":
		return true
	for pj in get_tree().get_nodes_in_group("piercing_jammer_aura"):
		# Only PiercingJammerMech instances ever join this group, so
		# PIERCE_AURA_RADIUS (one of its own script constants) is always
		# present - no membership guard needed beyond instance validity.
		if is_instance_valid(pj) and global_position.distance_to(pj.global_position) <= pj.PIERCE_AURA_RADIUS:
			return true
	return false

func apply_damage(amount: float, element: String = "RAW", source: Node = null):
	if elemental_resistances.has(element):
		amount *= elemental_resistances[element]

	# PIERCE "rent" status: torn armor takes +20% from everything while
	# the rend lasts (applied to damage only, never to heals).
	if amount > 0 and status_effects.has("rent"):
		amount *= 1.2

	# Balanced-school Mythic Actuator: a brief post-ram "brace" window
	# (see _process_ramming) shaves incoming damage - the utility half of
	# that school's flavor, on top of the extra ram knockback it also gets.
	if amount > 0 and _brace_timer > 0.0:
		amount *= 0.75

	if not is_player:
		var main = get_tree().current_scene
		# SquadDirector lives under Main.world (the pixel-viewport game
		# world), not directly under Main itself - see Main.gd's
		# _setup_pixel_viewport() for why.
		if main and "world" in main and main.world and main.world.has_node("SquadDirector"):
			main.world.get_node("SquadDirector").log_player_damage(amount, element)

	if amount > 0:
		time_since_last_hit = 0.0
		_break_cloak()
		# Remember what element is currently hurting us - if this hit kills
		# us, die() reports it to the director as the kill method
		# (feeds pierce-overuse counter-pressure, see SquadDirector).
		last_damage_element = element

	amount = _apply_shield_mitigation(amount, element)
	# NOTE: this used to be `if amount <= 0: return`, which was correct for
	# "shields fully absorbed a positive hit" (mitigation returns exactly
	# 0.0 for that case) but ALSO silently swallowed every heal - a heal
	# comes in as a negative amount, passes through mitigation unchanged
	# (shields don't interact with negative amounts), and a negative number
	# is always <= 0, so every single heal (Vampiric lifesteal, Heal
	# Beacon's self-heal path if it's ever routed through here, etc.) was
	# quietly doing nothing. Only an EXACT zero means "shields absorbed it
	# all, nothing left to apply" - that's the only case that should bail.
	if amount == 0.0:
		return

	if is_player and amount > 0:
		_log_incoming_damage(amount, element, source)

	# Piercing "cut in half" execution: a low flat chance for any PIERCE hit
	# that actually gets past shields to instantly finish the target,
	# regardless of remaining HP. Locked exemption list per
	# FEATURE_ROADMAP.md's Decision Log - see _is_pierce_execution_exempt().
	if element == "PIERCE" and not _is_pierce_execution_exempt():
		if randf() < PIERCE_EXECUTION_CHANCE:
			_show_floating_text("EXECUTED", Color(1.0, 0.15, 0.15))
			hp = 0
			die()
			return

	if amount < 0:
		_show_floating_text("+%d" % int(round(-amount)), Color(0.3, 1.0, 0.4))
	elif amount >= 1.0:
		# Skip tiny continuous-tick damage (burning ticks ~0.08/frame) so
		# the display doesn't turn into a wall of flickering micro-numbers.
		_show_floating_text(str(int(round(amount))), Color(1.0, 0.9, 0.3) if is_player else Color(1.0, 1.0, 1.0))

	hp -= amount
	if hp <= 0:
		die()

# Appends one entry to recent_damage_log and prunes anything older than
# DEATH_LOG_LOOKBACK_SEC (plus a hard size cap as a defensive backstop) -
# see the field's own comment for what reads this. amount here is already
# post-mitigation (the real damage that got through shields), which is the
# number that actually matters for "what killed me."
func _log_incoming_damage(amount: float, element: String, source: Node):
	# Label captured now, not resolved later off the source node - by the
	# time a death report gets built the attacker may already be gone
	# (queue_free'd, or the whole wave torn down). "Rival <name>" takes
	# priority over "Boss" over plain role, matching how those are already
	# surfaced elsewhere (see Main.gd's RIVAL floating text / rival_name meta).
	var label = "Environment"
	if source and is_instance_valid(source):
		if source.has_meta("rival_name"):
			label = "Rival " + str(source.get_meta("rival_name"))
		elif "is_boss" in source and source.is_boss:
			label = "Boss"
		elif "combat_role" in source and source.combat_role != "":
			label = source.combat_role.capitalize()

	var now = Time.get_ticks_msec() / 1000.0
	var entry = {
		"label": label,
		"element": element,
		"amount": amount,
		"time": now,
	}
	recent_damage_log.append(entry)

	var cutoff = now - DEATH_LOG_LOOKBACK_SEC
	while recent_damage_log.size() > 0 and recent_damage_log[0]["time"] < cutoff:
		recent_damage_log.pop_front()
	while recent_damage_log.size() > 200:
		recent_damage_log.pop_front()

# Shared floating-text popup for damage/heal numbers - used from here and
# from _emit_heal_pulse() (which sets hp directly and bypasses this
# function entirely, so it calls this separately).
func _show_floating_text(text: String, color: Color):
	var parent = get_parent()
	if not parent:
		return
	var lbl = Label.new()
	lbl.text = text
	lbl.modulate = color
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.z_index = 90
	lbl.global_position = global_position + Vector2(randf_range(-12, 12), -30)
	parent.add_child(lbl)
	var tw = lbl.create_tween()
	tw.tween_property(lbl, "global_position", lbl.global_position + Vector2(randf_range(-6, 6), -40), 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.7).set_ease(Tween.EASE_IN)
	tw.tween_callback(lbl.queue_free)

func apply_part_damage(slot: int, amount: float, element: String = "RAW"):
	amount = _apply_shield_mitigation(amount, element)
	if amount <= 0:
		return # Shields absorbed all part damage - nothing got through to roll a disable either

	if not components.has(slot): return
	var comp = components[slot]

	# Apply damage to a random tile in that component's grid - still not
	# picky about exactly where the structural HP damage lands.
	var tiles = comp.hex_grid.get_all_tiles()
	if tiles.size() > 0:
		var hit_tile = tiles[randi() % tiles.size()]
		hit_tile.take_damage(amount)
		# Any hit that actually reached the component (shields didn't fully
		# absorb it) also gets a separate shot at knocking a tile offline,
		# independent of that specific tile's own HP pool - see
		# _roll_component_disable for the priority/severity math.
		_roll_component_disable(comp, amount, element)

	# Apply a small fraction of locational damage to global structure HP
	apply_damage(amount * 0.2, element)

# Per-Natalia's design: a hit that gets past shields (or punches through as
# PIERCE - "armor pierced") rolls a % chance to disable/reboot a tile in the
# component, independent of the random direct-damage tile above. The roll
# targets whichever tile in the component is highest-priority right now:
# Splitters first, then Reflector/Resonator/Amplifier, then anything else at
# low risk (see HexTile.get_disable_risk). Weak chip damage against a
# low-risk tile can land a chance so far under DISABLE_MIN_CHANCE that it
# never rolls at all - "may never be disabled" is an intended outcome, not
# missing tuning. A single hit severe enough (see GRAVE_HIT_RATIO) fries the
# tile outright instead of just knocking it into a timed reboot.
const DISABLE_BASE_CHANCE = 0.14
const DISABLE_MIN_CHANCE = 0.02
const DISABLE_PIERCE_BONUS = 1.6
const GRAVE_HIT_RATIO = 1.75

func _roll_component_disable(comp, amount: float, element: String):
	var target = _find_disable_priority_tile(comp)
	if not target:
		return

	var severity = amount / max(1.0, target.max_hp)
	var pierce_bonus = DISABLE_PIERCE_BONUS if element == "PIERCE" else 1.0
	var chance = DISABLE_BASE_CHANCE * severity * pierce_bonus * target.get_disable_risk()
	if chance < DISABLE_MIN_CHANCE:
		return # too weak a hit on too low-priority a tile - never disables from this one

	if randf() >= chance:
		return

	target.hp = 0
	target.is_disabled = true
	if severity * pierce_bonus >= GRAVE_HIT_RATIO:
		# Catastrophic overkill - the tile is fried, not just knocked
		# offline. No self-recovery timer; only a Garage repair fixes it.
		target.power_lost = true
		_show_floating_text(target.tile_type + " DESTROYED", Color(1.0, 0.2, 0.2))
	else:
		var base_cooldown = 3.0
		target.disable_timer = base_cooldown + (target.times_disabled * 2.0)
		target.times_disabled += 1
		_show_floating_text(target.tile_type + " OFFLINE", Color(1.0, 0.7, 0.2))

# Priority search for the disable roll's target - independent of which tile
# happened to take the direct structural damage in apply_part_damage above.
func _find_disable_priority_tile(comp):
	var tiles = comp.hex_grid.get_all_tiles()
	if tiles.is_empty():
		return null

	var splitters: Array = []
	var secondary: Array = []
	var other: Array = []
	for t in tiles:
		if t.is_disabled or t.power_lost:
			continue
		if t.tile_type == "Splitter":
			splitters.append(t)
		elif t.tile_type in ["Reflector", "Resonator", "Amplifier"]:
			secondary.append(t)
		else:
			other.append(t)

	if not splitters.is_empty():
		return splitters.pick_random()
	if not secondary.is_empty():
		return secondary.pick_random()
	if not other.is_empty():
		return other.pick_random()
	return null

func apply_status(effect_name: String, duration: float):
	status_effects[effect_name] = duration

# Melee/mass physics pillar: heavier loadouts move slower, lighter ones get
# a mild bonus - intentionally rebalances the Kinetic "Speed Demon" builds
# the README used to flag as dominant (per FEATURE_ROADMAP.md). First-pass
# numbers, not measured against real playtesting: a ~60-mass loadout (a
# fairly average spread of tiles across all 6 slots) is speed-neutral, and
# the multiplier is capped both ways so no build becomes unplayable or
# absurdly fast just from mass alone.
const MASS_BASELINE = 60.0
const MASS_SPEED_COEFF = 0.0025
const MASS_SPEED_MIN_MULT = 0.6
const MASS_SPEED_MAX_MULT = 1.25

func _get_mass_speed_mult() -> float:
	return clamp(1.0 - (total_mass - MASS_BASELINE) * MASS_SPEED_COEFF, MASS_SPEED_MIN_MULT, MASS_SPEED_MAX_MULT)

func update_status_effects(delta: float):
	current_move_speed = base_move_speed * _get_mass_speed_mult()
	if is_amphibious and _in_water:
		current_move_speed *= AMPHIBIOUS_WATER_SPEED_MULT

	# Mythic Actuator "school" flavor - see ActuatorTile.gd/_process_ramming.
	# Velocity trades ram damage for extra speed; Ember trades speed for
	# harder/fire-tagged rams; Balanced sits in the middle and gets its
	# utility perk (knockback + brace window) purely on the ramming side.
	if actuator_school == 0: # Velocity
		current_move_speed *= 1.15
	elif actuator_school == 1: # Ember
		current_move_speed *= 0.9

	if _brace_timer > 0.0:
		_brace_timer -= delta

	var effects_to_remove = []
	for effect in status_effects:
		status_effects[effect] -= delta

		# Handle active effects - full elemental status suite (group 3).
		# Movement effects multiply onto current_move_speed (which was just
		# reset to base above), damage effects tick per second.
		if effect == "frozen":
			current_move_speed = base_move_speed * 0.4 # 60% slow
		elif effect == "burning":
			apply_damage(5.0 * delta) # 5 damage per second
		elif effect == "poisoned":
			apply_damage(4.0 * delta)
			current_move_speed *= 0.8
		elif effect == "bleeding":
			apply_damage(6.0 * delta)
		elif effect == "paralyzed":
			current_move_speed = 0.0 # LIGHTNING lockup
		elif effect == "immobilized":
			current_move_speed = 0.0 # heavy VAMPIRIC pin
		elif effect == "staggered":
			current_move_speed *= 0.5
		elif effect == "concussed":
			current_move_speed *= 0.1
		elif effect == "vortexed":
			# Dragged toward the impact point stored by the projectile
			pull_towards(vortex_drag_point, delta, 500.0)
		# ("rent" has no per-frame effect - it's consumed as a +20% damage
		# amplifier inside apply_damage.)

		# Check if expired
		if status_effects[effect] <= 0:
			effects_to_remove.append(effect)

	for effect in effects_to_remove:
		status_effects.erase(effect)

	if is_cloaked:
		current_move_speed *= 1.25 # Sneaking in fast while unseen

	if _ambush_window_timer > 0.0:
		_ambush_window_timer = max(0.0, _ambush_window_timer - delta)

	# Overlord boss ability ("Rally") - temporary speed buff on top of the
	# self-heal/shield-refresh it grants (see _do_rally). Ticked here so it
	# decays like every other timed status effect above instead of needing
	# its own timer loop.
	if _rally_speed_timer > 0.0:
		_rally_speed_timer -= delta
		current_move_speed *= RALLY_SPEED_MULT

	if not jammed_synergies.is_empty():
		var synergies_to_clear = []
		for syn_id in jammed_synergies:
			jammed_synergies[syn_id] -= delta
			if jammed_synergies[syn_id] <= 0:
				synergies_to_clear.append(syn_id)
		for syn_id in synergies_to_clear:
			jammed_synergies.erase(syn_id)

# --- Cloak -------------------------------------------------------------

func _update_cloak(delta: float):
	if not has_cloak_generator:
		if is_cloaked or modulate.a < 1.0:
			is_cloaked = false
			modulate.a = 1.0
		return

	time_since_cloak_break += delta

	if is_cloaked:
		cloak_charge = max(0.0, cloak_charge - cloak_drain_rate * delta)
		if cloak_charge <= 0.0:
			_break_cloak()
	elif time_since_cloak_break >= cloak_recharge_delay:
		cloak_charge = min(max_cloak_charge, cloak_charge + cloak_recharge_rate * delta)

		var wants_cloak = false
		if is_player:
			wants_cloak = InputMap.has_action("cloak") and Input.is_action_pressed("cloak")
		elif target:
			# Ambush AI: stay cloaked while closing in, reveal once at striking range
			wants_cloak = global_position.distance_to(target.global_position) > engagement_distance * 0.9

		if wants_cloak and cloak_charge >= max_cloak_charge * 0.3:
			is_cloaked = true

	var target_alpha = 0.3 if is_cloaked else 1.0
	# Was 8.0 - converged in under half a second, way too snappy for a
	# "cloak" to read as anything more than a quick flicker. This is a
	# genuinely slow fade now (~2-2.5s to fully settle).
	modulate.a = lerp(modulate.a, target_alpha, 1.2 * delta)

	# The "big distorted circle" visual: a heat-haze shimmer bubble around
	# the cloaked mech (screen-UV displacement shader). Fades in/out with
	# the cloak. Doubles as the ambusher counterplay tell - a player who
	# learns the shimmer can spot an incoming cloaked ambusher.
	_update_cloak_distortion(delta)

const CLOAK_DISTORTION_RADIUS = 80.0
const CLOAK_SHADER_CODE = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float dist = length(centered) * 2.0;
	// 1.0 at the middle, 0 at the rim - the bubble has a soft edge
	float mask = smoothstep(1.0, 0.55, dist);
	// Wobbling ripple rings drifting through the bubble
	float ripple = sin(dist * 22.0 - TIME * 4.0) + sin(centered.x * 18.0 + TIME * 2.3);
	vec2 dir = dist > 0.001 ? centered / dist : vec2(0.0);
	vec2 offset = dir * ripple * 0.012 * strength * mask;
	vec4 scene = texture(screen_tex, SCREEN_UV + offset);
	// Slight cool tint so the bubble reads even over flat terrain
	scene.rgb = mix(scene.rgb, scene.rgb * vec3(0.92, 0.97, 1.05), mask * strength);
	COLOR = vec4(scene.rgb, mask * min(1.0, strength * 3.0));
}"""

var _cloak_distortion: ColorRect = null
var _cloak_distortion_strength: float = 0.0

func _ensure_cloak_distortion():
	if _cloak_distortion and is_instance_valid(_cloak_distortion):
		return
	if not get_parent():
		return
	_cloak_distortion = ColorRect.new()
	_cloak_distortion.size = Vector2.ONE * CLOAK_DISTORTION_RADIUS * 2.0
	_cloak_distortion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh = Shader.new()
	sh.code = CLOAK_SHADER_CODE
	var mat = ShaderMaterial.new()
	mat.shader = sh
	_cloak_distortion.material = mat
	# Sibling of the mech, NOT a child: children inherit modulate, so a
	# child bubble would fade out with the cloaking mech - i.e. disappear
	# exactly when it's supposed to be the only visible tell. As a sibling
	# it keeps full opacity and just follows the mech's position.
	get_parent().add_child(_cloak_distortion)
	tree_exiting.connect(func():
		if _cloak_distortion and is_instance_valid(_cloak_distortion):
			_cloak_distortion.queue_free()
	)

func _update_cloak_distortion(delta: float):
	var target = 1.0 if is_cloaked else 0.0
	_cloak_distortion_strength = lerp(_cloak_distortion_strength, target, 1.2 * delta)

	if _cloak_distortion_strength < 0.02:
		if _cloak_distortion and is_instance_valid(_cloak_distortion):
			_cloak_distortion.visible = false
		return

	_ensure_cloak_distortion()
	if not _cloak_distortion:
		return
	_cloak_distortion.visible = true
	_cloak_distortion.global_position = global_position - _cloak_distortion.size / 2.0
	_cloak_distortion.material.set_shader_parameter("strength", _cloak_distortion_strength)

func _break_cloak():
	if not is_cloaked:
		return
	is_cloaked = false
	time_since_cloak_break = 0.0
	_ambush_window_timer = AMBUSH_WINDOW_DURATION

# Ambush multiplier for whatever damage is about to be dealt. True while
# still cloaked (covers the shot that's actively breaking cloak this call)
# OR while the post-decloak window is running (covers everything else within
# AMBUSH_WINDOW_DURATION seconds of any decloak, regardless of cause - see
# _break_cloak). Ticked down in update_status_effects().
func _get_ambush_multiplier() -> float:
	if is_cloaked or _ambush_window_timer > 0.0:
		return AMBUSH_MULTIPLIER
	return 1.0

# --- Jammer Module (equippable pulse ability) --------------------------

func _update_jammer_module(delta: float):
	if not has_jammer_module:
		return
	jammer_pulse_timer -= delta
	if jammer_pulse_timer <= 0.0:
		jammer_pulse_timer = jammer_pulse_interval
		_emit_jammer_pulse()

func _emit_jammer_pulse():
	var p = _get_player_ref()
	if not p:
		return
	if global_position.distance_to(p.global_position) <= jammer_pulse_radius:
		if jammer_mode == 0:
			if p.has_method("apply_vision_jam"):
				p.apply_vision_jam(jammer_effect_duration)
		else:
			if p.has_method("apply_synergy_jam"):
				p.apply_synergy_jam(jammer_target_synergy, jammer_effect_duration)

	var visual_class = load("res://scripts/attacks/PulseRingVisual.gd")
	if visual_class:
		var v = visual_class.new()
		v.global_position = global_position
		v.setup(jammer_pulse_radius, Color(0.6, 0.15, 0.85, 1.0))
		if get_parent():
			get_parent().add_child(v)

func apply_vision_jam(duration: float):
	if is_player:
		vision_jammed.emit(duration)

func apply_synergy_jam(synergy_id: int, duration: float):
	jammed_synergies[synergy_id] = max(jammed_synergies.get(synergy_id, 0.0), duration)

# Mutes any jammed synergy's contribution to an outgoing packet. Called once
# per actual shot fired, right before the packet leaves the mech.
func _apply_synergy_jamming(packet: EnergyPacket):
	if jammed_synergies.is_empty():
		return
	for syn_id in jammed_synergies:
		if packet.synergies.has(syn_id):
			var suppressed = packet.synergies[syn_id] * 0.9
			packet.magnitude = max(0.0, packet.magnitude - suppressed)
			packet.synergies[syn_id] *= 0.1

# --- Heal Beacon (Support ability) --------------------------------------

func _update_healer(delta: float):
	if not has_healer or is_player:
		return
	heal_pulse_timer -= delta
	if heal_pulse_timer <= 0.0:
		heal_pulse_timer = heal_pulse_interval
		_emit_heal_pulse()

func _emit_heal_pulse():
	var allies = get_tree().get_nodes_in_group("enemy")
	for ally in allies:
		if ally == self or not is_instance_valid(ally) or not ("hp" in ally):
			continue
		if global_position.distance_to(ally.global_position) > heal_pulse_radius:
			continue
		var healed = min(ally.max_hp, ally.hp + heal_pulse_power) - ally.hp
		ally.hp += healed
		if healed >= 1.0 and ally.has_method("_show_floating_text"):
			ally._show_floating_text("+%d" % int(round(healed)), Color(0.3, 1.0, 0.4))

	var self_healed = min(max_hp, hp + heal_pulse_power * 0.5) - hp
	hp += self_healed
	if self_healed >= 1.0:
		_show_floating_text("+%d" % int(round(self_healed)), Color(0.3, 1.0, 0.4))

	var visual_class = load("res://scripts/attacks/PulseRingVisual.gd")
	if visual_class:
		var v = visual_class.new()
		v.global_position = global_position
		v.setup(heal_pulse_radius, Color(0.2, 0.9, 0.5, 1.0))
		if get_parent():
			get_parent().add_child(v)

# --- Boss Fitness Tracking ------------------------------------------------
# Same fitness shape as Squad.gd's fitness inputs (damage dealt + hits
# landed + capped survival-since-first-engagement - flee penalty), just
# scoped to a single mech instead of a multi-member squad, since a boss
# fight is effectively "a squad of one." Feeds BossProfile.update_fitness
# via Main._on_boss_died -> SquadDirector._on_boss_defeated, which is what
# makes boss profiles evolve instead of just being 6 static archetypes.
var _boss_time_alive: float = 0.0
var _boss_hits_landed: int = 0
var _boss_damage_dealt: float = 0.0
var _boss_first_engagement: float = -1.0
var _boss_time_since_hit: float = 0.0
var _boss_flee_penalty: float = 0.0
const BOSS_FLEE_GRACE: float = 5.0
const BOSS_FLEE_RATE: float = 1.5

# Connected unconditionally in _ready() (see the dealt_damage.connect call
# there) - covers normal shots fired via Projectile automatically. Ability
# damage (shockwave/railgun) doesn't route through a Projectile, so
# _resolve_shockwave/_resolve_railgun call this directly after apply_damage.
func _on_self_dealt_damage(amount: float):
	_boss_damage_dealt += amount
	_boss_hits_landed += 1
	_boss_time_since_hit = 0.0
	if _boss_first_engagement < 0.0:
		_boss_first_engagement = _boss_time_alive

func get_boss_fitness() -> float:
	var damage_score = _boss_damage_dealt * 1.0
	var hit_score = _boss_hits_landed * 3.0
	var survival_score = 0.0
	if _boss_first_engagement >= 0.0:
		survival_score = min(_boss_time_alive - _boss_first_engagement, 60.0) * 2.0
	if _boss_hits_landed <= 0:
		survival_score = 0.0 # never engaged at all - no survival credit (anti-hiding, same rule as Squad's)
	return max(0.0, damage_score + hit_score + survival_score - _boss_flee_penalty)

# --- Boss Enrage & Signature Abilities -----------------------------------
# Every boss gets two things layered on top of its ordinary role AI
# (movement/shooting are otherwise untouched - see _execute_ai_tactics):
# enrage phases as HP drops, and cooldown-gated signature ability use.
# Neither system runs for non-boss mechs (is_boss stays false). Which
# ENRAGE STYLE and which ABILITIES are available now varies per-boss via
# boss_profile (see BossProfile.gd / SquadDirector's boss profile
# evolution) instead of being the same fixed escalation for every boss.

var enrage_stage: int = 0
const ENRAGE_THRESHOLDS: Array = [0.5, 0.2] # HP fraction that triggers each stage

# Each style hits a different combination of fire_rate/speed_modifier/
# engagement_distance/self-heal per stage - see _apply_enrage_style. Falls
# back to "berserker" if boss_profile is null (debug-spawned boss, etc.).
func _get_enrage_style() -> String:
	if boss_profile and boss_profile.enrage_style != "":
		return boss_profile.enrage_style
	return "berserker"

func _update_boss_enrage():
	while enrage_stage < ENRAGE_THRESHOLDS.size() and max_hp > 0.0 and hp <= max_hp * ENRAGE_THRESHOLDS[enrage_stage]:
		enrage_stage += 1
		_apply_enrage_style(_get_enrage_style())
		_show_floating_text("ENRAGED", Color(1.0, 0.25, 0.1))
		var cam = get_tree().get_first_node_in_group("camera")
		if cam and cam.has_method("shake"):
			cam.shake(2.0, 0.5)
		var orig_modulate = modulate
		var flash_tween = create_tween()
		flash_tween.tween_property(self, "modulate", Color(1.6, 0.4, 0.3) * orig_modulate, 0.1)
		flash_tween.tween_property(self, "modulate", orig_modulate, 0.4)

# Four flavors, each leaning on a different stat so "enraged" reads
# differently depending on the boss instead of every boss getting the
# identical fire_rate/speed/engage bump:
#   berserker  - mostly fire rate (shoots much faster, the classic "rage")
#   juggernaut - mostly speed + engagement range (charges you down harder)
#   vampiric   - modest all-around bump PLUS an actual heal-back, a real
#                "second wind" rather than just a stat spike
#   unstable   - the biggest, most chaotic all-around swing (highest risk
#                for the player to be near when it procs, but also the
#                easiest to punish since nothing here is subtle)
func _apply_enrage_style(style: String):
	match style:
		"berserker":
			fire_rate *= 0.65
			speed_modifier *= 1.08
			engagement_distance *= 0.95
		"juggernaut":
			fire_rate *= 0.9
			speed_modifier *= 1.35
			engagement_distance *= 0.75
		"vampiric":
			fire_rate *= 0.85
			speed_modifier *= 1.1
			engagement_distance *= 0.9
			var heal_amt = max_hp * 0.1
			hp = min(max_hp, hp + heal_amt)
			if heal_amt >= 1.0:
				_show_floating_text("+%d" % int(round(heal_amt)), Color(0.3, 1.0, 0.5))
		"unstable":
			fire_rate *= randf_range(0.5, 0.85)
			speed_modifier *= randf_range(1.1, 1.5)
			engagement_distance *= randf_range(0.7, 1.0)
		_:
			fire_rate *= 0.8
			speed_modifier *= 1.15
			engagement_distance *= 0.9

const BOSS_ABILITY_COOLDOWN = 6.0
var boss_ability_cooldown: float = 3.0 # first use isn't instant - gives the player a beat to size the boss up first
var boss_ability_state: String = "" # "" = idle/ready; otherwise the ability currently winding up ("shockwave"/"railgun")
var boss_ability_windup: float = 0.0
var _boss_railgun_aim: Vector2 = Vector2.ZERO
var _rally_speed_timer: float = 0.0
const RALLY_SPEED_MULT = 1.3

# Role that would have used this ability before boss_profile.ability_pool
# existed - the fallback for a profile-less boss (e.g. debug-menu spawned)
# and the seed data _register_default_boss_profiles builds each archetype's
# starting pool from.
const ROLE_DEFAULT_ABILITY = {
	"brawler": "shockwave", "sniper": "railgun", "ambusher": "blink_strike",
	"flamethrower": "fire_pool", "jammer": "jam_burst", "commander": "rally",
}

# True while resolving a chained follow-up ability, so _maybe_chain_ability
# can never trigger a second chain off of a chain (caps it at exactly one
# extra use per original trigger, however deep enrage_stage gets).
var _boss_chaining: bool = false

func _get_ability_pool() -> Array:
	if boss_profile and not boss_profile.ability_pool.is_empty():
		return boss_profile.ability_pool
	if ROLE_DEFAULT_ABILITY.has(combat_role):
		return [ROLE_DEFAULT_ABILITY[combat_role]]
	return []

# Dispatches by ability key (drawn from boss_profile.ability_pool, which
# mutation can grow to 2 abilities that alternate - the actual "more
# evolution options" this replaces the old fixed combat_role match with).
# Telegraphed abilities (shockwave/railgun) set boss_ability_state and let
# _continue_boss_ability resolve them next; instant ones (blink/fire pool/
# jam burst/rally) fire immediately and reset the cooldown themselves.
func _start_boss_ability():
	if not target or not is_instance_valid(target):
		return
	var pool = _get_ability_pool()
	if pool.is_empty():
		boss_ability_cooldown = BOSS_ABILITY_COOLDOWN # no ability available - don't retry every frame
		return
	var ability = pool[randi() % pool.size()]
	match ability:
		"shockwave":
			boss_ability_state = "shockwave"
			boss_ability_windup = 0.6
			var telegraph = load("res://scripts/visuals/BossTelegraphRing.gd").new()
			if get_parent():
				get_parent().add_child(telegraph)
				telegraph.global_position = global_position
				telegraph.telegraph(220.0, boss_ability_windup, Color(1.0, 0.4, 0.1, 0.8))
		"railgun":
			boss_ability_state = "railgun"
			boss_ability_windup = 1.2
			_boss_railgun_aim = target.global_position
			_spawn_railgun_telegraph(_boss_railgun_aim, boss_ability_windup)
		"blink_strike":
			_do_blink_strike()
			boss_ability_cooldown = BOSS_ABILITY_COOLDOWN
		"fire_pool":
			_do_fire_pool()
			boss_ability_cooldown = BOSS_ABILITY_COOLDOWN
		"jam_burst":
			_do_jam_burst()
			boss_ability_cooldown = BOSS_ABILITY_COOLDOWN
		"rally":
			_do_rally()
			boss_ability_cooldown = BOSS_ABILITY_COOLDOWN
		_:
			boss_ability_cooldown = BOSS_ABILITY_COOLDOWN # unrecognized key - don't retry every frame

	# Instant abilities resolved above (boss_ability_state is still "" for
	# them) can chain right here; telegraphed ones chain later, from
	# _continue_boss_ability, once they've actually resolved.
	if boss_ability_state == "" and not _boss_chaining:
		_maybe_chain_ability()

# From enrage_stage 2 ("desperate", 20% HP) onward, every ability use is
# immediately followed by a second one - the fight's climax reads as an
# actual combo instead of the same single move on repeat. Deliberately a
# flat property of the stage (not a depletable charge) so it stays a
# consistent threat for the rest of the fight once a boss gets there.
func _maybe_chain_ability():
	if enrage_stage >= 2 and target and is_instance_valid(target):
		_boss_chaining = true
		_start_boss_ability()
		_boss_chaining = false

# Ticks down an in-progress windup and resolves it once it hits zero. The
# boss is rooted (see _execute_ai_tactics) for the entire duration this is
# non-empty, which is what sells "channeling" rather than "moving normally
# while also somehow attacking."
func _continue_boss_ability(delta):
	boss_ability_windup -= delta
	if boss_ability_windup > 0.0:
		return
	if boss_ability_state == "shockwave":
		_resolve_shockwave()
	elif boss_ability_state == "railgun":
		_resolve_railgun()
	boss_ability_state = ""
	boss_ability_cooldown = BOSS_ABILITY_COOLDOWN
	if not _boss_chaining:
		_maybe_chain_ability()

# Warhulk: AoE damage + knockback centered on the boss. Damage/HP scale off
# the boss's OWN max_hp (which already carries wave/difficulty/hp_mult
# scaling) so this stays relevant at any wave without separate tuning.
func _resolve_shockwave():
	var radius = 220.0
	var p = _get_player_ref()
	if p:
		if global_position.distance_to(p.global_position) <= radius and p.has_method("apply_damage"):
			var dmg = max_hp * 0.06 * _get_ambush_multiplier()
			p.apply_damage(dmg, "RAW")
			dealt_damage.emit(dmg) # ability damage doesn't route through Projectile - credit fitness tracking manually
			if "external_force" in p:
				var away = p.global_position - global_position
				away = away.normalized() if away.length() > 0.01 else Vector2.RIGHT
				p.external_force += away * 700.0
	var ring = load("res://scripts/visuals/BossTelegraphRing.gd").new()
	if get_parent():
		get_parent().add_child(ring)
		ring.global_position = global_position
		ring.burst(20.0, radius, 0.25, Color(1.0, 0.6, 0.2, 1.0))
	var cam = get_tree().get_first_node_in_group("camera")
	if cam and cam.has_method("shake"):
		cam.shake(2.5, 0.3)

# Longshot: a locked firing line shown during the windup (so the player can
# see it and step off the line) - not a ring, so it gets its own tiny
# Line2D helper rather than reusing BossTelegraphRing.
func _spawn_railgun_telegraph(aim_point: Vector2, duration: float):
	var line = Line2D.new()
	line.width = 4.0
	line.default_color = Color(1.0, 0.2, 0.2, 0.0)
	line.z_index = 50
	# Points are in the line's own local space (matches the convention in
	# Projectile._spawn_instant_bolt_flash) - global_position below is what
	# actually places it in the world, not a baked-in world coordinate.
	var to_aim = aim_point - global_position
	var far_local = to_aim.normalized() * 2000.0 if to_aim.length() > 0.01 else Vector2.RIGHT * 2000.0
	line.points = PackedVector2Array([Vector2.ZERO, far_local])
	line.global_position = global_position
	if get_parent():
		get_parent().add_child(line)
		var tw = line.create_tween()
		tw.tween_property(line, "modulate:a", 1.0, duration * 0.6)
		tw.tween_property(line, "modulate:a", 0.3, duration * 0.4)
		tw.tween_callback(line.queue_free)

func _resolve_railgun():
	var dir_locked = global_position.direction_to(_boss_railgun_aim)
	if dir_locked == Vector2.ZERO:
		dir_locked = Vector2.RIGHT
	var p = _get_player_ref()
	if p:
		var to_player = p.global_position - global_position
		var along = to_player.dot(dir_locked)
		if along > 0.0:
			var perp = (to_player - dir_locked * along).length()
			if perp < 40.0 and p.has_method("apply_damage"): # beam width tolerance
				var dmg = max_hp * 0.1 * _get_ambush_multiplier()
				p.apply_damage(dmg, "PIERCE")
				dealt_damage.emit(dmg) # ability damage doesn't route through Projectile - credit fitness tracking manually
	var beam = Line2D.new()
	beam.width = 10.0
	beam.default_color = Color(1.0, 0.9, 0.7, 1.0)
	beam.z_index = 51
	beam.points = PackedVector2Array([Vector2.ZERO, dir_locked * 2000.0])
	beam.global_position = global_position
	if get_parent():
		get_parent().add_child(beam)
		var tw = beam.create_tween()
		tw.tween_property(beam, "modulate:a", 0.0, 0.25)
		tw.tween_callback(beam.queue_free)
	var cam = get_tree().get_first_node_in_group("camera")
	if cam and cam.has_method("shake"):
		cam.shake(2.0, 0.25)

# Specter: teleports to a random flank of the target and fires immediately
# while is_cloaked - _shoot() already applies the ambush bonus (via
# _get_ambush_multiplier()) to any shot fired while cloaked, so this gets a
# guaranteed heavy hit for free without needing new damage code. The strike
# also opens the usual 0.25s post-decloak window, so a fast follow-up shot
# right after still lands the bonus too.
func _do_blink_strike():
	var flank_dir = Vector2.RIGHT.rotated(randf() * TAU)
	var dest = target.global_position + flank_dir * 130.0
	# Snap to the nearest clear tile, same helper used for squad spawns -
	# a raw random offset could otherwise occasionally land the teleport
	# inside a wall/obstacle with no collision-resolution to bail it out.
	var map = _get_map_ref()
	if map:
		dest = map.get_valid_spawn_position(dest)
	global_position = dest
	is_cloaked = true
	_shoot(target.global_position, true, true, 0.0)
	_show_floating_text("STRIKE", Color(0.7, 0.6, 1.0))
	var cam = get_tree().get_first_node_in_group("camera")
	if cam and cam.has_method("shake"):
		cam.shake(1.5, 0.2)

# Incinerator: drops a JumpjetResidue hazard zone (the same DoT-zone class
# the player's own Jumpjet uses) at the player's current position. Reused
# wholesale rather than writing a new hazard class - it already does
# exactly this (expanding damage-over-time zone with a fade-out). Its
# default collision_mask targets Enemies (for the player's own residue), so
# that's overridden to Player here.
func _do_fire_pool():
	if not target or not is_instance_valid(target):
		return
	# Same construction order as the player's own jumpjet residue (see
	# above): global_position + setup() BEFORE add_child, so _ready() bakes
	# the visual/particle colors correctly from the start instead of
	# building a default-white zone and recoloring it after.
	var residue = JumpjetResidue.new()
	residue.global_position = target.global_position
	residue.lifetime = 4.0
	residue.source_mech = self # credits fitness tracking for this DoT zone's ticks (see JumpjetResidue._physics_process)
	residue.setup(max_hp * 0.015, {EnergyPacket.SynergyType.FIRE: 1.0})
	if get_parent():
		get_parent().add_child(residue)
	residue.collision_mask = 8 # Player - JumpjetResidue defaults to Enemies (4) for the player's own residue
	_show_floating_text("BURN", Color(1.0, 0.5, 0.1))

# Warden: a big one-shot vision-blackout burst layered on top of the
# JammerMech's own continuous power-drain aura (see JammerMech.gd) - the
# passive drain is the constant pressure, this is the periodic spike.
func _do_jam_burst():
	var burst_radius = 900.0
	if target and target.has_method("apply_vision_jam") and global_position.distance_to(target.global_position) <= burst_radius:
		target.apply_vision_jam(1.5)
	var visual_class = load("res://scripts/attacks/PulseRingVisual.gd")
	if visual_class:
		var v = visual_class.new()
		v.global_position = global_position
		v.setup(burst_radius, Color(0.2, 0.5, 1.0, 1.0))
		if get_parent():
			get_parent().add_child(v)
	_show_floating_text("JAM BURST", Color(0.3, 0.6, 1.0))

# Overlord: no summoning (per design constraint) - instead a big self-heal,
# a full shield refresh, and a temporary speed buff (see the
# _rally_speed_timer tick in update_status_effects).
func _do_rally():
	var heal_amt = max_hp * 0.15
	hp = min(max_hp, hp + heal_amt)
	if max_shield_hp > 0.0:
		shield_hp = max_shield_hp
	_rally_speed_timer = 4.0
	if heal_amt >= 1.0:
		_show_floating_text("+%d RALLY" % int(round(heal_amt)), Color(0.3, 1.0, 0.5))
	var cam = get_tree().get_first_node_in_group("camera")
	if cam and cam.has_method("shake"):
		cam.shake(1.0, 0.3)

# Drained-husk terrain from VAMPIRIC kills. Globally capped so a vampiric
# build can't pave the whole map - oldest husk crumbles when the cap hits.
func _spawn_corpse_obstacle():
	var existing = get_tree().get_nodes_in_group("corpse_obstacle")
	if existing.size() >= 12 and is_instance_valid(existing[0]):
		existing[0].queue_free()

	var husk = StaticBody2D.new()
	husk.add_to_group("corpse_obstacle")
	husk.collision_layer = 1 # world obstacle: blocks movement and shots
	husk.collision_mask = 0

	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 14.0
	shape.shape = circle
	husk.add_child(shape)

	var poly = Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(-14, -6), Vector2(-4, -12), Vector2(10, -8),
		Vector2(14, 4), Vector2(6, 12), Vector2(-10, 10)
	])
	poly.color = Color(0.32, 0.28, 0.33) # drained grey-violet
	husk.add_child(poly)

	var timer = Timer.new()
	timer.wait_time = 10.0
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(husk.queue_free)
	husk.add_child(timer)

	husk.global_position = global_position
	# Deferred: die() runs mid-physics, and adding a StaticBody during a
	# physics flush is exactly the kind of thing Godot errors about.
	get_parent().call_deferred("add_child", husk)

func die():
	if is_dead or is_queued_for_deletion():
		return
	is_dead = true

	# Report the killing element to the director (kill-method telemetry for
	# pierce-overuse counter-pressure). Approximation: we don't track the
	# damage SOURCE, so AI friendly-fire kills also count - acceptable noise
	# since the overwhelming majority of enemy deaths are player kills.
	if not is_player:
		var main_scene = get_tree().current_scene
		if main_scene and "world" in main_scene and main_scene.world and main_scene.world.has_node("SquadDirector"):
			main_scene.world.get_node("SquadDirector").log_player_kill(last_damage_element)

	# VAMPIRIC kills leave a drained husk that blocks movement and shots
	# for a while - terrain you make out of your enemies (group 3 spec).
	if not is_player and last_damage_element == "VAMPIRIC" and get_parent():
		_spawn_corpse_obstacle()

	# LootManager is an autoload singleton (see project.godot) - use it directly
	# instead of instantiating a throwaway copy (was also why the 25th-wave
	# guaranteed-legendary-drop check always failed: a fresh instance's
	# current_wave defaulted to 1, so `current_wave % 25 == 0` never fired).
	LootManager.generate_loot_for_mech(self)

	died.emit()
	
	var is_over_water = false
	var maps = get_tree().get_nodes_in_group("map_generator")
	if maps.size() > 0:
		var map = maps[0]
		var grid_pos = Vector2i(floor(global_position.x / map.tile_size), floor(global_position.y / map.tile_size))
		if grid_pos.x >= 0 and grid_pos.x < map.width and grid_pos.y >= 0 and grid_pos.y < map.height:
			if map.terrain[grid_pos.y][grid_pos.x] == map.BiomeType.WATER:
				is_over_water = true
				
	if is_over_water:
		collision_layer = 0
		collision_mask = 0
		set_physics_process(false)
		var tween = create_tween()
		tween.tween_property(self, "scale", Vector2(0.2, 0.2), 1.0).set_trans(Tween.TRANS_SINE)
		tween.parallel().tween_property(self, "global_position", global_position + Vector2(0, 20), 1.0)
		tween.parallel().tween_property(self, "modulate:a", 0.0, 1.0)
		tween.tween_callback(queue_free)
	else:
		queue_free()

func build_loadout_for_role(role_name: String):
	var inventory = []
	
	var add_tile = func(path, rarity, synergy=0):
		var tile = load(path).new()
		tile.rarity = rarity
		if synergy > 0 and "secondary_synergy" in tile:
			tile.secondary_synergy = synergy
		inventory.append(tile)
		
	match role_name:
		"sniper":
			add_tile.call("res://scripts/tiles/AmplifierTile.gd", HexTile.Rarity.RARE)
			add_tile.call("res://scripts/tiles/CatalystTile.gd", HexTile.Rarity.RARE)
			add_tile.call("res://scripts/tiles/DirectionalConduitTile.gd", HexTile.Rarity.COMMON)
		"brawler":
			add_tile.call("res://scripts/tiles/SplitterTile.gd", HexTile.Rarity.UNCOMMON)
			add_tile.call("res://scripts/tiles/SplitterTile.gd", HexTile.Rarity.UNCOMMON)
			add_tile.call("res://scripts/tiles/AmplifierTile.gd", HexTile.Rarity.UNCOMMON)
		"flamethrower":
			add_tile.call("res://scripts/tiles/InfuserTile.gd", HexTile.Rarity.RARE, 1) # FIRE
			add_tile.call("res://scripts/tiles/SplitterTile.gd", HexTile.Rarity.UNCOMMON)
			add_tile.call("res://scripts/tiles/SplitterTile.gd", HexTile.Rarity.COMMON)
		"ambusher":
			add_tile.call("res://scripts/tiles/InfuserTile.gd", HexTile.Rarity.RARE, 4) # KINETIC
			add_tile.call("res://scripts/tiles/AmplifierTile.gd", HexTile.Rarity.UNCOMMON)
		"scout":
			pass # Uses basic conduits if they were available, fallback empty solver handles it
		"commander":
			# Weapons are secondary for a Commander - the Command Suite
			# backpack is the payload. Feed the solver defensive parts.
			add_tile.call("res://scripts/tiles/ShieldTile.gd", HexTile.Rarity.RARE)
			add_tile.call("res://scripts/tiles/AccumulatorTile.gd", HexTile.Rarity.RARE)

	# Give the solver something to actually work with: an Infuser it can
	# configure toward the spawn profile's counter-element/Pierce priority.
	# Without this, a profile could only ever reorder whatever flavor tiles
	# the role already hardcodes above - it couldn't introduce a genuinely
	# new counter-element into a role that doesn't normally use one.
	if spawn_profile != null:
		add_tile.call("res://scripts/tiles/InfuserTile.gd", HexTile.Rarity.UNCOMMON)

	var solver = load("res://scripts/core/AutoEquipSolver.gd").new()

	if components.has(HexTile.BodySlot.TORSO):
		inventory = solver.solve(components[HexTile.BodySlot.TORSO], inventory, spawn_profile)
	if components.has(HexTile.BodySlot.ARM_R):
		inventory = solver.solve(components[HexTile.BodySlot.ARM_R], inventory, spawn_profile)
	if components.has(HexTile.BodySlot.ARM_L):
		inventory = solver.solve(components[HexTile.BodySlot.ARM_L], inventory, spawn_profile)

	_recalculate_grid()

