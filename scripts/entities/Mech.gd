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
const PlayerController = preload("res://scripts/entities/PlayerController.gd")
const BossBrain = preload("res://scripts/entities/BossBrain.gd")
const StatusEffectRunner = preload("res://scripts/entities/StatusEffectRunner.gd")
const SightAndSearch = preload("res://scripts/entities/SightAndSearch.gd")
const MagnetSystem = preload("res://scripts/entities/MagnetSystem.gd")
const CloakSystem = preload("res://scripts/entities/CloakSystem.gd")
const JammerModuleSystem = preload("res://scripts/entities/JammerModuleSystem.gd")
const JammerField = preload("res://scripts/visuals/JammerField.gd")

# Lazily constructed the first time it's needed (is_player branch of
# _physics_process / is_boss branch of _execute_ai_tactics / first call to
# update_status_effects / first call to _update_player_sight / first call to
# _physics_process's cloak/jammer tick) - see PlayerController.gd/
# BossBrain.gd/StatusEffectRunner.gd/SightAndSearch.gd/CloakSystem.gd/
# JammerModuleSystem.gd's own header comments for why these are composed
# RefCounted objects, not child Nodes.
var player_controller: PlayerController = null
var boss_brain: BossBrain = null
var status_runner: StatusEffectRunner = null
var sight_and_search: SightAndSearch = null
var magnet_system: MagnetSystem = null
var cloak_system: CloakSystem = null
var jammer_module_system: JammerModuleSystem = null

# JammerField is a real scene-tree Node (see its own header comment for why
# it's NOT a RefCounted composed object like the ones above) - constructed
# lazily by JammerModuleSystem the first time this mech's equipped Jammer
# Module is in VISION mode, freed the moment it isn't (mode swapped, tile
# unequipped, or this mech dies). Stays a plain Mech field (not moved into
# JammerModuleSystem) since it's read directly as mech.jammer_field by an
# existing debug check and other systems - meant to be glanceable state.
var jammer_field: JammerField = null

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
var jumpjet_rarity: int = -1
# -1 = no Maneuvering Thruster equipped, otherwise the highest-rarity one's
# rarity tier - read by PlayerController.gd's accel calc (see
# ManeuveringThrusterTile.gd).
var thruster_accel_bonus: int = -1
var jumpjet_energy = null
var actuator_energy = null

# --- Cloak (Ambusher backpack ability) ---
# Capacity/recharge-rate are sized once per _recalculate_grid() from
# CloakTile energy (same pattern as the shield generator) - these stay on
# Mech (not CloakSystem) because _recalculate_grid writes them directly on
# every loadout change, and is_cloaked is read/written externally by
# BossBrain/PlayerController at any time. The actual per-frame charge/
# timer/visual tick lives in CloakSystem.gd - see its header comment for
# the full split rationale (same principle as StatusEffectRunner.gd).
var has_cloak_generator: bool = false
var max_cloak_charge: float = 0.0
var cloak_recharge_rate: float = 0.0
var cloak_recharge_delay: float = 1.0
var cloak_drain_rate: float = 0.0
var is_cloaked: bool = false

# --- Jammer Module (equippable pulse ability - distinct from the JammerMech
# role, which is a whole separate continuous-aura mech class) ---
var has_jammer_module: bool = false
# Every equipped Jammer Module tile (rebuilt each _recalculate_grid) -
# drained of routed packet energy every frame to power-scale the field.
var _jammer_tiles: Array = []
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

func apply_shield_energy(amount: float):
	max_shield_hp += amount # Max shield grows based on energy it processes!
	shield_hp = max_shield_hp

var is_player: bool = false
var is_firing_outward: bool = false
var last_aim_position: Vector2 = Vector2.ZERO

var current_jammer_debuff: float = 1.0 # 1.0 is no debuff. 0.1 is 90% power reduction

var jumpjet_trail = null
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

# MagnetTile.get_magnetic_power() accumulates packet.magnitude every time
# ANY packet passes through it in _simulate_grid() - and a closed-loop grid
# (Splitter/Reflector/Resonator circuits, explicitly allowed up to the
# 100-step cap in _simulate_grid) can route the same packet through one
# magnet many times in a single recalculation. With EnergyPacket.MAX_MAGNITUDE
# at 150000 (raised for capacitor-bank builds), a handful of loop passes on a
# dense Mythic grid used to blow total_magnetic_power into the millions,
# feeding pull_radius/pull-speed formulas that were LINEAR in power with no
# ceiling - a legitimately powerful build could make every loot pickup on
# the ENTIRE map snap to the player in a single 1/MAGNET_UPDATE_HZ tick
# regardless of true distance.
#
# First fix here was a flat clamp on total_magnetic_power itself - too
# blunt: a single NORMAL (non-looped) packet passing through one Mythic
# magnet can easily carry a magnitude in the thousands on a decent mid-game
# build, nowhere near the pathological loop-abuse case, so the flat cap
# also crushed ordinary magnet scaling down to "barely stronger than the
# 150 baseline" for anyone past the very early game ("the magnet doesn't
# seem to be working"). Replaced with a saturating curve instead: pull_
# radius/speed grow close to linearly with power at normal scales (matching
# the original feel) but asymptotically approach a fixed ceiling no matter
# how large total_magnetic_power gets - "more power = more pull" stays true
# all the way up instead of hitting a wall, while still bounding the
# absolute maximum reach against the loop-abuse case. total_magnetic_power
# itself is left unclamped (see pull_radius/pull_speed_mult below).
const MAGNET_POWER_SCALE = 250.0
const MAGNET_PULL_RADIUS_MAX_BONUS = 2500.0
const MAGNET_PULL_SPEED_MAX_BONUS = 5.0


var fire_cooldown: float = 0.0
var fire_rate: float = 0.25 # 4 shots per second

var components: Dictionary = {} # Dict of HexTile.BodySlot -> ComponentEquipment
var is_grid_dirty: bool = true
var precalculated_weapons: Array = []
# Every LanceMountTile found across all equipped components this recalc -
# collected here (not folded into precalculated_weapons, which assumes the
# WeaponMountTile bank/normal-split model) since Lance fires itself
# automatically once fed+off-cooldown rather than being mouse/key-triggered
# - see _tick_weapon_charges.
var lance_mounts: Array = []
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
# New fitness-axis input (see Squad._calculate_fitness): mirrors dealt_damage
# but for the receiving side, so Squad can score damage TRADED (dealt vs.
# taken) instead of only ever looking at offense. was_reflected flags damage
# from a Mythic Magnet repel-mode bounce specifically - Natalia asked for the
# AI to notice when it's dying to its own reflected fire and weight
# speed/shield accordingly (see the magnet-repel flip block below).
signal took_damage(amount: float, was_reflected: bool)
signal died()
signal fled_to_wild(bot: Node)

# --- Wild-bot flee thresholds (Status.md queue) ----------------------------
# Role-specific HP fractions below which a regular wave enemy breaks off,
# sprints away from the player, and goes "wild": it leaves its squad, hands
# its wave slot back (so a hiding survivor can never stall the wave-clear),
# emits fled_to_wild, and joins SquadDirector.wild_bots for recruitment into
# a future squad. Skittish roles bail early; heavy front-line roles fight to
# the bitter end (0.0 = never). Bosses, rivals, champions, and debug spawns
# never flee (gated on actually holding a wave slot - see _is_wave_enemy).
const FLEE_THRESHOLDS = {
	"ambusher": 0.5,
	"scout": 0.5,
	"jammer": 0.45,
	"sniper": 0.4,
	"support": 0.35,
	"piercing_jammer": 0.3,
	"flamethrower": 0.2,
	"commander": 0.15,
	"brawler": 0.0,
	"melee": 0.0,
	"tank": 0.0,
	"drone": 0.0,
}
const FLEE_DEFAULT_THRESHOLD = 0.25
const FLEE_SAFE_DISTANCE = 1400.0
# Wild bots lick their wounds while loitering - regen keeps a re-recruited
# bot from instantly re-fleeing at the same threshold it bailed at.
const WILD_REGEN_PER_SEC_FRACTION = 0.02
const WILD_REGEN_CAP_FRACTION = 0.75
var is_fleeing: bool = false
var _has_gone_wild: bool = false

# --- Individual-bot fitness tracking (Natalia: "individuals in types of
# roles... tracked/scored") ------------------------------------------------
# Mirrors Squad._calculate_fitness's inputs but scoped to THIS bot alone,
# by self-connecting dealt_damage/took_damage in _ready() rather than
# scattering += calls across every emission site (Projectile._handle_hit,
# Mech._boss_emit_dealt_damage, Mech.apply_damage). Squad still sums these
# same signals into a SQUAD-wide total for template/composition scoring
# (a group property) - this is the per-bot analog, consumed by
# SquadDirector.credit_bot_death() to score that bot's OWN spawn_profile
# with its OWN performance instead of the squad's shared aggregate.
var _own_damage_dealt: float = 0.0
var _own_hits_landed: int = 0
var _own_damage_taken: float = 0.0
var _own_reflected_damage_taken: float = 0.0
var _own_blind_hits_landed: int = 0
var _own_first_engagement_time: float = -1.0
var _own_time_alive: float = 0.0

func _on_own_dealt_damage(amount: float):
	_own_damage_dealt += amount
	_own_hits_landed += 1
	if _own_first_engagement_time < 0:
		_own_first_engagement_time = _own_time_alive
	# has_sight_of_player is only meaningful for non-player mechs (the
	# player never runs _update_player_sight on itself) - harmless either
	# way since individual fitness is only ever consumed for enemy bots.
	if not has_sight_of_player:
		_own_blind_hits_landed += 1

func _on_own_took_damage(amount: float, was_reflected: bool):
	_own_damage_taken += amount
	if was_reflected:
		_own_reflected_damage_taken += amount

# Near-peer evolution rewards (playtest: "now I'm fighting near peer
# enemies - I'm dying a whole lot more. Could it give extra special bonus
# for that? Could it also be rewarded for hitting my drones or allied
# units?"): damage that actually lands on the PLAYER is worth extra fitness
# beyond the generic damage term, damage on the player's drones/allies a
# smaller premium, and killing blows a large flat bonus - so evolution
# selects for bots that genuinely threaten the player's side, not ones that
# farm safe chip damage. Credited from the VICTIM's apply_damage (it knows
# both the source and what it itself is), not from the projectile.
var _own_player_damage: float = 0.0
var _own_ally_damage: float = 0.0
var _own_player_kills: int = 0
var _own_ally_kills: int = 0

func note_priority_target_damage(amount: float, was_the_player: bool):
	if was_the_player:
		_own_player_damage += amount
	else:
		_own_ally_damage += amount

func note_priority_kill(was_the_player: bool):
	if was_the_player:
		_own_player_kills += 1
	else:
		_own_ally_kills += 1

# Same formula shape as Squad._calculate_fitness (damage/hits/survival/
# trade/blind), minus the flee-penalty term - that's a squad-cohesion
# signal ("the group went quiet"), not meaningful for a single bot whose
# own timeline just ends at death. Kept directly comparable in scale to
# squad-level fitness (100 = "expected average" convention) so a solver
# profile's average fitness means the same thing whether it was credited
# via the old squad-aggregate path or this new per-bot one.
func get_individual_fitness() -> float:
	var damage_score = _own_damage_dealt * 1.0
	var hit_score = _own_hits_landed * 3.0

	var survival_score = 0.0
	if _own_first_engagement_time >= 0:
		survival_score = min(_own_time_alive - _own_first_engagement_time, 60.0) * 2.0
	if _own_hits_landed <= 0:
		survival_score = 0.0

	var trade_ratio = damage_score / max(1.0, _own_damage_taken)
	var trade_score = clamp((trade_ratio - 1.0) * 15.0, -40.0, 60.0)

	var reflection_penalty = _own_reflected_damage_taken * 0.5
	var blind_score = _own_blind_hits_landed * 4.0

	# Priority-target premium (see note_priority_target_damage): player
	# damage counts ON TOP of the generic damage term (so it's worth 2.5x a
	# hit on nothing in particular), ally/drone damage a smaller premium,
	# and killing blows are worth a wave's worth of chip damage by
	# themselves - "extra special bonus" per the playtest ruling.
	var priority_score = _own_player_damage * 1.5 \
		+ _own_ally_damage * 0.75 \
		+ _own_player_kills * 400.0 \
		+ _own_ally_kills * 80.0

	return max(0.0, damage_score + hit_score + survival_score + trade_score + blind_score + priority_score - reflection_penalty)

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
	# Individual-bot fitness tracking (see the field block above) - self-
	# connected rather than instrumented at every dealt_damage/took_damage
	# emission site.
	dealt_damage.connect(_on_own_dealt_damage)
	took_damage.connect(_on_own_took_damage)

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
		collision_mask = 1 | 2 | 4 | 16 | 32 # Env, Water, Enemy, Loot, Obstacles
	else:
		collision_layer = 4 # Layer 3 (Enemy)
		collision_mask = 1 | 2 | 8 | 32 # Env, Water, Player, Obstacles
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

	# Commanders always come with a companion Drone (see create_command_
	# backpack); every other enemy role gets a modest independent chance at
	# one too (Natalia: "mobs/enemies should get to have them too") - never
	# for the player (role == "" only ever happens for the player's own
	# backpack, which stays entirely Garage-controlled, never procedurally
	# overridden). Rolled AFTER the role match above so it only ever applies
	# to whichever roles fell through without a guaranteed special backpack
	# of their own (including a "scout"/"ambusher" that rolled OUT of their
	# usual jammer/cloak chance above).
	if role != "" and randf() < 0.12:
		return ComponentEquipment.create_drone_backpack(max(p_rarity, HexTile.Rarity.UNCOMMON))

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

# Terrain obstacles live on their own physics layer (design ruling:
# "jumpjets go over all terrain obstacles") - merged obstacle runs, trees,
# ruins, and corpse husks are all layer 32; map border/dungeon walls stay
# layer 1 (jets never leave the table). While the jets are visibly firing
# (sprint or water-hover both light the trail emitters), the obstacle bit
# drops out of the mask and the mech flies clean over.
const OBSTACLE_LAYER = 32

func _jets_firing() -> bool:
	if _water_hover_active:
		return true
	if jumpjet_trail:
		for p in jumpjet_trail.get_children():
			if p.emitting:
				return true
	return false

func _update_obstacle_phasing():
	if _has_jumpjets() and _jets_firing():
		collision_mask &= ~OBSTACLE_LAYER
	else:
		collision_mask |= OBSTACLE_LAYER

func _physics_process(delta: float):
	_own_time_alive += delta
	current_jammer_debuff = 1.0 # Reset every frame, JammerMech will re-apply it before we shoot if near
	_refresh_water_state()
	_update_obstacle_phasing()

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
	# _update_heat(delta) # Thermal system commented out per Natalia - see the
	# heat block near HEAT_CAPACITY below for the rest of what's disabled.

	time_since_last_hit += delta
	if has_shield_generator and max_shield_hp > 0 and time_since_last_hit >= shield_recharge_delay:
		if shield_hp < max_shield_hp:
			shield_hp = min(max_shield_hp, shield_hp + shield_recharge_rate * delta)

	if is_boss:
		# _boss_time_alive/_boss_first_engagement used to be separate boss-only
		# clocks duplicating _own_time_alive/_own_first_engagement_time (see
		# get_individual_fitness's field block) - a boss fight is "a squad of
		# one" so the individual-bot tracking already covers this identically;
		# only the flee-penalty piece below is genuinely boss-specific.
		if _own_first_engagement_time >= 0.0:
			_boss_time_since_hit += delta
			if _boss_time_since_hit > BOSS_FLEE_GRACE:
				_boss_flee_penalty += BOSS_FLEE_RATE * delta

	if not cloak_system:
		cloak_system = CloakSystem.new(self)
	cloak_system.tick(delta)
	_update_jammer_module(delta)
	_update_healer(delta)

	if is_player:
		if not player_controller:
			player_controller = PlayerController.new(self)
		player_controller.handle_input(delta)
		velocity += external_force
		move_and_slide()
		_process_ramming(delta)
		var lerp_weight = 10.0 * delta
		if lerp_weight > 1.0: lerp_weight = 1.0
		external_force = external_force.lerp(Vector2.ZERO, lerp_weight)

		# Magnet Logic
		if not magnet_system:
			magnet_system = MagnetSystem.new(self)
		magnet_system.update(delta)
		
		# Drowning check
		if not Input.is_action_pressed("ui_select"):
			_check_drowning()
		
		if _renderer:
			_renderer.rotate_arms(get_global_mouse_position(), global_position)
			_renderer.animate_legs(velocity, Time.get_ticks_msec() / 1000.0)
	else:
		var is_far = false
		if target and is_instance_valid(target):
			is_far = global_position.distance_to(target.global_position) > 1400.0

		if is_far:
			_lod_ai_timer -= delta
			if _lod_ai_timer <= 0.0:
				_lod_ai_timer = 0.25 # 4 AI ticks per second when far
				_execute_ai_tactics(0.25)
			# move_and_slide runs every frame so they slide properly
			velocity += external_force
			velocity = _avoid_water_in_velocity(velocity, delta)
			move_and_slide()
			# Skipped: _process_ramming(delta) and visual updates when far
		else:
			_execute_ai_tactics(delta)
			velocity += external_force
			velocity = _avoid_water_in_velocity(velocity, delta)
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
		
		if target and not is_far:
			if _renderer:
				_renderer.rotate_arms(target.global_position, global_position)
				_renderer.animate_legs(velocity, Time.get_ticks_msec() / 1000.0)

var external_force: Vector2 = Vector2.ZERO
var _lod_ai_timer: float = 0.0

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
		# FightShovel corn trampling (Utility-SOC: "corn-fields that leave
		# trails when walked through") - same per-mech-per-tick terrain
		# lookup this function already does, one dictionary check further.
		# No-ops instantly on any map without corn (see MapGenerator.
		# trample_corn's own guard).
		if map.map_type == "FightShovel" and map.has_method("trample_corn"):
			map.trample_corn(grid_pos)
	_in_water = is_over_water

# Prevents enemies from just walking straight into water and drowning.
# _execute_ai_tactics/_execute_search compute movement as a pure straight
# line toward whatever they're chasing/searching (global_position.
# direction_to(...)) - MapGenerator's astar_grid is built water-aware
# (water tiles marked solid, see MapGenerator._build_navigation) but is
# never actually consulted by enemy movement, so any chase/search path that
# happened to cross a lake or river turned it into an "enemies delete
# themselves in ~1s" hazard rather than a real obstacle, instead of the
# amphibious/jumpjet-gated hazard it's meant to be (see _check_drowning).
# Cheap: one lookahead terrain lookup, same cost as the existing
# _refresh_water_state() check already run every tick.
func _avoid_water_in_velocity(vel: Vector2, delta: float) -> Vector2:
	if is_amphibious or _has_jumpjets() or vel == Vector2.ZERO:
		return vel
	var map = _get_map_ref()
	if not map or not ("terrain" in map):
		return vel
	var lookahead = global_position + vel * max(delta, 0.15) # a beat ahead, not just this tick
	var grid_pos = Vector2i(int(floor(lookahead.x / map.tile_size)), int(floor(lookahead.y / map.tile_size)))
	if grid_pos.x < 0 or grid_pos.x >= map.width or grid_pos.y < 0 or grid_pos.y >= map.height:
		return vel
	if map.terrain[grid_pos.y][grid_pos.x] != map.BiomeType.WATER:
		return vel
	# Heading into water - slide along its edge instead of stopping dead
	# (a hard stop reads as "the AI got stuck"; sliding reads as avoidance).
	var tangent = Vector2(-vel.y, vel.x).normalized()
	return tangent * vel.length()

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

# Trail creation, shared between sprint (PlayerController.handle_input) and
# water-hover (both player and AI) - was inlined in player input handling,
# which meant AI mechs could never show a jet trail at all.
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
# Runs after PlayerController.handle_input in the frame, so it wins over the
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
					packet_to_fire.is_banked_shot = true
					packet_to_fire.magnitude *= current_jammer_debuff
					for k in packet_to_fire.synergies:
						packet_to_fire.synergies[k] *= current_jammer_debuff
					_apply_synergy_jamming(packet_to_fire)
					mount._fire_combined_projectile(self, packet_to_fire, data.step)
					mount.bank_current_charge = 0.0
					heat = max(0.0, heat - required * 0.6) # AI vents on auto-release too

			# Player auto-dump (Accumulator config, see auto_dump_threshold's
			# field comments): the bank releases ITSELF at its configured
			# fraction of full charge, payload scaled to the charge actually
			# banked - a lower threshold buys a faster automated rhythm at
			# proportionally lower per-volley payoff. Threshold 0 (default)
			# means this never runs and the 1/2/3 key stays the only trigger.
			var auto_t = data.packet.auto_dump_threshold
			if is_player and auto_t > 0.0 and mount.bank_current_charge >= required * auto_t:
				var banked_frac = clamp(mount.bank_current_charge / max(0.001, required), 0.0, 1.0)
				var auto_packet = data.packet.copy()
				auto_packet.is_banked_shot = true
				auto_packet.magnitude *= banked_frac * current_jammer_debuff
				for k in auto_packet.synergies:
					auto_packet.synergies[k] *= banked_frac * current_jammer_debuff
				_apply_synergy_jamming(auto_packet)
				auto_packet.magnitude *= _get_ambush_multiplier()
				if is_cloaked:
					_break_cloak()
				mount._fire_combined_projectile(self, auto_packet, data.step)
				mount.bank_current_charge = 0.0
				heat = max(0.0, heat - required * banked_frac * 0.6)
		else:
			if mount.current_charge < required:
				mount.current_charge = min(required, mount.current_charge + delta / max(0.01, fire_rate))

	# Lance mounts fire themselves - no mouse/key trigger, see
	# LanceMountTile.gd's own header comment.
	for lance in lance_mounts:
		if lance.cooldown_timer > 0.0:
			lance.cooldown_timer -= delta
		elif lance.ready_to_fire:
			lance.fire(self)

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
		# 1/2/3 key exclusively (PlayerController.fire_charged). Two independent weapons
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
# Natalia: thermal system fully commented out below (_update_heat,
# _heat_arc_damage, _overheat, and the heat_rate/ice/ltg computation block
# in _recalculate_grid) rather than just flag-gated - none of those are
# called from anywhere outside this system, so nothing else breaks. The vars
# below and the inline venting lines inside the weapon-fire functions
# elsewhere are left alone: the vars are just inert idle state now (cheap to
# leave declared, and other code still references `heat` safely), and the
# venting lines are interlocked with weapon-firing logic in those functions -
# they're harmless no-ops now that nothing ever raises heat above 0.0.
var heat: float = 0.0
var heat_rate: float = 0.0      # computed in _recalculate_grid
var heat_ice_frac: float = 0.0
var heat_ltg_frac: float = 0.0
var _heat_arc_timer: float = 0.0

# These three functions are pure heat machinery - nothing outside this
# system calls them, so they're safe to fully comment out. The inline
# venting lines elsewhere (heat = max(0.0, heat - required * 0.6) in the
# weapon-fire functions) are NOT touched here - they're interlocked with
# weapon-firing logic in those functions, and are harmless no-ops now that
# heat never leaves 0.0 with _update_heat() itself never running.
#func _update_heat(delta: float):
#	if precalculated_weapons.is_empty():
#		heat = max(0.0, heat - 10.0 * delta)
#		return
#
#	# Generation minus constant ambient dissipation. heat_rate can already
#	# be negative (ICE cooling), so heavily iced builds pin to 0 here.
#	heat = clamp(heat + (heat_rate - 2.0) * delta, 0.0, HEAT_CAPACITY)
#
#	# LIGHTNING volatility: above 70% heat, lightning-heavy storage arcs
#	# into the grid - severity proportional to current heat.
#	if heat > HEAT_CAPACITY * 0.7 and heat_ltg_frac > 0.3:
#		_heat_arc_timer -= delta
#		if _heat_arc_timer <= 0.0:
#			_heat_arc_timer = 2.0
#			_heat_arc_damage()
#
#	if heat >= HEAT_CAPACITY:
#		_overheat()

#func _heat_arc_damage():
#	# Shock a random tile in a random component - reuses the standard
#	# take_damage -> disable/reboot pipeline, no new failure states.
#	var comps = components.values()
#	if comps.is_empty():
#		return
#	var comp = comps[randi() % comps.size()]
#	var tiles = comp.hex_grid.get_all_tiles()
#	if tiles.is_empty():
#		return
#	var tile = tiles[randi() % tiles.size()]
#	tile.take_damage(heat * 0.1) # proportional to heat, not flat
#	if is_player:
#		_show_floating_text("ARC!", Color(1.0, 1.0, 0.3))

#func _overheat():
#	# Knock out one Accumulator (the thing storing all that energy) via the
#	# existing disable machinery, shed a big chunk of heat, carry on.
#	for comp in components.values():
#		for tile in comp.hex_grid.get_all_tiles():
#			if tile.tile_type == "Accumulator" and not tile.is_disabled:
#				tile.take_damage(tile.hp + 1.0)
#				heat = HEAT_CAPACITY * 0.55
#				if is_player:
#					_show_floating_text("OVERHEAT!", Color(1.0, 0.35, 0.2))
#				is_grid_dirty = true
#				# Pay the recalculation cost RIGHT NOW instead of leaving
#				# is_grid_dirty lazy for whatever _shoot() call happens to
#				# come next - same class of bug, same fix, as the deploy-time
#				# freeze (see Main._close_garage's comment). An overheat can
#				# happen mid-fight and then the player stops firing for a
#				# while (repositioning, or just noticing they're overheated);
#				# without this, THAT much-later shot is the one that
#				# synchronously eats the recalc - "hesitation when shooting
#				# the first time after not shooting for some interval." Doing
#				# it here instead bundles the cost into a moment that's
#				# already visually busy (the OVERHEAT! text/heat spike),
#				# where a brief hitch is far less jarring.
#				_recalculate_grid()
#				return
#	# No accumulator to sacrifice: vent hard instead (raw/kinetic builds
#	# shouldn't really get here - they generate almost nothing).
#	heat = HEAT_CAPACITY * 0.4

# _shoot_release() is gone. Under the old hold-to-charge model it fired
# the partial charge when the mouse was released; under the pre-prime model
# (passive charging) it fired unprompted every idle frame the moment charge
# crossed its 10% floor - the "shooting randomly" playtest bug. Partial
# releases are now exclusively the hold-1/2/3 dump in _shoot().

func _recalculate_grid():
	precalculated_weapons.clear()
	lance_mounts.clear()
	max_shield_hp = 0.0 # Reset shield HP
	has_shield_generator = false
	shield_recharge_delay = 3.0
	shield_recharge_rate = 0.0
	base_move_speed = 150.0 # Reset base speed for Jumpjets to calculate
	jumpjet_rarity = -1
	thruster_accel_bonus = -1
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
	_jammer_tiles.clear()
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
			
		# get_all_tiles() (not raw .grid.keys()) - footprint-safe, see
		# HexGridComponent.get_all_tiles's own comment.
		for t in comp.hex_grid.get_all_tiles():
			if t.has_method("generate_energy"):
				var generated = t.generate_energy(comp.hex_grid)
				for p in generated:
					p.position = t.grid_position
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
				var bank_auto_dump = 0.0
				if tile.tile_type == "Weapon Mount" and tile.grid_position:
					var bank = _get_adjacent_accumulator_bonus(comp.hex_grid, tile.grid_position)
					bank_charge = bank.charge
					bank_amplify = bank.amplify
					bank_quality = bank.quality
					bank_auto_dump = bank.auto_dump

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
					# (PlayerController.fire_charged); AI auto-releases on full
					# (_tick_weapon_charges). The mouse never fires this.
					var enhanced = combined.copy()
					enhanced.amplify(combined.acc_damage_mult * (1.0 + bank_amplify))
					enhanced.charge_required = combined.charge_required * combined.acc_charge_mult + bank_charge
					enhanced.trigger_key = combined.trigger_key if combined.trigger_key != "None" else "1"
					# Auto-dump: routed-through accumulators stamped the packet
					# already (copy/merge carry it); adjacent bank accumulators
					# contribute theirs here - highest threshold wins.
					enhanced.auto_dump_threshold = max(enhanced.auto_dump_threshold, bank_auto_dump)

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

			if tile.tile_type == "Lance Mount" and tile.has_method("check_face_gate"):
				tile.check_face_gate()
				lance_mounts.append(tile)
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
				# All modules are kept so _update_jammer_module can drain their
				# routed packet energy every frame (feeds the field's power
				# scaling) - no consume-and-discard here anymore.
				_jammer_tiles.append(tile)
				if not has_jammer_module: # first module found sets the profile
					has_jammer_module = true
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

	# Heat profile of this circuit - commented out along with the rest of the
	# thermal system (see HEAT_CAPACITY's comment above). Self-contained:
	# heat_rate/heat_ice_frac/heat_ltg_frac are only ever read by the now-
	# commented _update_heat(), so nothing else in _recalculate_grid depends
	# on this block running.
	#heat_rate = 0.0
	#var _syn_totals: Dictionary = {}
	#var _syn_sum: float = 0.0
	#for data in precalculated_weapons:
	#	heat_rate += data.packet.charge_required * 0.03
	#	for k in data.packet.synergies:
	#		_syn_totals[k] = _syn_totals.get(k, 0.0) + data.packet.synergies[k]
	#		_syn_sum += data.packet.synergies[k]
	#heat_ice_frac = (_syn_totals.get(EnergyPacket.SynergyType.ICE, 0.0) / _syn_sum) if _syn_sum > 0.0 else 0.0
	#heat_ltg_frac = (_syn_totals.get(EnergyPacket.SynergyType.LIGHTNING, 0.0) / _syn_sum) if _syn_sum > 0.0 else 0.0
	#heat_rate *= (1.0 - 2.0 * heat_ice_frac)

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

	for comp in components.values():
		_sync_contiguous_accumulator_shortcuts(comp.hex_grid)

	is_grid_dirty = false

# Every Accumulator in a hex-contiguous cluster shares one bank/shortcut
# feel: manually keying each one individually was the actual friction (place
# 3 Accumulators, set the same key 3 times) rather than a meaningful
# choice, so a cluster now auto-adopts whichever explicit key (if any) one
# of its members already has. "Lowest" key wins on a conflicting cluster
# (two different keys placed in one contiguous group) so the outcome is
# deterministic rather than depending on flood-fill visit order.
func _sync_contiguous_accumulator_shortcuts(grid: HexGridComponent):
	var visited: Dictionary = {}
	for coord_v in grid.grid.keys():
		if visited.has(coord_v):
			continue
		var tile = grid.grid[coord_v]
		if tile.tile_type != "Accumulator":
			continue

		var cluster: Array = []
		var queue = [coord_v]
		visited[coord_v] = true
		while queue.size() > 0:
			var cur_v = queue.pop_back()
			cluster.append(grid.grid[cur_v])
			var cur_coord = HexCoord.new(cur_v.x, cur_v.y)
			for d in range(6):
				var n = cur_coord.neighbor(d)
				var nv = Vector2i(n.q, n.r)
				if visited.has(nv) or not grid.grid.has(nv):
					continue
				if grid.grid[nv].tile_type == "Accumulator":
					visited[nv] = true
					queue.append(nv)

		if cluster.size() <= 1:
			continue

		var best_key = "None"
		for t in cluster:
			if t.trigger_key != "None" and (best_key == "None" or t.trigger_key < best_key):
				best_key = t.trigger_key
		if best_key != "None":
			for t in cluster:
				t.trigger_key = best_key

var _spawn_primed: bool = false

# Sums get_bank_charge()/get_bank_amplify() from every Accumulator tile
# directly hex-adjacent to `coord` within `grid` - see AccumulatorTile.gd
# and the capacitor-bank branch in the precalculated_weapons loop above.
func _get_adjacent_accumulator_bonus(grid: HexGridComponent, coord: HexCoord) -> Dictionary:
	var total_charge = 0.0
	var total_amplify = 0.0
	var worst_quality = 1.0
	var max_auto_dump = 0.0
	for d in range(6):
		var n = coord.neighbor(d)
		if grid.has_tile(n):
			var neighbor_tile = grid.get_tile(n)
			if neighbor_tile.tile_type == "Accumulator" and neighbor_tile.has_method("get_bank_charge"):
				total_charge += neighbor_tile.get_bank_charge()
				total_amplify += neighbor_tile.get_bank_amplify()
				if neighbor_tile.has_method("get_quality_factor"):
					worst_quality = min(worst_quality, neighbor_tile.get_quality_factor())
				max_auto_dump = max(max_auto_dump, float(neighbor_tile.get("auto_dump_threshold")))
	return {"charge": total_charge, "amplify": total_amplify, "quality": worst_quality, "auto_dump": max_auto_dump}

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
					
				var out_pkts = tile.process_energy(p, (dir + 3) % 6, grid, next_pos)
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
# Stuck detection while searching (see SightAndSearch._execute_search) -
# search movement is straight-line velocity + move_and_slide, so a leg
# whose line clips an obstacle pocket leaves the mech grinding a wall until
# the leg times out. Checked on a short interval; no progress = skip the leg.
var _search_stuck_timer: float = 0.0
var _search_progress_pos: Vector2 = Vector2.INF # INF = no baseline sample yet
# The last_known_player_pos the current pattern was datumed on - redatum
# triggers on intel DRIFT from this, so frontier hops (which move the datum
# away from stale intel on purpose) don't get snapped back. INF sorts as
# "never datumed" so the first search tick always initializes the pattern.
var _search_intel_pos: Vector2 = Vector2.INF

func _update_player_sight(delta: float):
	if not sight_and_search:
		sight_and_search = SightAndSearch.new(self)
	sight_and_search._update_player_sight(delta)

func _gain_sight(player_pos: Vector2):
	has_sight_of_player = true
	last_known_player_pos = player_pos


# --- Flee/wild state machine (see FLEE_THRESHOLDS block up top) ------------
func _flee_threshold() -> float:
	return FLEE_THRESHOLDS.get(combat_role, FLEE_DEFAULT_THRESHOLD)

# Only mechs holding a real wave slot (died wired to Main._on_enemy_died)
# may flee - rivals, traveling champions, and debug spawns have their own
# lifecycle accounting that a disappearing combatant would stall or corrupt.
func _is_wave_enemy() -> bool:
	for conn in died.get_connections():
		if conn.callable.get_method() == "_on_enemy_died":
			return true
	return false

# Returns true while flee/wild owns this mech's movement (caller returns).
func _update_flee_state(delta: float) -> bool:
	if _has_gone_wild:
		# Wild loiter: out of the fight, licking wounds until the director
		# recruits it into a fresh squad (Squad.add_member clears the flag).
		velocity = Vector2.ZERO
		if hp < max_hp * WILD_REGEN_CAP_FRACTION:
			hp = min(max_hp * WILD_REGEN_CAP_FRACTION, hp + max_hp * WILD_REGEN_PER_SEC_FRACTION * delta)
		if _ai_state_label:
			_ai_state_label.text = "WILD"
			_ai_state_label.modulate = Color(0.7, 0.7, 0.7)
		return true

	if not is_fleeing:
		var threshold = _flee_threshold()
		if threshold <= 0.0 or max_hp <= 0.0 or hp <= 0.0:
			return false
		if hp / max_hp > threshold:
			return false
		if not _is_wave_enemy():
			return false
		_begin_flee()

	var p = _get_player_ref()
	if not p or not is_instance_valid(p):
		_finish_flee()
		return true
	var away = global_position - p.global_position
	if away.length() >= FLEE_SAFE_DISTANCE:
		_finish_flee()
		return true
	if _ai_state_label:
		_ai_state_label.text = "FLEE"
		_ai_state_label.modulate = Color(1.0, 1.0, 0.3)
	velocity = away.normalized() * current_move_speed * speed_modifier
	return true

func _begin_flee():
	is_fleeing = true
	fled_to_wild.emit(self)
	# Leave the squad cleanly: detach every listener Squad.add_member wired
	# (so a later death or re-recruitment can't double-count into a squad
	# it already left) and hand the squad its "member gone" tick - fitness-
	# wise a deserter reads exactly like a loss, which is the point.
	if squad and is_instance_valid(squad):
		for conn in tree_exiting.get_connections():
			if conn.callable.get_method() == "_on_member_died":
				tree_exiting.disconnect(conn.callable)
		for conn in dealt_damage.get_connections():
			if conn.callable.get_method() == "_on_member_dealt_damage":
				dealt_damage.disconnect(conn.callable)
		for conn in took_damage.get_connections():
			if conn.callable.get_method() == "_on_member_took_damage":
				took_damage.disconnect(conn.callable)
		squad._on_member_died()
		squad = null

func _finish_flee():
	if _has_gone_wild:
		return
	_has_gone_wild = true
	is_fleeing = false
	target = null
	# Hand the wave slot back exactly as if this bot died (and disconnect
	# so its actual death later can't double-decrement) - a survivor hiding
	# at the map edge must never stall the wave-clear.
	for conn in died.get_connections():
		if conn.callable.get_method() == "_on_enemy_died":
			died.disconnect(conn.callable)
			conn.callable.call()
	var main = get_tree().current_scene
	if main and "world" in main and main.world and main.world.has_node("SquadDirector"):
		main.world.get_node("SquadDirector").register_wild_bot(self)

# Called by Squad.add_member when the director recruits this bot into a
# fresh squad - it rejoins the fight as a regular member.
func rejoin_from_wild():
	is_fleeing = false
	_has_gone_wild = false

func _execute_ai_tactics(delta):
	# Flee/wild states override everything below for regular wave enemies -
	# checked BEFORE target re-acquisition, or a wild bot would immediately
	# re-target the player it just escaped from.
	if not is_boss and not is_player and _update_flee_state(delta):
		return

	if not target:
		target = _get_player_ref()

	# Boss enrage/ability dispatch happens BEFORE the normal movement logic
	# below so a just-triggered teleport (blink-strike) or windup-freeze
	# (shockwave/railgun) takes effect this same frame rather than a frame
	# late. A telegraphed ability roots the boss for its windup - returning
	# early here (with velocity zeroed) is what sells "channeling."
	if is_boss:
		if not boss_brain:
			boss_brain = BossBrain.new(self)
		if _ai_state_label:
			_ai_state_label.text = "BOSS"
			_ai_state_label.modulate = Color(1.0, 0.3, 0.3)
		boss_brain.update_enrage()
		if boss_brain.is_channeling():
			boss_brain.continue_ability(delta)
			velocity = Vector2.ZERO
			return
		if target and is_instance_valid(target):
			boss_brain.tick_ability_cooldown_and_maybe_start(delta)
			if boss_brain.is_channeling():
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
				if not sight_and_search:
					sight_and_search = SightAndSearch.new(self)
				sight_and_search._execute_search(delta)
				return

		var dist = global_position.distance_to(target.global_position)
		var dir = global_position.direction_to(target.global_position)

		# Cloak hit-and-run takes priority over position_style for any boss
		# that actually has a Cloak Generator equipped (regardless of
		# archetype/ability_pool) - "liberally use the cloak" per design,
		# not just the one-shot Specter blink-strike ability.
		if is_boss and boss_brain.try_hit_and_run(delta, dist, dir):
			return

		# Boss position_style ("kiter"/"circler") takes over movement
		# entirely when it applies; "aggressive" (and every non-boss mech)
		# falls through to the shared approach/orbit logic below, unchanged.
		if is_boss and boss_brain.try_reposition(delta, dist, dir):
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

	# dominant_shield_synergy is a stringified SynergyType id (see
	# _recalculate_grid's shield block - keys come straight from packet
	# synergies dicts). A previous hand-written table here used a stale
	# numbering (3=POISON where SynergyType 3 is LIGHTNING, etc.), which
	# silently broke the elemental rock-paper-scissors for LIGHTNING/VORTEX/
	# POISON shields and gave VAMPIRIC/KINETIC shields no counters at all.
	if syn_id > 0:
		shield_str = EnergyPacket.element_name(syn_id)

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

func apply_damage(amount: float, element: String = "RAW", source: Node = null, was_reflected: bool = false):
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

	# Squad._calculate_fitness's damage-traded and reflection-punishment
	# axes (see took_damage's own field comment) - post-mitigation amount,
	# same point dealt_damage's counterpart fires from the attacker's side.
	if not is_player and amount > 0:
		took_damage.emit(amount, was_reflected)

	# Near-peer evolution premium: this victim is on the player's side
	# (is_player covers the player AND player-owned drones; the "player"
	# group membership distinguishes which) and the attacker is an enemy
	# bot - credit it (see note_priority_target_damage / fitness).
	if is_player and amount > 0 and is_instance_valid(source) \
			and source.get("is_player") == false and source.has_method("note_priority_target_damage"):
		source.note_priority_target_damage(amount, is_in_group("player"))

	if is_player and amount > 0:
		_log_incoming_damage(amount, element, source)
		var main = get_tree().current_scene
		if main and "world" in main and main.world and main.world.has_node("SquadDirector"):
			main.world.get_node("SquadDirector").log_bot_damage(amount, element)

	# Piercing "cut in half" execution: a low flat chance for any PIERCE hit
	# that actually gets past shields to instantly finish the target,
	# regardless of remaining HP. Locked exemption list per
	# FEATURE_ROADMAP.md's Decision Log - see _is_pierce_execution_exempt().
	if element == "PIERCE" and not _is_pierce_execution_exempt():
		if randf() < PIERCE_EXECUTION_CHANCE:
			_show_floating_text("EXECUTED", Color(1.0, 0.15, 0.15))
			hp = 0
			if is_player and is_instance_valid(source) and source.has_method("note_priority_kill"):
				source.note_priority_kill(is_in_group("player"))
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
		# Killing-blow premium for near-peer evolution (see note_priority_kill).
		if is_player and is_instance_valid(source) and source.has_method("note_priority_kill"):
			source.note_priority_kill(is_in_group("player"))
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
	# Hidden enemies (player currently Blind, see Main._update_player_blind_state)
	# shouldn't leak combat info through floating damage/status text - it's a
	# sibling node under `parent`, not a child of this mech, so it isn't
	# covered by the .visible toggle there automatically.
	if not is_player and not visible:
		return
	# Global popup budget (see ProjectileManager.request_floater): a bullet
	# storm shouldn't also spawn hundreds of tweened Labels per second. The
	# player's own popups always count as high-priority.
	if not ProjectileManager.request_floater(is_player):
		return
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

	if not status_runner:
		status_runner = StatusEffectRunner.new(self)
	status_runner.tick(delta)

	if is_cloaked:
		current_move_speed *= 1.25 # Sneaking in fast while unseen

	# (Ambush-window countdown now lives in CloakSystem.tick(), ticked from
	# _physics_process alongside the rest of cloak's per-frame state.)

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

# --- Cloak ---------------------------------------------------------------
# Thin wrappers only - see CloakSystem.gd for the actual charge/timer/
# visual tick and the ambush-window bonus. Both stay as real Mech methods
# (not e.g. mech.cloak_system.break_cloak()) because they're called from
# many places both inside this file and externally (BossBrain,
# PlayerController) - lazily constructing here matches the same pattern
# update_status_effects() uses for status_runner, so callers never have to
# know or care whether a CloakSystem exists yet.

func _break_cloak():
	if not cloak_system:
		cloak_system = CloakSystem.new(self)
	cloak_system.break_cloak()

func _get_ambush_multiplier() -> float:
	if not cloak_system:
		cloak_system = CloakSystem.new(self)
	return cloak_system.get_ambush_multiplier()

# --- Jammer Module (equippable ability) ---------------------------------
# Thin wrapper only - see JammerModuleSystem.gd for the actual field
# lifecycle, broadcast throttling, and synergy-pulse emission. Stays a
# real Mech method (not e.g. mech.jammer_module_system.tick()) since
# _physics_process and an existing debug check both call it directly by
# this name - lazily constructing here matches update_status_effects()'s
# status_runner pattern, so callers never have to know or care whether a
# JammerModuleSystem exists yet.
func _update_jammer_module(delta: float):
	if not jammer_module_system:
		jammer_module_system = JammerModuleSystem.new(self)
	jammer_module_system.tick(delta)

# Called by SquadDirector.broadcast_jammer_alert on every live squad member.
# Deliberately does nothing but nudge last_known_player_pos - an enemy
# that's already in a real fight (has_sight_of_player) or is a boss ignores
# this entirely; everyone else's existing _execute_search picks up the new
# datum and redatums its search pattern toward it, same as any other
# lost-sight wander trigger.
func receive_jammer_alert(approx_pos: Vector2):
	if is_boss or is_player or has_sight_of_player:
		return
	last_known_player_pos = approx_pos

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
	if not has_healer:
		return
	heal_pulse_timer -= delta
	if is_player:
		# Module-keybind ruling ("I need to be able to use every type of
		# module"): the player's Heal Beacon is a BUTTON, not an autocast -
		# press H (registered in Main._ready) when the pulse is charged.
		if heal_pulse_timer <= 0.0 and InputMap.has_action("heal_pulse") and Input.is_action_just_pressed("heal_pulse"):
			heal_pulse_timer = heal_pulse_interval
			_emit_heal_pulse()
	elif heal_pulse_timer <= 0.0:
		heal_pulse_timer = heal_pulse_interval
		_emit_heal_pulse()

func _emit_heal_pulse():
	# Allies by side: AI beacons heal their squad (the "enemy" group);
	# the player's beacon heals their companion drones.
	var allies: Array = []
	if is_player:
		var main = get_tree().current_scene
		if main and "drone_nodes" in main:
			allies = main.drone_nodes.values()
	else:
		allies = EntityCache.get_group("enemy")
	for ally in allies:
		if ally == self or not is_instance_valid(ally) or not ("hp" in ally):
			continue
		if global_position.distance_to(ally.global_position) > heal_pulse_radius:
			continue
		var healed = min(ally.max_hp, ally.hp + heal_pulse_power) - ally.hp
		ally.hp += healed
		if healed >= 1.0 and ally.has_method("_show_floating_text"):
			ally._show_floating_text("+%d" % int(round(healed)), Color(0.3, 1.0, 0.4))

	# AI beacons self-heal at half strength (the squad is the point); the
	# player's manual pulse self-heals at full - it's their button.
	var self_mult = 1.0 if is_player else 0.5
	var self_healed = min(max_hp, hp + heal_pulse_power * self_mult) - hp
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
var _boss_time_since_hit: float = 0.0
var _boss_flee_penalty: float = 0.0
const BOSS_FLEE_GRACE: float = 5.0
const BOSS_FLEE_RATE: float = 1.5

# Connected unconditionally in _ready() (see the dealt_damage.connect call
# there) - covers normal shots fired via Projectile automatically. Ability
# damage (shockwave/railgun) doesn't route through a Projectile, so
# _resolve_shockwave/_resolve_railgun call this directly after apply_damage.
# Damage/hit/survival counting itself is now shared with every mech via
# _on_own_dealt_damage/get_individual_fitness (see that field block near
# the top of the file) - this used to duplicate that exact counting into a
# separate _boss_* set of fields feeding an almost-identical formula; the
# only thing still genuinely boss-specific is resetting the flee timer.
func _on_self_dealt_damage(_amount: float):
	_boss_time_since_hit = 0.0

# Same shape as Squad._calculate_fitness (damage dealt + hits landed +
# capped survival-since-first-engagement + damage-traded/blind bonuses -
# flee penalty), just scoped to a single mech since a boss fight is
# effectively "a squad of one" - get_individual_fitness() already computes
# exactly that; flee penalty is the one piece unique to a boss (a squad can
# go quiet as a group, but this is measuring one mech refusing to engage).
# Feeds BossProfile.update_fitness via Main._on_boss_died ->
# SquadDirector._on_boss_defeated, which is what makes boss profiles evolve
# instead of just being 6 static archetypes.
func get_boss_fitness() -> float:
	return max(0.0, get_individual_fitness() - _boss_flee_penalty)

# BossBrain (a RefCounted, not a Node) can't own the dealt_damage signal
# itself - its shockwave/railgun ability resolution calls this instead of
# emitting directly, so the signal still only ever lives on the Mech node.
func _boss_emit_dealt_damage(amount: float):
	dealt_damage.emit(amount)

# --- Boss Enrage & Signature Abilities -----------------------------------
# Moved to BossBrain.gd (see Mech._execute_ai_tactics for the delegation
# call sites). _rally_speed_timer/RALLY_SPEED_MULT stay here - BossBrain's
# _do_rally() only writes into _rally_speed_timer; the countdown-and-apply
# lives below in update_status_effects, alongside several other systems'
# per-frame speed modifiers.
var _rally_speed_timer: float = 0.0
const RALLY_SPEED_MULT = 1.3

# Drained-husk terrain from VAMPIRIC kills. Globally capped so a vampiric
# build can't pave the whole map - oldest husk crumbles when the cap hits.
func _spawn_corpse_obstacle():
	var existing = get_tree().get_nodes_in_group("corpse_obstacle")
	if existing.size() >= 12 and is_instance_valid(existing[0]):
		existing[0].queue_free()

	var husk = load("res://scripts/entities/CorpseHusk.gd").new() # destructible by anything (playtest ruling)
	husk.add_to_group("corpse_obstacle")
	husk.collision_layer = 32 # terrain-obstacle layer: blocks movement and shots, jets fly over
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
			var director = main_scene.world.get_node("SquadDirector")
			director.log_player_kill(last_damage_element)
			# Credit THIS bot's own solver profile with ITS OWN individual
			# performance (see get_individual_fitness/SquadDirector.
			# credit_bot_death) - fires on every bot death regardless of
			# whether its squad ultimately wipes or wins, unlike the old
			# squad-wide crediting which only ever fired on a full wipe.
			director.credit_bot_death(self)

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

	# Tile rarity now scales with base_rarity instead of being hardcoded -
	# previously every enemy got the exact same fixed-rarity weapon tiles
	# regardless of base_rarity (only component/frame SIZE scaled), so a
	# "Mythic-tier" enemy's huge grid ended up sparsely filled with COMMON/
	# UNCOMMON/RARE gear. The offsets below preserve each role's original
	# relative shape (signature tile strongest, support tiles trail behind
	# it) rather than flattening everything to the same tier - the old
	# hardcoded ceiling was RARE (2), so that's offset 0; UNCOMMON (1) was
	# one step below that ceiling, COMMON (0) was two steps below.
	var tier = func(offset: int) -> int:
		return clamp(base_rarity - offset, HexTile.Rarity.COMMON, HexTile.Rarity.MYTHIC)

	match role_name:
		"sniper":
			add_tile.call("res://scripts/tiles/AmplifierTile.gd", tier.call(0))
			add_tile.call("res://scripts/tiles/CatalystTile.gd", tier.call(0))
			add_tile.call("res://scripts/tiles/DirectionalConduitTile.gd", tier.call(2))
		"brawler":
			add_tile.call("res://scripts/tiles/SplitterTile.gd", tier.call(1))
			add_tile.call("res://scripts/tiles/SplitterTile.gd", tier.call(1))
			add_tile.call("res://scripts/tiles/AmplifierTile.gd", tier.call(1))
		"flamethrower":
			add_tile.call("res://scripts/tiles/InfuserTile.gd", tier.call(0), 1) # FIRE
			add_tile.call("res://scripts/tiles/SplitterTile.gd", tier.call(1))
			add_tile.call("res://scripts/tiles/SplitterTile.gd", tier.call(2))
		"ambusher":
			add_tile.call("res://scripts/tiles/InfuserTile.gd", tier.call(0), 4) # KINETIC
			add_tile.call("res://scripts/tiles/AmplifierTile.gd", tier.call(1))
		"scout":
			pass # Uses basic conduits if they were available, fallback empty solver handles it
		"commander":
			# Weapons are secondary for a Commander - the Command Suite
			# backpack is the payload. Feed the solver defensive parts.
			add_tile.call("res://scripts/tiles/ShieldTile.gd", tier.call(0))
			add_tile.call("res://scripts/tiles/AccumulatorTile.gd", tier.call(0))

	# Give the solver something to actually work with: an Infuser it can
	# configure toward the spawn profile's counter-element/Pierce priority.
	# Without this, a profile could only ever reorder whatever flavor tiles
	# the role already hardcodes above - it couldn't introduce a genuinely
	# new counter-element into a role that doesn't normally use one.
	if spawn_profile != null:
		add_tile.call("res://scripts/tiles/InfuserTile.gd", tier.call(1))

	var solver = load("res://scripts/core/AutoEquipSolver.gd").new()

	if components.has(HexTile.BodySlot.TORSO):
		inventory = solver.solve(components[HexTile.BodySlot.TORSO], inventory, spawn_profile)
	if components.has(HexTile.BodySlot.ARM_R):
		inventory = solver.solve(components[HexTile.BodySlot.ARM_R], inventory, spawn_profile)
	if components.has(HexTile.BodySlot.ARM_L):
		inventory = solver.solve(components[HexTile.BodySlot.ARM_L], inventory, spawn_profile)

	_recalculate_grid()

