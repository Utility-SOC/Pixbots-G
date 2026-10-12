class_name Mech
extends CharacterBody2D

const TerrainEffects = preload("res://scripts/core/TerrainEffects.gd")

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
# Same reason as SolverProfile above - used as a bare type hint on
# _recalculate_grid_for_stock/_capture_stock_simulation_cache/_restore_
# stock_simulation_cache's `stock` parameter.
const StockBuild = preload("res://scripts/ai/StockBuild.gd")
const PlayerController = preload("res://scripts/entities/PlayerController.gd")
const BossBrain = preload("res://scripts/entities/BossBrain.gd")
const StatusEffectRunner = preload("res://scripts/entities/StatusEffectRunner.gd")
const SightAndSearch = preload("res://scripts/entities/SightAndSearch.gd")
const MagnetSystem = preload("res://scripts/entities/MagnetSystem.gd")
const CloakSystem = preload("res://scripts/entities/CloakSystem.gd")
const JammerModuleSystem = preload("res://scripts/entities/JammerModuleSystem.gd")
# Perf fix (see AutoEquipSolver.gd's own perf-instrumentation comment):
# build_loadout_for_role used to load() this fresh on every single call
# instead of a preloaded const, the pattern used everywhere else in this
# file - a small, free, zero-risk win alongside the real solver-cost
# investigation.
const AutoEquipSolverScript = preload("res://scripts/core/AutoEquipSolver.gd")
const HealBeaconSystem = preload("res://scripts/entities/HealBeaconSystem.gd")
const AegisShieldPulseSystem = preload("res://scripts/entities/AegisShieldPulseSystem.gd")
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
var heal_beacon_system: HealBeaconSystem = null

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
		_wcache_cx = -1000000 # new map: the per-tile water cache no longer applies
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
var is_vortex_immune: bool = false
var vortex_pull_protection_ratio: float = 0.0
var vortex_damage_reduction: float = 0.0
var anchor_energy: float = 0.0 # total energy fed into Anchors this recalculation (see AnchorTile.protection_for)

var current_move_speed: float = 200.0
var base_move_speed: float = 200.0

# Melee/mass physics pillar - total weight of every equipped hex tile (see
# HexTile.get_weight() and the per-tile overrides), recomputed in
# _recalculate_grid(). Drives the movement-speed penalty/bonus in
# update_status_effects() and the ramming damage formula in _process_ramming().
var total_mass: float = 0.0
var combat_role: String = "melee"

# Corporate Sponsorships (task #17): "" means unaffiliated - only bosses from
# wave 100+ ever get one (see Main._spawn_boss), rolled via
# BrandRegistry.random_brand(). Read by LootManager.generate_loot_for_mech()
# to pick which brand's tile a boss kill drops.
var brand_affiliation: String = ""

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

# Corporate Sponsorships (task #17): Shadow Systems' AllyCloakTile capacity
# fields, written directly in _collect_weapon_mounts_and_tile_capabilities()
# same as the block above (has_cloak_generator etc.) - see CloakSystem.gd's
# tick() for how these actually get used.
#   shadow_share_radius - > 0 means an Shadow cloak generator is equipped;
#     while cloaked, allies within this radius get faded/hidden too, even
#     though they don't own a cloak generator themselves.
#   shadow_stealth_fire - firing a weapon while cloaked no longer breaks
#     cloak (see the two _break_cloak() call sites in _shoot/weapon-charge
#     ticking below).
#   shadow_toggle_mode - Cloak (C) is a toggle instead of hold-to-cloak (see
#     CloakSystem.tick()'s player input branch).
var shadow_share_radius: float = 0.0
var shadow_stealth_fire: bool = false
var shadow_toggle_mode: bool = false

# Smoke Grenade backpack tile - same capacity/recharge shape as Cloak above
# (written in _collect_weapon_mounts_and_tile_capabilities(), reset in
# _reset_grid_state()), but a single-charge consumable rather than a
# continuous drain: a drop only fires once smoke_charge reaches
# max_smoke_charge, then drains to 0 and refills over smoke_recharge_time
# seconds (see try_drop_smoke_grenade()/_update_smoke_grenade() below).
var has_smoke_grenade: bool = false
var max_smoke_charge: float = 0.0
var smoke_charge: float = 0.0
var smoke_recharge_rate: float = 0.0
var smoke_radius: float = 320.0
var smoke_duration: float = 6.0

# Corporate Sponsorships (task #17): Keeneye Sensing's SensorTile capacity
# fields, written directly in _collect_weapon_mounts_and_tile_capabilities()
# same as everything above. See SensorTile.gd's header for what "bypasses
# jammers and cloaks" actually resolves to given what those two systems
# really gate in this codebase.
var has_jammer_immunity: bool = false
var has_cloak_detection: bool = false
var sensor_sight_bonus: float = 0.0

# AI counter-doctrine (SquadDirector._spawn_bot_for_role): set ONCE at spawn,
# not a loadout-derived capacity field, so it's NOT reset in
# _reset_grid_state() - same category as elemental_resistances/modulate
# tweaks the Director already sets directly on a bot at build time. Kinetic
# weapons get a huge projectile-range bonus (Projectile.gd's
# KINETIC_RANGE_BONUS) that was otherwise wasted - a bot built to counter
# the player's shield with Kinetic couldn't ever get close enough to use
# that range, since SIGHT_RANGE (the actual detection gate) never scaled
# with it. Only ever set on bots the Director deliberately kitted with
# Kinetic weapons for exactly this reason.
var kinetic_sight_bonus: float = 0.0
# Enemy element doctrine from the director (ElementCombos): {name, a, b} or {} for none; MechGridSim retints the weapons with it.
var element_combo: Dictionary = {}
# Timed buffs from capturing map objectives: type -> seconds left (see CaptureBuffs).
var capture_buffs: Dictionary = {}
# Phase Shifter (PhaseShifterTile / PhaseDrain): a powered Mythic shifter lets the mech pass through terrain obstacles;
# phase_flow is the share of energy flow left after the terrain drain (1.0 = none).
var phase_shifter_active: bool = false
var phase_flow: float = 1.0

# Corporate Sponsorships (task #17): Aegis Dynamics' AegisJammerShieldTile
# capacity fields. has_elemental_aegis is checked directly in
# _apply_shield_mitigation(); shield_pulse_* mirror heal_pulse_*'s exact
# shape and feed AegisShieldPulseSystem.gd (see its header).
var has_elemental_aegis: bool = false
var has_shield_pulse: bool = false
var shield_pulse_power: float = 0.0
var shield_pulse_radius: float = 0.0
var shield_pulse_interval: float = 4.0
var shield_pulse_timer: float = 0.0
var shield_pulse_system: AegisShieldPulseSystem = null
# Decremented every tick in CloakSystem.tick() regardless of whether THIS
# mech owns a cloak generator - refreshed by a nearby Shadow-equipped ally's
# _share_cloak_with_allies() pulse. >0 fades this mech out exactly like
# is_cloaked does, letting an ally without their own cloak generator still
# be hidden by someone else's Shadow field.
var external_cloak_timer: float = 0.0

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
# MYTHIC heal beacon "Field Repair" (see HealBeaconTile.is_field_repair / HealBeaconSystem._tick_field_repair):
# repair_energy_flow is the beacon energy per second routed into mythic beacons by the last grid recalculation,
# repair_charge banks it between pulses (survives recalculations), repair_cooldown spaces consecutive pulses.
var has_field_repair: bool = false
var repair_energy_flow: float = 0.0
var repair_charge: float = 0.0
var repair_cooldown: float = 0.0
var heal_pulse_power: float = 0.0
var heal_pulse_radius: float = 0.0
var heal_pulse_interval: float = 4.0
var heal_pulse_timer: float = 0.0

# Synergies actively muted on THIS mech by an enemy Jammer Module, mapped to
# remaining duration. Consulted when firing to suppress that element.
var jammed_synergies: Dictionary = {}

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
# raised well past its original 30,000/100 for capacitor-bank builds, a handful of loop passes on a
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
#
# Ceiling raised (user report 2026-08-05: four Mythic Magnets, ~600,000
# total_magnetic_power - already fully saturating the curve above, i.e.
# already AT the old ceiling, and it still fell well short of "should be
# able to blanket the whole map" - the default map's diagonal is
# width*height*tile_size-scale ~15,000px (400x250 tiles @ 32px, see
# _start_wave()'s density_mult), against the old max radius of only 150+
# 2500=2650px. Only the CEILING moved, not MAGNET_POWER_SCALE (the curve's
# approach speed) - a real endgame investment like this SHOULD reach that
# far, but early/mid-game magnet feel at lower power is unchanged, since
# those builds are nowhere near either ceiling to begin with.
const MAGNET_POWER_SCALE = 250.0
const MAGNET_PULL_RADIUS_MAX_BONUS = 15000.0
const MAGNET_PULL_SPEED_MAX_BONUS = 22.0


var fire_cooldown: float = 0.0
var fire_rate: float = 0.25 # 4 shots per second

var components: Dictionary = {} # Dict of HexTile.BodySlot -> ComponentEquipment
var is_grid_dirty: bool = true
var precalculated_weapons: Array = []
var _ai_shot_speed_cache: float = -1.0
var _ai_explosion_cache: float = -1.0
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

# Separation steering (the user: "mostly shuffling around really close to one
# another"): every enemy independently approaches the SAME shared flow-field
# corridor toward the player, then orbits at the same engagement_distance
# ring with no awareness of each other - with a big enough wave, that ring's
# circumference just doesn't fit everyone, so they stack up and visibly jam/
# jostle against each other's collision shapes instead of spreading into an
# actual surrounding formation. A small, throttled repulsion-from-neighbors
# nudge (classic boid "separation") blended into velocity fixes the clumping
# without touching the approach/orbit logic itself.
# SEPARATION_QUERY_INTERVAL is read by SeparationBatcher.gd (the batched
# replacement for the old per-mech timer this class used to keep itself) -
# kept here as the single source of truth for the cadence.
const SEPARATION_QUERY_INTERVAL = 0.2
const SEPARATION_RADIUS = 70.0
const SEPARATION_WEIGHT = 0.7
var _cached_separation: Vector2 = Vector2.ZERO

var separate_arm_firing: bool = false
var base_rarity: int = 0 # HexTile.Rarity.COMMON
var _stock_evo_override = null # set only by presolve_stock_build's off-tree throwaway
# Set by SquadDirector before add_child() (same pattern as combat_role/
# base_rarity below) so build_loadout_for_role() can hand it to
# AutoEquipSolver. Null means "use the solver's old fixed-priority
# behavior" - safe default for anything that doesn't set this.
var spawn_profile: SolverProfile = null
# Which SquadTemplate this bot spawned under (set by SquadDirector before
# add_child(), same pattern as combat_role/base_rarity/spawn_profile above) -
# "" for the player and anything spawned outside the normal squad-assembly
# path (debug spawns, the safety-fallback trio in Main._spawn_wave_async).
# The key StockBuildEvolution scopes cached/evolving loadouts by, alongside
# combat_role - see build_loadout_for_role().
var spawn_template_name: String = ""
# Which same-role slot within its squad this bot filled (set by SquadDirector.
# _assemble_squad before add_child(), same pattern as spawn_template_name
# above) - lets same-role squad-mates independently evolve their own
# StockBuild via StockBuildEvolution instead of always sharing one build for
# the whole role. 0 for anything spawned outside normal squad-assembly
# (debug spawns, bosses, the safety-fallback trio in Main._spawn_wave_async).
var sub_archetype_slot: int = 0
# Set by build_loadout_for_role() when this spawn rolled a deviation test
# against an existing StockBuild - SquadDirector.credit_bot_death() reads
# these to report the deviation's fitness back to StockBuildEvolution.
var _is_deviation_test: bool = false
var _force_deviation: bool = false
var _deviation_components: Dictionary = {}
# Which evolving pool entry actually shaped this bot's loadout (see build_loadout_for_role).
var _champion_build = null # StockBuild replayed as-is (gets fitness credit at death)
var _build_profile_name: String = "" # SolverProfile that produced the loadout, even when replayed from cache
# Back-reference to the Squad.gd instance this mech was recruited into (set
# by Squad.add_member()) - null for bosses and anything spawned outside the
# normal squad-assembly path. Used by the sight-sharing system below: a
# mech that spots the player broadcasts to squad.members ONLY, never
# globally, so different squads never leak sight info to each other.
var squad: Node = null
# Written by SquadTactics each planning tick: where this member should go to
# play its part in the squad plan (flank point, staging ring...), whether the
# straight line there is walkable, and a short label for the state tag.
var tactic_goal: Vector2 = Vector2.ZERO
var tactic_goal_active: bool = false
var tactic_path_clear: bool = false
var tactic_hold: bool = false
var tactic_label: String = ""
var suppress_pos: Vector2 = Vector2.ZERO # SquadTactics: aim here (the rock the player hides behind) instead of at the player
var _hazard_wary_cached: int = -1 # -1 unknown, 0 careless, 1 wary (HazardSense; fixed per bot)
func _hazard_wary() -> bool:
	if _hazard_wary_cached < 0:
		_hazard_wary_cached = 1 if HazardSense.is_wary(get_instance_id(), SaveManager.difficulty) else 0
	return _hazard_wary_cached == 1
var cover_brain = null # CoverBrain (lazy, enemies only): peek-and-hide behaviour under pressure
var is_boss: bool = false
# Set by Main._spawn_boss right after director._spawn_bot_for_role (same
# pattern as spawn_profile above). Drives which enrage style/ability
# pool/position style this specific boss uses - see the Boss Enrage &
# Signature Abilities section below. Null-safe everywhere it's read (falls
# back to role-based defaults) so a debug-menu-spawned or profile-less boss
# still works.
var boss_profile: BossProfile = null
# Set by Main._spawn_nemesis right after director._spawn_bot_for_role (same
# pattern as boss_profile above) - a Nemesis Bounty is a one-off boss built
# specifically to counter the player's own damage log, not a member of the
# evolving boss_profiles pool. Read by build_loadout_for_role() below to
# guarantee real amplification hardware on the counter-built weapon feed,
# since a bare retargeted Microcore face (SquadDirector._spawn_bot_for_role's
# counter-build) isn't enough output on its own to be a real threat - the
# user: "the microcores don't have enough output on their own... they need
# amplifiers, they need loops".
var is_nemesis: bool = false
var total_magnetic_power: float = 0.0
# -1 = attract loot of any rarity (default). Set by a Mythic Magnet's
# min_attract_rarity filter - see MagnetTile.gd.
var min_loot_attract_rarity: int = -1
var visual_seed: int = 0
# Player-only cosmetic override - see MechRenderer._rebuild_visuals()'s
# is_hero branch. Alpha 0 (the default) means "no paint chosen" and falls
# back to the hardcoded hero color. Main._setup_player() rolls/loads a
# persisted choice into this on game start; the planned Paint Rack Garage
# tab will let the player change it mid-run the same way.
var paint_color: Color = Color(0, 0, 0, 0)

signal dealt_damage(amount: float)
# New fitness-axis input (see Squad._calculate_fitness): mirrors dealt_damage
# but for the receiving side, so Squad can score damage TRADED (dealt vs.
# taken) instead of only ever looking at offense. was_reflected flags damage
# from a Mythic Magnet repel-mode bounce specifically - the user asked for the
# AI to notice when it's dying to its own reflected fire and weight
# speed/shield accordingly (see the magnet-repel flip block below).
signal took_damage(amount: float, was_reflected: bool)
signal died()
signal fled_to_wild(bot: Node)
# Fired (at most once per frame) after the equipped parts or any tile on them
# changed. The player's body art listens and redraws; other systems may too.
signal loadout_changed()

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
	# Raised from 0.35 to the old Piercing Jammer's braver 0.3 - the merged
	# support role (see SupportMech.gd) now also carries the pierce-
	# execution-immunity aura, which only protects a squad if the unit
	# stays IN the fight rather than bailing at the first sign of trouble.
	"support": 0.3,
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

# --- Individual-bot fitness tracking (the user: "individuals in types of
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
# Enemy power growth: multiplier on the energy packets this mech fires (set by the
# SquadDirector from waves since the last rebuild; see energy_scale_for_wave). 1.0 = none.
var energy_scale: float = 1.0

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
	# Perf instrumentation (bot_spawn confirmed real+dominant by live
	# playtest: 927ms/sec while actively spawning, ~all of the frame
	# budget - see FpsCounter.gd). This is the first of three candidate
	# costs inside that bucket (shape generation here, build_loadout_for_
	# role's solver/cache below, MechRenderer._rebuild_visuals further
	# down) - splitting them out so the NEXT playtest screenshot shows
	# which one actually dominates instead of guessing.
	var _t_shape = Time.get_ticks_usec()
	equip_component(ComponentEquipment.create_starter_torso(combat_role if not is_player else "", base_rarity))
	equip_component(ComponentEquipment.create_starter_arm(true, combat_role if not is_player else "", base_rarity))
	equip_component(ComponentEquipment.create_starter_arm(false, combat_role if not is_player else "", base_rarity))
	equip_component(ComponentEquipment.create_starter_leg(true, combat_role if not is_player else "", base_rarity))
	equip_component(ComponentEquipment.create_starter_leg(false, combat_role if not is_player else "", base_rarity))
	equip_component(ComponentEquipment.create_starter_head(combat_role if not is_player else "", base_rarity))
	equip_component(_create_role_backpack(combat_role if not is_player else "", base_rarity))
	_perf_shape_gen_usec += Time.get_ticks_usec() - _t_shape

	if not is_player:
		visual_seed = randi()

		# Desync throttled per-mech timers (the user: "freezing is still
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
		_sight_check_timer = SimRng.stream("combat").randf() * (1.0 / SIGHT_CHECK_HZ)
		_search_waypoint_timer = SimRng.stream("combat").randf() * SEARCH_WAYPOINT_INTERVAL
		_mosey_timer = SimRng.stream("combat").randf() * MOSEY_UPDATE_INTERVAL
		# Per-mech personal drift bias for _mosey_toward_target - without
		# this every far mech beelines the exact same flow-field direction,
		# which reads as a single-file conga line and (per the user) has a
		# whole wave's worth of mechs arriving at the LOD boundary bunched
		# together instead of spread out. A small fixed heading offset,
		# rolled once and kept for the mech's whole life, gives each one its
		# own consistent amble angle instead of a robotic identical line.
		_mosey_wander_offset = SimRng.stream("combat").randf_range(-0.4, 0.4)

	if not is_player:
		var _t_loadout = Time.get_ticks_usec()
		build_loadout_for_role(combat_role)
		_perf_build_loadout_usec += Time.get_ticks_usec() - _t_loadout

	# Attach Visual Renderer
	var _t_visuals = Time.get_ticks_usec()
	var renderer = load("res://scripts/visuals/MechRenderer.gd").new()
	renderer.name = "MechRenderer"
	add_child(renderer)
	_renderer = renderer

	# Pass the full components dict so the renderer can draw each piece
	renderer.components = components
	renderer._rebuild_visuals()
	_perf_visual_build_usec += Time.get_ticks_usec() - _t_visuals
	if not is_player:
		_perf_bots_built += 1

	# Collision shape - sized to match this mech's actual visual scale
	# (role-based, e.g. scout renders ~0.8x, brawler ~1.2x, boss up to 1.8x
	# before the extra mega/regular boss node-scale on top) rather than
	# every role sharing the same fixed 40x40 box regardless of how big or
	# small it actually looks on screen.
	var hitbox_scale = renderer.get_role_scale(combat_role, is_player)
	var collision = CollisionShape2D.new()
	_body_shape = collision
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

# Generic version of refresh_boss_visuals() above, for any other case where
# a visual-affecting field (paint_color, equipped components, etc.) changes
# after the renderer already built once - e.g. applying a paint choice.
func refresh_visuals():
	_visuals_stale = false
	if _renderer:
		_renderer._rebuild_visuals()
		if is_player and _body_shape:
			# Silhouette width may nudge the hitbox, capped (see get_hero_width_factor).
			_body_shape.shape.size = Vector2(40, 40) * _renderer.get_role_scale(combat_role, true) * Vector2(_renderer.get_hero_width_factor(), 1.0)

func _create_role_backpack(role: String, p_rarity: int) -> ComponentEquipment:
	return _get_MechLoadoutBuilder()._create_role_backpack(role, p_rarity)

# -1 if no over-reliance is currently flagged, or no director exists yet
# (e.g. very first spawns before any kills have been logged) - also -1 if
# this Mech isn't in the scene tree at all yet (Mech.prewarm_stock_build's
# throwaway bots deliberately never get add_child()'d, see that function's
# own header). is_inside_tree() check comes FIRST and unconditionally -
# get_tree() itself logs an engine-level error when called on a node with
# no tree (still returns null, but noisily), so it must never be called
# speculatively.
func _get_reactive_jam_synergy() -> int:
	if not is_inside_tree():
		return -1
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
	_watch_component(comp)
	_notify_loadout_changed()
	
# Tile edits only matter for the hero (enemy loadouts are built wholesale and
# drawn once), so only the player hooks the per-grid change signal.
func _watch_component(comp) -> void:
	if is_player and comp.hex_grid and not comp.hex_grid.changed.is_connected(_notify_loadout_changed):
		comp.hex_grid.changed.connect(_notify_loadout_changed)

func _unwatch_component(comp) -> void:
	if comp.hex_grid and comp.hex_grid.changed.is_connected(_notify_loadout_changed):
		comp.hex_grid.changed.disconnect(_notify_loadout_changed)

var _loadout_signal_queued: bool = false
var _body_shape: CollisionShape2D = null
var _visuals_stale: bool = false
func _notify_loadout_changed() -> void:
	if _loadout_signal_queued or not is_inside_tree():
		return
	_loadout_signal_queued = true
	_flush_loadout_changed.call_deferred()

func _flush_loadout_changed() -> void:
	_loadout_signal_queued = false
	if not is_inside_tree():
		return
	loadout_changed.emit()
	if is_player and _renderer:
		# Mid-garage the world is paused and hidden under the menu: just mark
		# stale; Main's deploy transition (refresh_visuals) redraws once.
		if get_tree().paused:
			_visuals_stale = true
		else:
			if is_grid_dirty:
				_recalculate_grid()
			refresh_visuals()

func unequip_component(slot: HexTile.BodySlot) -> ComponentEquipment:
	if components.has(slot):
		var comp = components[slot]
		components.erase(slot)
		remove_child(comp)
		is_grid_dirty = true
		_unwatch_component(comp)
		_notify_loadout_changed()
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
	if phase_shifter_active or (_has_jumpjets() and _jets_firing()):
		collision_mask &= ~OBSTACLE_LAYER
	else:
		collision_mask |= OBSTACLE_LAYER

# --- Perf instrumentation (temporary, for the drones/enemies-tanking-fps
# investigation - see FpsCounter.gd's 4th breakdown line) - aggregate
# wall-clock time spent in the AI-tactics path, weapon-fire path, and
# move_and_slide() across every mech/drone, read + reset once a second by
# FpsCounter. Not mutually exclusive: an AI mech's ai_tactics time INCLUDES
# its own _shoot() call (that's what _execute_ai_tactics invokes to fire) -
# shoot_usec counts that same cost again on its own so weapon-fire cost can
# be read in isolation, and also captures the player's + drones' own shots,
# neither of which go through _execute_ai_tactics at all.
static var _perf_ai_tactics_usec: int = 0
static var _perf_shoot_usec: int = 0
static var _perf_move_usec: int = 0
# Breakdown of the "bot_spawn" bucket confirmed dominant by live playtest
# (927ms/sec while actively spawning - see SquadDirector._perf_bot_spawn_
# usec's own comment). Three candidate costs inside Mech._ready(), split
# out so the next playtest screenshot shows which one actually dominates.
static var _perf_shape_gen_usec: int = 0
static var _perf_bots_built: int = 0 # non-player Mechs whose _ready finished (BenchGame per-bot averages)
static var _perf_build_loadout_usec: int = 0
static var _perf_visual_build_usec: int = 0
# build_loadout_for_role's own internal breakdown (2026-08-10 playtest,
# wave 172, 3fps: solve()'s OWN breakdown - AutoEquipSolver._perf_bfs_usec
# etc. - read all 0ms while build_loadout itself read 1716ms, meaning the
# cost isn't inside solve() at all. Four candidate regions inside build_
# loadout_for_role that were never separately measured before now:
#   stock_lookup: StockBuildEvolution.get_stock_build()'s own linear scan
#     over director.stock_builds - prime suspect, since the sub-archetype
#     slot rework (this same session) can multiply that array's size up
#     to 3x per (template, role, rarity).
#   stock_replay: the per-tile SaveManager._deserialize_tile() loop when
#     reusing a cached stock build (the common case once a role/template/
#     rarity/slot has stabilized).
#   fresh_inventory: building the solver's input inventory (add_tile calls,
#     role-specific tiles, Nemesis/profile/amplifier injection) BEFORE
#     solver.solve() is ever called - only happens on a stock miss/
#     deviation-test roll.
#   post_solve_serialize: SaveManager._serialize_component() + establish/
#     deviation-tracking AFTER solve() returns - also stock-miss/deviation-
#     test only.
static var _perf_stock_lookup_usec: int = 0
static var _perf_stock_replay_usec: int = 0
static var _perf_fresh_inventory_usec: int = 0
static var _perf_post_solve_serialize_usec: int = 0
# Direct per-region instrumentation for the CHASE branch of
# _execute_ai_tactics (see scripts/debug/MechPhysicsCostDiagnostic.gd) -
# added because comparing whole-config deltas (with/without separation,
# with/without shoot) came back noisy/contradictory at the ~10-20ms scale
# involved. Wrapping each candidate region directly, in the SAME run,
# removes cross-config noise entirely - this is a real measurement, not an
# inference from subtraction.
static var _perf_sight_usec: int = 0
static var _perf_flow_field_usec: int = 0
static var _perf_orbit_raycast_usec: int = 0
static var _perf_separation_usec: int = 0
# Phase 0 of the AI-tactics Rust-cutover plan (see
# C:\Users\Utility\.claude\plans\effervescent-drifting-kazoo.md) - these three
# isolate the specific raycast/rebuild fractions that decide whether Phases
# 1/3/4 are worth porting at all, same "measure first" discipline as every
# other Rust port this session. _perf_sight_usec already wraps the WHOLE
# _update_player_sight call (range check + raycast); this isolates just the
# raycast sub-cost within it, since only the raycast is a Phase 1 grid-LOS
# candidate. _perf_flow_field_rebuild_usec wraps MapGenerator._rebuild_flow_field
# itself (the bounded BFS) - distinct from _perf_flow_field_usec, which only
# ever measured the O(1) per-mech get_flow_direction lookup.
static var _perf_sight_raycast_usec: int = 0
static var _perf_flow_field_rebuild_usec: int = 0
static var _perf_boss_retreat_raycast_usec: int = 0
# Simulation-LOD investigation (task #34): these three wrap the
# ALWAYS-RUN _physics_process preamble - update_status_effects,
# _tick_weapon_charges, and the cloak/jammer/healer/shield-pulse ability
# systems' .tick() calls - which run for EVERY mech every tick regardless
# of near/far/engaged status, unlike the AI-tactics/move_and_slide path
# which already has a far-branch LOD gate. An earlier MechPhysicsCostDiagnostic.gd
# run flagged this exact preamble as unexplored ("needs its own bisection
# round"); this is that round.
static var _perf_status_effects_usec: int = 0
static var _perf_weapon_charges_usec: int = 0
static var _perf_ability_systems_usec: int = 0
# FpsCounter.gd reads-AND-RESETS _perf_ai_tactics_usec/_perf_shoot_usec/
# _perf_move_usec once/sec for its own HUD (see FpsCounter.gd:226-228) -
# since it's a real autoload, it's active even in a headless diagnostic and
# races any longer-than-1s measurement window, silently zeroing those three
# mid-run. This wraps the exact same _execute_ai_tactics() call site as
# _perf_ai_tactics_usec, under a name nothing else knows about or resets,
# so a diagnostic spanning more than a second gets one reliable total.
static var _perf_diag_ai_tactics_usec: int = 0
static var _perf_diag_shoot_usec: int = 0

# Perf plan (wave-138 playtest: 2fps, "shoot 466ms/sec" dwarfing everything
# else on the overlay) - splits that one bucket into "ticks where a weapon
# actually fired" vs. "ticks that paid the full charge-check/tax-math
# overhead but had nothing ready" (see Mech._shoot's own comment). FpsCounter
# reads-AND-RESETS these two once/sec exactly like _perf_shoot_usec itself -
# _perf_shoot_usec is left untouched so nothing that already reads it breaks.
static var _perf_shoot_fired_usec: int = 0
static var _perf_shoot_checked_only_usec: int = 0
# Diagnostic-only (see _perf_diag_shoot_usec's own comment just above for why
# this needs to be separate from anything FpsCounter resets) - a plain
# free-running fire-event count, never touched by FpsCounter. Headless
# checks zero it themselves before measuring a window, then read the delta.
static var _perf_diag_shots_fired_count: int = 0
# Companion counter to the one above - every _shoot() CALL (fired or not),
# vs. _perf_diag_shots_fired_count's fired-only count. The gap between the
# two is exactly the AI_SHOOT_CHECK_HZ throttle's win: a headless check can
# assert this call count drops while the fired count stays the same (see
# _ai_shoot_timer's own comment).
static var _perf_diag_shoot_call_count: int = 0

# Diagnostic-only bypass for move_and_slide() on the AI branches below (see
# scripts/debug/MechPhysicsCostDiagnostic.gd) - isolates move_and_slide's own
# PhysicsServer2D sweep/solve cost from everything else in this function.
# Defaults false and is never touched by real gameplay code; only the
# diagnostic sets it on its own throwaway test mechs.
var _diag_skip_move_and_slide: bool = false
# Diagnostic-only: skips the ENTIRE "far" (mosey) branch body below (flee
# check, mosey movement, water-avoidance, move_and_slide) - a coarse binary
# split to prove/disprove the cost lives somewhere in that branch at all,
# before trying to isolate which specific line. Same real-gameplay-safe
# convention as _diag_skip_move_and_slide above.
var _diag_skip_far_branch_body: bool = false
# Diagnostic-only: isolate the near/CHASE branch's throttled separation
# query and its engagement-range _shoot() attempt independently (see
# scripts/debug/MechPhysicsCostDiagnostic.gd's Config X follow-up).
var _diag_skip_separation: bool = false
var _diag_skip_shoot: bool = false

# Part hitboxes (Area2D) mirror this body's collision layer. Each one used to poll it every physics tick
# (~480 script calls a step at wave 35); they now register here and the body re-syncs them every
# HITBOX_SYNC_TICKS ticks (staggered per instance), plus immediately when activated from the bot pool.
const HITBOX_SYNC_TICKS = 10
var _hitboxes: Array = []

func register_hitbox(h: Node) -> void:
	_hitboxes.append(h)

func sync_hitbox_layers() -> void:
	var stale = false
	for h in _hitboxes:
		if not is_instance_valid(h):
			stale = true
		elif h.collision_layer != collision_layer:
			h.collision_layer = collision_layer
	if stale:
		_hitboxes = _hitboxes.filter(func(x): return is_instance_valid(x))

# Crowd LOD: with many enemies alive, mechs that are not in the player's face run the per-tick systems
# (weapon charges, status, ability systems, AI tactics) every 2nd/3rd physics tick, staggered by instance id,
# passing the ACCUMULATED elapsed time so charge/DoT totals stay exact (same trade as the far-mech 4 Hz
# throttle below, just applied to near mechs when the crowd is large). Measured at wave 34 (~120 enemies):
# these systems were ~250 ms of every second; see docs/DEBUG_ROOM.md and the 2026-10-06 bisect.
# Diagnostic A/B toggle: true = call the jammer/healer/shield-pulse ticks every tick even when the mech has none
# (their early exits are no-ops, so skipping the calls is behaviour-identical - see the call sites).
static var diag_no_ability_gate: bool = false
static var crowd_lod_enabled: bool = false # off: A/B at wave 34 showed no fps gain (5.8 vs 6.2), see DebugRoom --crowdlod
# Diagnostic (DebugRoom --stage=N): enemies return from _physics_process after section N (99 = run it all).
# 0 top, 1 hitbox/water preamble, 2 status, 3 weapon charges, 5 ability systems, 6 AI tactics, 7 move.
static var diag_stage_limit: int = 99
const CROWD_LOD_MID := 30 # live enemies at/above which divisor 2 applies
const CROWD_LOD_HIGH := 60 # ... divisor 3
const CROWD_LOD_CLOSE_SQ := 350.0 * 350.0 # inside this range of the target a mech always ticks every frame
static var _crowd_frame: int = -1
static var _crowd_n: int = 0
var _lod_mid_elapsed: float = 0.0

static func crowd_divisor(crowd: int, dist_sq: float) -> int:
	if dist_sq < CROWD_LOD_CLOSE_SQ:
		return 1
	if crowd >= CROWD_LOD_HIGH:
		return 3
	if crowd >= CROWD_LOD_MID:
		return 2
	return 1

func _physics_process(delta: float):
	if diag_stage_limit < 1 and not is_player:
		return
	_own_time_alive += delta
	if (Engine.get_physics_frames() + get_instance_id()) % HITBOX_SYNC_TICKS == 0:
		sync_hitbox_layers()
	current_jammer_debuff = 1.0 # Reset every frame, JammerMech will re-apply it before we shoot if near
	_refresh_water_state()
	_update_obstacle_phasing()
	if diag_stage_limit < 2 and not is_player:
		return

	if is_drowning:
		drown_timer -= delta
		scale = Vector2.ONE * (drown_timer)
		modulate.a = drown_timer
		if drown_timer <= 0:
			die()
		return
		
	# Simulation LOD (task #34, extended): a non-player, non-boss mech far
	# from its target already skips full AI-tactics/shooting (see the near/
	# far branch below), so running the preamble below at full 60Hz
	# precision is pure waste in the meantime. Computed here (hoisted above
	# update_status_effects, which used to run before this existed) so every
	# throttled piece in the preamble can share it. Same 4Hz cadence already
	# established for far bosses' AI-tactics (_lod_ai_timer) and far weapon
	# charges (_lod_weapon_charge_timer) - not skipped outright, so DoT/
	# ability effects are still progressing, just less precisely metered,
	# and land close to on-time whenever the mech actually closes to
	# engagement range.
	var _is_far_for_lod = not is_player and not is_boss and target and is_instance_valid(target) and global_position.distance_squared_to(target.global_position) > 1400.0 * 1400.0

	# Crowd LOD gate (see crowd_divisor). _crowd_skip = skip the throttled systems this tick;
	# _sys_delta = the elapsed time they should be advanced by when they do run.
	var _crowd_skip := false
	var _sys_delta := delta
	if crowd_lod_enabled and not is_player and not is_boss and not _is_far_for_lod and target and is_instance_valid(target):
		var _pf := Engine.get_physics_frames()
		if _crowd_frame != _pf:
			_crowd_frame = _pf
			_crowd_n = EntityCache.get_group(&"enemy").size()
		var _div := crowd_divisor(_crowd_n, global_position.distance_squared_to(target.global_position))
		if _div > 1:
			_lod_mid_elapsed += delta
			if (_pf + get_instance_id()) % _div != 0:
				_crowd_skip = true
			else:
				_sys_delta = _lod_mid_elapsed
				_lod_mid_elapsed = 0.0
		elif _lod_mid_elapsed > 0.0:
			_sys_delta = _lod_mid_elapsed + delta
			_lod_mid_elapsed = 0.0
	elif _lod_mid_elapsed > 0.0:
		_sys_delta = _lod_mid_elapsed + delta
		_lod_mid_elapsed = 0.0

	var _t_status = Time.get_ticks_usec()
	# update_status_effects recomputes current_move_speed AND runs the real
	# per-effect DoT/duration tick (status_runner.tick, delta-scaled damage)
	# as one atomic unit - throttled as a whole here rather than split, same
	# as _tick_weapon_charges below. current_move_speed staying stale for up
	# to 0.25s is the same tier of imperceptible-while-off-screen tradeoff as
	# every other throttled piece; DoT totals stay exactly correct since the
	# accumulated elapsed time is what actually gets applied, just in fewer/
	# larger increments (confirmed: StatusEffectRunner.gd's damage effects
	# are all `amount * delta`, not fixed-per-tick).
	if _is_far_for_lod:
		_lod_status_timer -= delta
		_lod_status_elapsed += delta
		if _lod_status_timer <= 0.0:
			_lod_status_timer = 0.25
			update_status_effects(_lod_status_elapsed)
			_lod_status_elapsed = 0.0
	elif _lod_status_elapsed > 0.0:
		update_status_effects(_lod_status_elapsed + delta)
		_lod_status_elapsed = 0.0
	elif not _crowd_skip:
		update_status_effects(_sys_delta)
	_perf_status_effects_usec += Time.get_ticks_usec() - _t_status
	if diag_stage_limit < 3 and not is_player:
		return

	if fire_cooldown > 0:
		fire_cooldown -= delta

	var _t_weapon_charges = Time.get_ticks_usec()
	# Measured the single biggest piece of the always-run preamble
	# (5.09us/mech-tick of 10.86us total, MechPreamblePerfCheck.gd).
	# Accumulates elapsed time between ticks and passes THAT as delta so the
	# total charge over time still matches, same pattern
	# Projectile._pull_nearby_items already uses for its own throttled tick.
	if _is_far_for_lod:
		_lod_weapon_charge_timer -= delta
		_lod_weapon_charge_elapsed += delta
		if _lod_weapon_charge_timer <= 0.0:
			_lod_weapon_charge_timer = 0.25
			_tick_weapon_charges(_lod_weapon_charge_elapsed)
			_lod_weapon_charge_elapsed = 0.0
	elif _lod_weapon_charge_elapsed > 0.0:
		# Just transitioned back from far to near mid-cycle - flush whatever
		# elapsed time was pending from the throttled phase (up to 0.25s)
		# into this tick instead of silently dropping it, so a mech closing
		# to engagement range never loses real charge progress it already
		# "earned" while far.
		_tick_weapon_charges(_lod_weapon_charge_elapsed + delta)
		_lod_weapon_charge_elapsed = 0.0
	elif not _crowd_skip:
		_tick_weapon_charges(_sys_delta)
	_perf_weapon_charges_usec += Time.get_ticks_usec() - _t_weapon_charges
	if diag_stage_limit < 4 and not is_player:
		return
	# _update_heat(delta) # Thermal system commented out per the user - see the
	# heat block near HEAT_CAPACITY below for the rest of what's disabled.

	time_since_last_hit += delta
	if has_shield_generator and max_shield_hp > 0 and time_since_last_hit >= shield_recharge_delay:
		if shield_hp < max_shield_hp:
			shield_hp = min(max_shield_hp, shield_hp + shield_recharge_rate * delta * phase_flow)

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

	# Four ability-system ticks, each independently throttled (own timer/
	# elapsed pair) rather than sharing one - CloakSystem/JammerModuleSystem/
	# HealBeaconSystem/AegisShieldPulseSystem all already early-exit fast
	# when the mech doesn't have the relevant part equipped, but the
	# early-exit ITSELF still costs something 4 separate times every tick
	# (measured ~3.91-4.02us/mech-tick combined even for starter-torso mechs
	# with none of these equipped) - throttling still helps regardless of
	# whether the ability is actually equipped. Pulse intervals for
	# heal/shield/jammer (3-8s) are vastly larger than the 0.25s throttle
	# window, so this can't perceptibly delay a real pulse.
	var _t_abilities = Time.get_ticks_usec()
	if not cloak_system:
		cloak_system = CloakSystem.new(self)
	if _is_far_for_lod:
		_lod_cloak_timer -= delta
		_lod_cloak_elapsed += delta
		if _lod_cloak_timer <= 0.0:
			_lod_cloak_timer = 0.25
			cloak_system.tick(_lod_cloak_elapsed)
			_lod_cloak_elapsed = 0.0
	elif _lod_cloak_elapsed > 0.0:
		cloak_system.tick(_lod_cloak_elapsed + delta)
		_lod_cloak_elapsed = 0.0
	elif not _crowd_skip:
		cloak_system.tick(_sys_delta)

	# Smoke Grenade charge regen - a single min()/add, not worth the same
	# LOD-throttling apparatus as the four systems above (their own
	# comment's ~4us/tick measurement was for real per-frame work; this
	# is one float addition).
	if has_smoke_grenade:
		smoke_charge = min(max_smoke_charge, smoke_charge + smoke_recharge_rate * delta)
		# Player input, same "check the raw action directly here" convention
		# HealBeaconSystem.gd uses for "heal_pulse" - Ctrl held. try_drop_
		# smoke_grenade() itself no-ops until charge is full, so holding
		# naturally rate-limits to one drop per recharge cycle rather than
		# spamming every physics frame.
		if is_player and InputMap.has_action("smoke_grenade") and Input.is_action_pressed("smoke_grenade"):
			try_drop_smoke_grenade()

	if _is_far_for_lod:
		_lod_jammer_timer -= delta
		_lod_jammer_elapsed += delta
		if _lod_jammer_timer <= 0.0:
			_lod_jammer_timer = 0.25
			_update_jammer_module(_lod_jammer_elapsed)
			_lod_jammer_elapsed = 0.0
	elif _lod_jammer_elapsed > 0.0:
		_update_jammer_module(_lod_jammer_elapsed + delta)
		_lod_jammer_elapsed = 0.0
	elif not _crowd_skip and (diag_no_ability_gate or has_jammer_module or jammer_field != null or not _jammer_tiles.is_empty()):
		_update_jammer_module(_sys_delta)

	if _is_far_for_lod:
		_lod_healer_timer -= delta
		_lod_healer_elapsed += delta
		if _lod_healer_timer <= 0.0:
			_lod_healer_timer = 0.25
			_update_healer(_lod_healer_elapsed)
			_lod_healer_elapsed = 0.0
	elif _lod_healer_elapsed > 0.0:
		_update_healer(_lod_healer_elapsed + delta)
		_lod_healer_elapsed = 0.0
	elif not _crowd_skip and (diag_no_ability_gate or has_healer):
		_update_healer(_sys_delta)

	if _is_far_for_lod:
		_lod_shieldpulse_timer -= delta
		_lod_shieldpulse_elapsed += delta
		if _lod_shieldpulse_timer <= 0.0:
			_lod_shieldpulse_timer = 0.25
			_update_shield_pulse(_lod_shieldpulse_elapsed)
			_lod_shieldpulse_elapsed = 0.0
	elif _lod_shieldpulse_elapsed > 0.0:
		_update_shield_pulse(_lod_shieldpulse_elapsed + delta)
		_lod_shieldpulse_elapsed = 0.0
	elif not _crowd_skip and (diag_no_ability_gate or has_shield_pulse):
		_update_shield_pulse(_sys_delta)
	_perf_ability_systems_usec += Time.get_ticks_usec() - _t_abilities
	if diag_stage_limit < 6 and not is_player:
		return

	if is_player:
		if not player_controller:
			player_controller = PlayerController.new(self)
		player_controller.handle_input(delta)
		velocity += external_force
		SimPhysics.move(self)
		_process_ramming(delta)
		_process_reactive_plating_cooldowns(delta)
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
			is_far = global_position.distance_squared_to(target.global_position) > 1400.0 * 1400.0

		if is_far:
			if _diag_skip_far_branch_body:
				pass # diagnostic: entire far-branch body (flee/mosey/water-avoid/move_and_slide) skipped
			elif is_boss:
				# Bosses keep full AI tactics even far - only ever one at a
				# time, so the perf case for mosey (up to 80 far mechs
				# paying for search/sight logic they don't need yet) doesn't
				# apply, and a boss's kit/behavior matters more than the
				# savings would.
				_lod_ai_timer -= delta
				if _lod_ai_timer <= 0.0:
					_lod_ai_timer = 0.25 # 4 AI ticks per second when far
					var _t_ai = Time.get_ticks_usec()
					_execute_ai_tactics(0.25)
					_perf_ai_tactics_usec += Time.get_ticks_usec() - _t_ai
			elif not _update_flee_state(delta):
				# Not fleeing/wild - mosey instead of full _execute_ai_tactics
				# (see _mosey_toward_target's own header comment for why).
				_mosey_toward_target(delta)
			# else: _update_flee_state already set velocity itself (FLEE/WILD)
			# move_and_slide runs every frame so they slide properly
			if not _diag_skip_far_branch_body:
				velocity += external_force
				_apply_terrain_to_ai_velocity(delta)
				velocity = _avoid_water_in_velocity(velocity, delta)
				var _t_move = Time.get_ticks_usec()
				if _diag_skip_move_and_slide:
					position += velocity * delta
				else:
					SimPhysics.move(self)
				_perf_move_usec += Time.get_ticks_usec() - _t_move
			# Skipped: _process_ramming(delta) and visual updates when far
		else:
			var _t_ai2 = Time.get_ticks_usec()
			if not _crowd_skip:
				_execute_ai_tactics(_sys_delta)
			var _ai2_elapsed = Time.get_ticks_usec() - _t_ai2
			_perf_ai_tactics_usec += _ai2_elapsed
			_perf_diag_ai_tactics_usec += _ai2_elapsed
			if diag_stage_limit < 7:
				return
			velocity += external_force
			_apply_terrain_to_ai_velocity(delta)
			velocity = _avoid_water_in_velocity(velocity, delta)
			var _t_move2 = Time.get_ticks_usec()
			if _diag_skip_move_and_slide:
				position += velocity * delta
			else:
				SimPhysics.move(self)
			_perf_move_usec += Time.get_ticks_usec() - _t_move2
			_process_ramming(delta)
			_process_reactive_plating_cooldowns(delta)

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
# Simulation LOD (task #34) for _tick_weapon_charges - see the call site in
# _physics_process. Same 4Hz-while-far philosophy as _lod_ai_timer above,
# just applied to non-boss mechs' weapon-charge accumulation instead of
# full AI-tactics. Randomized start (thundering-herd avoidance, same
# convention as Projectile.gd's throttled query timers) even though the
# cost here is pure GDScript loop math, not a physics-server round trip -
# spreads the periodic catch-up work across frames instead of bursting the
# whole far population on the same tick.
var _lod_weapon_charge_timer: float = SimRng.stream("combat").randf() * 0.25
var _lod_weapon_charge_elapsed: float = 0.0

# Perf plan (wave-138 playtest: "shoot 466ms/sec" dwarfing everything else)
# - every non-player, non-boss mech in engagement range calls _shoot() on
# EVERY physics tick with no fire-rate gate at that call site at all (only
# an internal charge-check inside _shoot_impl, which still pays the tax/
# jamming-math overhead in full even on ticks where nothing was ready).
# Weapon charge accumulation itself is untouched by this - _tick_weapon_
# charges already runs unthrottled and safely clamps at the required
# amount (Mech.gd's own _lod_weapon_charge_timer/_tick_weapon_charges), so
# gating the CHECK doesn't change WHEN a ready weapon fires, only how often
# the AI re-runs the surrounding overhead while genuinely nothing is ready.
# AI_SHOOT_CHECK_HZ (20) was picked with real margin over the fastest real
# fire cadence found across the weapon-tuning space: default fire_rate is
# 0.25 (4Hz), the fastest SquadDirector.gd override is 0.15 (~6.7Hz), and
# even the rare worst case - that fast an override COMBINED with the
# maximum Reverse Accumulator charge_required discount (floored at 0.75,
# Mech.gd's _collect_weapon_mounts_and_tile_capabilities) - tops out
# around ~19Hz. 20Hz still meaningfully cuts overhead (60Hz physics -> 20Hz
# checks = 1/3 the calls) while staying at or above every real cadence
# found; any residual delay-to-first-shot-after-ready is bounded to one
# throttle interval and self-corrects every cycle, it never compounds into
# an actual DPS loss. Randomized start offset (thundering-herd avoidance),
# same convention as _lod_weapon_charge_timer above. Bosses are excluded
# entirely (see the call site) - matches this file's existing stance that
# a boss's kit/behavior matters more than the savings would.
const AI_SHOOT_CHECK_HZ = 20.0
var _ai_shoot_timer: float = SimRng.stream("combat").randf() * (1.0 / AI_SHOOT_CHECK_HZ)

# Simulation LOD (task #34 follow-up) - same throttle-while-far pattern as
# _lod_weapon_charge_timer/_lod_weapon_charge_elapsed above, extended to the
# rest of the always-run preamble (update_status_effects + the 4 ability-
# system ticks). Measured combined cost of these five ~7.1us/mech-tick
# (MechPreamblePerfCheck.gd) - real but individually smaller than weapon
# charges, and every one confirmed safe to throttle via the SAME elapsed-
# accumulator approach (DoT damage/pulse intervals are delta-scaled, so
# accumulating real time and applying it in fewer/larger increments
# preserves exact totals - only expiry/pulse timing precision gets coarser,
# by at most one throttle interval, imperceptible for an off-screen mech).
# Five separate field pairs rather than a shared helper - matches this
# codebase's existing preference for explicit per-site state over
# abstracting a handful of call sites, and avoids Callable-construction
# overhead on a hot path.
var _lod_status_timer: float = 0.0
var _lod_status_elapsed: float = 0.0
var _lod_cloak_timer: float = 0.0
var _lod_cloak_elapsed: float = 0.0
var _lod_jammer_timer: float = 0.0
var _lod_jammer_elapsed: float = 0.0
var _lod_healer_timer: float = 0.0
var _lod_healer_elapsed: float = 0.0
var _lod_shieldpulse_timer: float = 0.0
var _lod_shieldpulse_elapsed: float = 0.0

# --- Mosey: cheap passive approach for far (LOD'd) mechs -------------------
# Per the user: far mechs shouldn't pay for full _execute_ai_tactics (sight
# raycast, separation shape query, flow-field consultation, weapon-fire
# dispatch) just to end up running _execute_search's frontier-wander anyway,
# since a mech >1400 units out essentially never has sight of the player.
# Mosey replaces all of that with a direction lookup + a slow, personally-
# offset amble - no physics queries at all, deferring the real (expensive)
# AI decision-making until the mech is actually close enough for it to
# matter, same "defer to later" idea as the user's own framing of this.
# Also directly addresses the observed "cluster of enemies arriving at once
# causes a frame-time spike" pattern: a slower, staggered approach means
# far mechs cross into full-AI range spread out over time instead of all at
# once - "mosey, because we don't want them cramming in."
const MOSEY_SPEED_MULT = 0.45 # unhurried amble, not a beeline sprint
const MOSEY_UPDATE_INTERVAL = 0.5 # how often the heading itself is recomputed
var _mosey_timer: float = 0.0
var _mosey_wander_offset: float = 0.0
var _mosey_velocity: Vector2 = Vector2.ZERO

func _mosey_toward_target(delta: float):
	if not target:
		# Same auto-acquire _execute_ai_tactics does - a mech that hasn't
		# been given a target yet (or lost it) must still be able to find
		# the player on its own rather than sitting frozen at the LOD
		# boundary forever.
		target = _get_player_ref()
	if not target or not is_instance_valid(target):
		velocity = Vector2.ZERO
		return
	if _ai_state_label:
		_ai_state_label.text = "MOSEY"
		_ai_state_label.modulate = Color(0.6, 0.7, 0.5)

	_mosey_timer -= delta
	if _mosey_timer <= 0.0:
		_mosey_timer = MOSEY_UPDATE_INTERVAL
		var dir: Vector2
		if not is_amphibious:
			var map = _get_map_ref()
			if map and map.has_method("get_flow_direction"):
				dir = map.get_flow_direction(global_position, target.global_position)
			else:
				dir = global_position.direction_to(target.global_position)
		else:
			dir = global_position.direction_to(target.global_position)
		_mosey_velocity = dir.rotated(_mosey_wander_offset) * current_move_speed * speed_modifier * MOSEY_SPEED_MULT

	velocity = _mosey_velocity

# Melee/mass physics pillar: automatic contact damage on a fast enough
# collision with an opposing mech - no dedicated input, matches the user's
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

# Reactive Plating's per-attacker cooldown (see has_reactive_plating's field
# comment) - mirrors _ram_cooldowns' own decrement loop above, just for a
# different system. Always ticks regardless of whether THIS mech is
# currently ramming/being rammed, same as ram cooldowns do.
func _process_reactive_plating_cooldowns(delta: float):
	if _reactive_plating_cooldowns.is_empty():
		return
	for id in _reactive_plating_cooldowns.keys():
		_reactive_plating_cooldowns[id] -= delta
		if _reactive_plating_cooldowns[id] <= 0.0:
			_reactive_plating_cooldowns.erase(id)

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
# Ground effects from the biome underfoot (see TerrainEffects); refreshed with the water state each tick.
var terrain_speed_mult: float = 1.0
var terrain_traction: float = 1.0
var _slide_velocity: Vector2 = Vector2.ZERO

# AI branches set velocity outright; scale it by the ground and, on ice, let the old heading bleed off.
func _apply_terrain_to_ai_velocity(delta: float) -> void:
	if terrain_speed_mult != 1.0:
		velocity *= terrain_speed_mult
	if terrain_traction < 1.0:
		velocity = TerrainEffects.slide(_slide_velocity, velocity, terrain_traction, delta)
	_slide_velocity = velocity

# Diagnostic A/B toggle (DebugRoom --micro, MechWaterCacheParityCheck): true = recompute every tick.
static var diag_no_water_cache: bool = false
var _wcache_cx: int = -1000000
var _wcache_cy: int = -1000000
var _wcache_ver: int = -1

func _refresh_water_state():
	var is_over_water = false
	var map = _get_map_ref()
	if map and "terrain" in map:
		var ts: float = map.tile_size
		var cx := int(floor(global_position.x / ts))
		var cy := int(floor(global_position.y / ts))
		# Same tile as last tick on the same terrain: _in_water / terrain_speed_mult / terrain_traction are
		# already current, so skip the lookups (a mech changes tile every ~10-20 ticks). The player and
		# FightShovel (corn trampling runs every tick) keep the full path.
		if not diag_no_water_cache and not is_player and cx == _wcache_cx and cy == _wcache_cy \
				and map.terrain_version == _wcache_ver:
			return
		var grid_pos = Vector2i(cx, cy)
		if grid_pos.x >= 0 and grid_pos.x < map.width and grid_pos.y >= 0 and grid_pos.y < map.height:
			var biome_here: int = map.terrain[grid_pos.y][grid_pos.x]
			is_over_water = biome_here == map.BiomeType.WATER
			if _has_jumpjets() or is_amphibious:
				terrain_speed_mult = 1.0
				terrain_traction = 1.0
			else:
				terrain_speed_mult = TerrainEffects.speed(biome_here)
				terrain_traction = TerrainEffects.traction(biome_here)
		# FightShovel corn trampling (Utility-SOC: "corn-fields that leave
		# trails when walked through") - same per-mech-per-tick terrain
		# lookup this function already does, one dictionary check further.
		# No-ops instantly on any map without corn (see MapGenerator.
		# trample_corn's own guard).
		var is_corn_map: bool = map.map_type == "FightShovel"
		if is_corn_map and map.has_method("trample_corn"):
			map.trample_corn(grid_pos)
		if not is_player and not is_corn_map:
			_wcache_cx = cx
			_wcache_cy = cy
			_wcache_ver = map.terrain_version
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
	if not diag_no_water_cache and not map.any_water():
		return vel # no water tile anywhere on this map: nothing to avoid
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

	# GPU migration (AAA Polish Roadmap Priority 1) - see DestructibleObstacle.gd's
	# identical conversion for why. p_r below duplicate()s p_l including this
	# process_material - sharing one material between both feet is fine (and
	# is the point): they're meant to look identical, just offset.
	var p_l = GPUParticles2D.new()
	p_l.local_coords = false
	p_l.lifetime = 0.5
	p_l.explosiveness = 0.0
	p_l.amount = 10
	var p_mat = ParticleProcessMaterial.new()
	p_mat.spread = 180.0
	p_mat.initial_velocity_min = 10.0
	p_mat.initial_velocity_max = 30.0
	p_mat.scale_min = 4.0
	p_mat.scale_max = 8.0
	p_l.process_material = p_mat
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
		# color lives on the GPU process_material, not the node itself - see
		# _ensure_jumpjet_trail()'s GPU migration comment.
		if p.process_material and p.process_material.color != new_color:
			p.process_material.color = new_color
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

func _get_rarity_charge_multiplier(tile) -> float:
	if not "rarity" in tile:
		return 1.0
	match tile.rarity:
		1: return 1.25 # UNCOMMON
		2: return 1.5  # RARE
		3: return 2.0  # LEGENDARY
		4: return 2.5  # MYTHIC
	return 1.0

# True when a listed weapon can no longer fire: its mount was knocked out or
# destroyed, or its whole limb broke. Checked at fire time so the effect is
# immediate, not delayed until the grid is next recalculated.
func _weapon_offline(data) -> bool:
	var mount = data.mount
	if mount.is_disabled or mount.power_lost:
		return true
	var slot = data.get("slot_type", HexTile.BodySlot.NONE)
	return components.has(slot) and components[slot].is_broken

# Diagnostic A/B toggle (DebugRoom --micro, MechChargeTickParityCheck): true = the original loop without the
# full-charge early-out below.
static var diag_slow_charges: bool = false

# True while every weapon is a full, non-bank, online-or-full mount and there are no lances: the whole tick is then a
# no-op, so it is skipped until something changes a charge (_shoot_impl consuming one, the grid being rebuilt, spawn
# priming). Writers of current_charge: this function, _shoot_impl (resets this), spawn priming (resets this).
var _charges_idle: bool = false

func _tick_weapon_charges(delta: float):
	if _charges_idle and not diag_slow_charges:
		return
	var _any_active := false
	for data in precalculated_weapons:
		var mount = data.mount
		var required = data.packet.charge_required
		# Early-out: a normal (non-bank) weapon that is already fully charged has nothing to accumulate and, since
		# the offline check below only ever causes a `continue`, skipping it first is behaviour-identical. At wave
		# 34 every enemy carries ~7 weapons, mostly full, and the offline check + rarity lookup cost ~4 us each.
		if not diag_slow_charges and mount.current_charge >= required and data.get("bank_mode", "") != "bank":
			continue
		_any_active = true # charging, bank, or offline (may come back online): keep ticking
		if _weapon_offline(data):
			continue
		var r_mult = _get_rarity_charge_multiplier(mount)
		if data.get("bank_mode", "") == "bank":
			if is_boss:
				mount.bank_current_charge = min(required, mount.bank_current_charge + delta * (required / BOSS_BANK_RECHARGE_TIME))
			elif mount.bank_current_charge < required:
				mount.bank_current_charge = min(required, mount.bank_current_charge + (delta * r_mult) / max(0.01, fire_rate))
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
				if is_cloaked and not shadow_stealth_fire:
					_break_cloak()
				mount._fire_combined_projectile(self, auto_packet, data.step)
				mount.bank_current_charge = 0.0
				heat = max(0.0, heat - required * banked_frac * 0.6)
		else:
			if mount.current_charge < required:
				mount.current_charge = min(required, mount.current_charge + (delta * r_mult) / max(0.01, fire_rate))

	# Lance mounts fire themselves - no mouse/key trigger, see
	# LanceMountTile.gd's own header comment.
	for lance in lance_mounts:
		_any_active = true
		if lance.is_disabled or lance.power_lost:
			continue
		var r_mult = _get_rarity_charge_multiplier(lance)
		if lance.cooldown_timer > 0.0:
			lance.cooldown_timer -= delta * r_mult
		elif lance.ready_to_fire:
			lance.fire(self)
	_charges_idle = not _any_active and not is_boss

# Thin timing wrapper (see the perf-instrumentation block above
# _physics_process) - renamed the real body to _shoot_impl rather than
# threading Time.get_ticks_usec() around every early-return inside it, so
# every caller (AI tactics, PlayerController, drones, and the weapon-bank
# auto-release in _tick_weapon_charges) gets counted uniformly from one spot.
func _shoot(target_pos: Vector2, is_outward: bool, fire_left_arm: bool = true, delta: float = 0.0):
	var _t_shoot = Time.get_ticks_usec()
	_perf_diag_shoot_call_count += 1
	var _fired = _shoot_impl(target_pos, is_outward, fire_left_arm, delta)
	var _elapsed = Time.get_ticks_usec() - _t_shoot
	_perf_shoot_usec += _elapsed
	if _fired:
		_perf_shoot_fired_usec += _elapsed
	else:
		_perf_shoot_checked_only_usec += _elapsed

# --- Rust packet-tax batching: tried, measured, reverted (2026-08-03) ---
# rust_ext/src/packet_tax.rs + Mech._batch_scale_packets_fallback (the
# GDScript reference the parity check still validates it against) implement
# a batched tax/jamming/ambush scale - correct (PacketTaxParityCheck.gd
# passes, including the no-input-mutation contract), but a properly
# warmup-controlled, order-alternated same-process A/B
# (ProjectileConstructCostDiagnostic.gd) measured it as ~16% SLOWER than
# plain GDScript at this call site's real batch size (1-2 armed mounts per
# _shoot_impl() call) - FFI/array-marshalling overhead exceeds the saved
# arithmetic below that scale. Not wired in. Left in the tree (Rust module +
# parity check) since the function itself would very plausibly pay off if a
# future redesign batches across ALL mechs' fire requests once per frame
# (mirroring ProjectileManager/ProjectileBroadphase's proven pattern)
# instead of once per mech - see Status.md's Phase 4 section.

func _shoot_impl(target_pos: Vector2, is_outward: bool, fire_left_arm: bool = true, delta: float = 0.0):
	last_aim_position = target_pos
	is_firing_outward = is_outward

	if is_grid_dirty:
		_recalculate_grid()

	var was_cloaked = is_cloaked
	var fired_a_shot = false

	for data in precalculated_weapons:
		if _weapon_offline(data):
			continue
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
		_charges_idle = false
		# Thermal venting: firing sheds heat proportional to the volley
		heat = max(0.0, heat - required_charge * 0.6)
		fired_a_shot = true
		_perf_diag_shots_fired_count += 1

	if fired_a_shot and was_cloaked and not shadow_stealth_fire:
		_break_cloak()

	return fired_a_shot

static func _batch_scale_packets_fallback(requests: Array) -> Array:
	return MechGridSim._batch_scale_packets_fallback(requests)

# --- Lightweight heat, v1 (FEATURE_ROADMAP.md group 5, locked spec) --------
# No live packet simulation: heat is ONE scalar per mech, derived from the
# static grid sim. Everything is proportional to totals (the user's ruling):
#   - generation rate ~ sum of charge_required across armed weapons
#   - venting ~ the volley just released
#   - volatility severity ~ current heat
# ICE-dominant circuits actively cool (can fully solve heat); LIGHTNING-
# heavy circuits arc into adjacent tiles when hot; hitting the cap knocks
# out an Accumulator via the existing disable/reboot machinery.
const HEAT_CAPACITY = 100.0
# the user: thermal system fully commented out below (_update_heat,
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

## _recalculate_grid() (Mech.gd tech-debt pass): this was one 394-line
## function - by far the largest in the file, and central enough (public
## entry point called from equip/unequip, GarageSimulationRunner,
## GarageTestRange, and many debug checks) that moving it to a composed
## RefCounted helper the way CloakSystem/JammerModuleSystem/HealBeaconSystem
## were would just relocate ~25 fields' worth of cross-subsystem coupling to
## a different file without reducing it, at real risk to the single most
## safety-critical function in the game. This is a pure extract-method
## refactor instead - same class, zero field-access changes, phases split
## into named private helpers below with NO behavior change. Diff this
## against git history if you ever need to confirm nothing moved wrong.
static var _perf_recalc_usec: int = 0
static var _perf_recalc_calls: int = 0
static var _perf_phase_usec: Array = [0, 0, 0, 0, 0]
static var _perf_sim_rust_calls: int = 0
static var _perf_sim_gd_calls: int = 0

# The player's build identity: the element that dominates their armed weapons. MechRenderer tints the hero
# crest, chest vents and visor with it (RAW / no weapons = the default gold and cyan), so a glance at the
# mech says what it is built around. Re-renders only when the dominant element actually changes.
var identity_synergy: int = -1

func compute_identity_synergy() -> int:
	var totals: Dictionary = {}
	for data in precalculated_weapons:
		var pkt = data.get("packet")
		if pkt == null:
			continue
		for k in pkt.synergies:
			if int(k) == EnergyPacket.SynergyType.RAW:
				continue
			totals[k] = totals.get(k, 0.0) + float(pkt.synergies[k])
	var best = -1
	var best_v = 0.0
	for k in totals:
		if totals[k] > best_v:
			best_v = totals[k]
			best = int(k)
	return best

func _update_identity_synergy() -> void:
	var now = compute_identity_synergy()
	if now != identity_synergy:
		identity_synergy = now
		call_deferred("refresh_visuals")

func _recalculate_grid():
	return _get_MechGridSim()._recalculate_grid()

func _recalculate_grid_for_stock(stock: StockBuild):
	return _get_MechLoadoutBuilder()._recalculate_grid_for_stock(stock)

# Snapshots every tile's just-simulated pending_packets (the routing
# result _collect_weapon_mounts_and_tile_capabilities is about to consume
# and clear) onto the StockBuild, keyed by slot+grid_position so a later
# replay can restore them onto the freshly-placed tiles at the same
# positions without re-running the simulation. Packets are copy()'d going
# in (and again going out, in _restore_stock_simulation_cache) so the
# cached entries are never aliased with any live packet a caller might
# mutate.
func _capture_stock_simulation_cache(stock: StockBuild):
	for slot in components:
		var comp = components[slot]
		for tile in comp.hex_grid.get_all_tiles():
			if "pending_packets" in tile and tile.pending_packets.size() > 0 and tile.grid_position:
				var key = str(slot) + ":" + str(tile.grid_position.q) + "," + str(tile.grid_position.r)
				var cached_entries = []
				for entry in tile.pending_packets:
					cached_entries.append({"packet": entry.packet.copy(), "step": entry.step})
				stock._simulation_cache[key] = cached_entries

func _restore_stock_simulation_cache(stock: StockBuild):
	for slot in components:
		var comp = components[slot]
		for tile in comp.hex_grid.get_all_tiles():
			if not ("pending_packets" in tile) or not tile.grid_position:
				continue
			var key = str(slot) + ":" + str(tile.grid_position.q) + "," + str(tile.grid_position.r)
			if stock._simulation_cache.has(key):
				for entry in stock._simulation_cache[key]:
					tile.pending_packets.append({"packet": entry.packet.copy(), "step": entry.step})

func _replay_stock_tiles(stock: StockBuild):
	return _get_MechLoadoutBuilder()._replay_stock_tiles(stock)

static func prewarm_stock_build(stock: StockBuild) -> void:
	MechLoadoutBuilder.prewarm_stock_build(stock)

static func presolve_stock_build(evo, template_name: String, role: String, rarity: int, slot: int, profile) -> void:
	MechLoadoutBuilder.presolve_stock_build(evo, template_name, role, rarity, slot, profile)

static func generate_deviation_candidate(evo, template_name: String, role: String, rarity: int, slot: int, profile) -> StockBuild:
	return MechLoadoutBuilder.generate_deviation_candidate(evo, template_name, role, rarity, slot, profile)

func _reset_grid_state():
	return _get_MechGridSim()._reset_grid_state()

func _compute_mass_and_stat_modifiers():
	return _get_MechGridSim()._compute_mass_and_stat_modifiers()

func _simulate_energy_flow(torso):
	return _get_MechGridSim()._simulate_energy_flow(torso)

# Single pass over every equipped tile: builds precalculated_weapons (with
# the accumulator normal/bank split-fire model) AND detects every
# per-tile capability (Lance Mount, speed/magnetic bonuses, loot rarity
# filter, Magnet repel mode, Jumpjet blink mode, Actuator school, Shield/
# Cloak/Jammer/Heal Beacon capacity) in the same loop they were always
# scanned together in - kept as ONE pass (not split further) so nothing
# about iteration order can change.
# Rapid-fire energy cost (per the user: "the shots spraying so fast
# everywhere is cool... it should cost more than it currently does" -
# specifically as an energy-economy cost, reusing the EXISTING charge_
# required/fire_rate infrastructure rather than a new heat/stamina
# resource). Applied ONLY to normal (mouse/AI) fire, not Accumulator bank
# shots - bank shots are ALREADY the deliberate "wait longer, hit much
# harder" playstyle and don't need more pressure. This uses the discrete
# normal-vs-bank distinction the code already has, rather than inferring
# "weak" from a packet's raw magnitude - magnitude legitimately ranges from
# ~100 (early game) to 150,000+ (endgame Mythic loops - see EnergyPacket.
# NORMAL_MAGNITUDE_CAP), so a magnitude-threshold curve would need real
# playtesting data to calibrate safely; a flat, clearly-tunable multiplier
# on the specific playstyle in question is the safer first pass.
const RAPID_FIRE_CHARGE_MULT = 1.4

func _collect_weapon_mounts_and_tile_capabilities():
	return _get_MechGridSim()._collect_weapon_mounts_and_tile_capabilities()

func _finalize_grid_state():
	return _get_MechGridSim()._finalize_grid_state()

func _sync_contiguous_accumulator_shortcuts(grid: HexGridComponent):
	return _get_MechGridSim()._sync_contiguous_accumulator_shortcuts(grid)

var _spawn_primed: bool = false

static func _get_adjacent_accumulator_bonus(grid: HexGridComponent, coord: HexCoord) -> Dictionary:
	return MechGridSim._get_adjacent_accumulator_bonus(grid, coord)

static func _get_adjacent_reverse_accumulator_discount(grid: HexGridComponent, coord: HexCoord) -> float:
	return MechGridSim._get_adjacent_reverse_accumulator_discount(grid, coord)

static func _get_adjacent_accumulator_capacity_tier(grid: HexGridComponent, coord: HexCoord) -> int:
	return MechGridSim._get_adjacent_accumulator_capacity_tier(grid, coord)

static func _get_adjacent_chopper_split_factor(grid: HexGridComponent, coord: HexCoord) -> int:
	return MechGridSim._get_adjacent_chopper_split_factor(grid, coord)

func _collect_transfers(comp) -> Dictionary:
	return _get_MechGridSim()._collect_transfers(comp)

func _route_to_peripheral(pkts: Array, comp):
	return _get_MechGridSim()._route_to_peripheral(pkts, comp)

const RustGridSimBridge = preload("res://scripts/core/RustGridSim.gd")

func _simulate_grid(grid: HexGridComponent, starting_packets: Array, force_gdscript: bool = false):
	return _get_MechGridSim()._simulate_grid(grid, starting_packets, force_gdscript)

# --- Player Sight/Detection (non-boss only) --------------------------------
# Previously every enemy just always knew exactly where the player was and
# beelined toward them forever, regardless of range or obstacles - per
# the user: "enemies off screen don't seem to see/acknowledge me... their
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
# Raised from 1000 - per the user: "the npc's should be given longer
# visual range/better sensors." Paired with SensorTile's own sight_bonus
# stat bump (see SensorTile.gd) for enemies actually carrying that tile.
const SIGHT_RANGE = 1400.0
const SIGHT_CHECK_HZ = 3.0
# Per the user: lost (or never-had) sight should trigger an ONGOING search,
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
# enemy units" per the user - wider patrol/search footprint plus modestly
# better eyesight, matching a recon archetype.
const SCOUT_SIGHT_MULT = 1.25
const SCOUT_SEARCH_MULT = 3.0

# --- Expanding Square Search (the user: "us coast guard search pattern...
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

# Wild bots had no despawn path at all outside campaign mode's periodic
# map rotation (Main._rotate_campaign_map, gated to current_game_mode ==
# "campaign") - the same gating bug LootPickup had. A bot whose role never
# happens to be needed by the next several squad templates the director
# rolls (_assemble_squad only recruits a wild bot if the selected template
# actually calls for its exact combat_role) sat in the tree forever: full
# renderer + physics body + particles, ticking every frame, indefinitely.
# Confirmed as a real secondary contributor to a wave-50 playtest's
# disproportionate draws/objects/verts (see LootPickup.gd's own fix for the
# primary one, same root cause).
const WILD_DESPAWN_TIME = 60.0
var _wild_timer: float = 0.0

# Active reinforcement (2026-08-05, user-designed): a wild bot no longer
# just waits to be picked up by the next brand-new squad ASSEMBLY that
# happens to want its exact role (SquadDirector._assemble_squad's
# role-matched wild_bots recruitment, still there as the spawn-time path) -
# every REASSIGN_CHECK_INTERVAL seconds it actively asks the director for
# the nearest squad already on the field with an opening, "whatever role it
# is." Throttled, not per-frame - this is a small active_squads scan on the
# director side, same category of cost the EntityCache-throttling pattern
# elsewhere in this file exists to avoid paying every tick.
const REASSIGN_CHECK_INTERVAL = 1.0
var _reassign_check_timer: float = 0.0

func _get_squad_director_ref():
	var main = get_tree().current_scene
	if main and "world" in main and main.world and main.world.has_node("SquadDirector"):
		return main.world.get_node("SquadDirector")
	return null

# Returns true while flee/wild owns this mech's movement (caller returns).
func _update_flee_state(delta: float) -> bool:
	if _has_gone_wild:
		# Wild loiter: out of the fight, licking wounds while actively
		# looking for a squad to rejoin (see try_reassign_wild_bot above),
		# or WILD_DESPAWN_TIME runs out with nothing found and it retreats
		# for good.
		velocity = Vector2.ZERO
		if hp < max_hp * WILD_REGEN_CAP_FRACTION:
			hp = min(max_hp * WILD_REGEN_CAP_FRACTION, hp + max_hp * WILD_REGEN_PER_SEC_FRACTION * delta)
		_wild_timer += delta
		_reassign_check_timer -= delta
		if _reassign_check_timer <= 0.0:
			_reassign_check_timer = REASSIGN_CHECK_INTERVAL
			var director = _get_squad_director_ref()
			if director and director.has_method("try_reassign_wild_bot") and director.try_reassign_wild_bot(self):
				return true # Squad.add_member already called rejoin_from_wild()
		if _wild_timer >= WILD_DESPAWN_TIME:
			# NOT despawned_wild.emit() (that signal existed briefly, removed
			# 2026-08-05) - _finish_flee() below already hands this mech's
			# wave slot back to Main.active_enemies the MOMENT it goes wild
			# (disconnects died->_on_enemy_died and manually fires it once,
			# "a survivor hiding at the map edge must never stall the
			# wave-clear"). A second decrement here for the SAME mech's later
			# timeout double-counted it, wedging active_enemies negative -
			# harder to detect than the original leak this was meant to fix,
			# since it reproduces on a fresh session too (any wave long
			# enough for a fled bot to hit WILD_DESPAWN_TIME mid-fight, e.g.
			# a boss wave) rather than needing many waves of accumulated
			# drift first. Confirmed via user report: still stuck even after
			# a full relaunch, on a boss wave (every 5th).
			queue_free() # tree_exiting -> SquadDirector._on_wild_bot_died erases it from wild_bots
			return true
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
	# Grunt AI use of Smoke Grenade: "pop smoke and run" - no-ops silently if
	# not equipped or on cooldown, same as the player's own held-Ctrl trigger.
	try_drop_smoke_grenade()
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
	_wild_timer = 0.0
	_reassign_check_timer = 0.0
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
	_wild_timer = 0.0
	_reassign_check_timer = 0.0

static var _perf_flee_check_usec: int = 0
static var _perf_execute_search_usec: int = 0

const TACTIC_ARRIVE_RADIUS = 70.0

# Squad plans lead the player's motion (skill scales with director pressure);
# without a squad/tactics it aims at the raw position as before.
func _ai_aim_point(target_pos: Vector2, _dist: float) -> Vector2:
	if squad and is_instance_valid(squad) and squad.get("tactics"):
		return squad.tactics.lead_point(global_position, target_pos, _ai_shot_speed())
	return target_pos

# Mean projectile speed of this mech's weapons, mirroring Projectile.gd's
# speed stat (500 base, +1200*pierce, -250*poison, -200*ice, Mythic beam x2.5).
# Cached; _reset_grid_state() invalidates it.
func _ai_shot_speed() -> float:
	if _ai_shot_speed_cache > 0.0:
		return _ai_shot_speed_cache
	var total = 0.0
	var n = 0
	for data in precalculated_weapons:
		var ratios = EnergyPacket.compute_ratios(data.packet.synergies)
		var sp = 500.0 + 1200.0 * float(ratios.get(EnergyPacket.SynergyType.PIERCE, 0.0)) - 250.0 * float(ratios.get(EnergyPacket.SynergyType.POISON, 0.0)) - 200.0 * float(ratios.get(EnergyPacket.SynergyType.ICE, 0.0))
		var tile = data.mount
		if tile and "mythic_pattern" in tile and tile.rarity == HexTile.Rarity.MYTHIC and int(tile.get("mythic_pattern")) == 3:
			sp *= 2.5
		total += max(sp, 50.0)
		n += 1
	_ai_shot_speed_cache = total / n if n > 0 else 500.0
	return _ai_shot_speed_cache

# Mean Explosion share of this mech's shots (decides whether it can crack hard cover; see CoverSense.can_damage).
func ai_explosion_share() -> float:
	if _ai_explosion_cache >= 0.0:
		return _ai_explosion_cache
	var total = 0.0
	var n = 0
	for data in precalculated_weapons:
		var ratios = EnergyPacket.compute_ratios(data.packet.synergies)
		total += float(ratios.get(EnergyPacket.SynergyType.EXPLOSION, 0.0))
		n += 1
	_ai_explosion_cache = total / n if n > 0 else 0.0
	return _ai_explosion_cache

func _execute_ai_tactics(delta):
	# Flee/wild states override everything below for regular wave enemies -
	# checked BEFORE target re-acquisition, or a wild bot would immediately
	# re-target the player it just escaped from.
	var _t_flee = Time.get_ticks_usec()
	var _fleeing = not is_boss and not is_player and _update_flee_state(delta)
	_perf_flee_check_usec += Time.get_ticks_usec() - _t_flee
	if _fleeing:
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
		# above _execute_search) and always fall straight through. Phase 2 of
		# the AI-tactics Rust-cutover plan (see
		# C:\Users\Utility\.claude\plans\effervescent-drifting-kazoo.md) moved
		# the actual sight-check GATE (range + line-of-sight) out of this
		# per-mech call into SightAndSearchBatcher.gd, which refreshes
		# has_sight_of_player/last_known_player_pos for every eligible enemy
		# on one shared cadence instead of each mech polling its own
		# independently-staggered SIGHT_CHECK_HZ timer - this just reads the
		# result. _update_player_sight() itself still exists unchanged
		# (JammerWiringCheck.gd calls it directly to force past the
		# throttle for its own test), it's just no longer called from here.
		var in_cover := false
		if not is_boss:
			if cover_brain == null:
				cover_brain = CoverBrain.new(self)
			cover_brain.update(delta, _get_map_ref())
			in_cover = cover_brain.active()
		if not is_boss:
			if in_cover and _ai_state_label:
				_ai_state_label.text = cover_brain.label()
				_ai_state_label.modulate = Color(0.9, 0.8, 0.3)
			elif _ai_state_label:
				_ai_state_label.text = ("CHASE" if tactic_label == "" else tactic_label) if has_sight_of_player else "SEARCH"
				_ai_state_label.modulate = (Color(0.3, 1.0, 0.3) if tactic_label == "" else Color(0.3, 0.9, 1.0)) if has_sight_of_player else Color(1.0, 0.6, 0.2)
			if not has_sight_of_player and not in_cover:
				if not sight_and_search:
					sight_and_search = SightAndSearch.new(self)
				# Phase 2 continuation instrumentation (see
				# C:\Users\Utility\.claude\plans\effervescent-drifting-kazoo.md) -
				# unlike the sight-check gate (which eliminated a real
				# per-mech physics-server round-trip), most of
				# _execute_search's state machine is already cheap unthrottled
				# GDScript arithmetic with no FFI cost to save - measuring
				# first before assuming a Rust port pays off, same "gate on
				# the real number" discipline Phase 0 used for Phase 3.
				var _t_search = Time.get_ticks_usec()
				sight_and_search._execute_search(delta)
				_perf_execute_search_usec += Time.get_ticks_usec() - _t_search
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
			var _t_flow = Time.get_ticks_usec()
			var map = _get_map_ref()
			if map and map.has_method("get_flow_direction"):
				path_dir = map.get_flow_direction(global_position, target.global_position)
			_perf_flow_field_usec += Time.get_ticks_usec() - _t_flow

		var tactic_moving = false
		if in_cover:
			# Cover owns movement: straight to the hide/peek point (CoverBrain only plans cover it can walk to directly).
			tactic_moving = true
			velocity = cover_brain.desired_velocity(current_move_speed * speed_modifier)
		elif not is_boss and tactic_goal_active:
			var to_goal = tactic_goal - global_position
			if to_goal.length() > TACTIC_ARRIVE_RADIUS:
				tactic_moving = true
				var steer = to_goal.normalized() if tactic_path_clear else path_dir
				velocity = steer * current_move_speed * speed_modifier
			elif tactic_hold:
				tactic_moving = true
				velocity = Vector2.ZERO

		if tactic_moving:
			pass # squad tactic is steering this member
		elif dist > engagement_distance:
			# Approach full speed
			velocity = path_dir * current_move_speed * speed_modifier
		else:
			# Reached engagement distance, strafe/orbit at half speed
			var tangent = Vector2(-dir.y, dir.x) * rotational_direction
			# Raycast to prevent strafing into walls
			var _t_orbit = Time.get_ticks_usec()
			if SimPhysics.segment_blocked(self, global_position, global_position + tangent * 50.0, SimPhysics.LAYER_ENV):
				rotational_direction *= -1 # Reverse orbit
				tangent = Vector2(-dir.y, dir.x) * rotational_direction
			_perf_orbit_raycast_usec += Time.get_ticks_usec() - _t_orbit

			velocity = tangent * current_move_speed * (speed_modifier * 0.5)

		# Hazard sense (see HazardSense): wary bots leave or avoid a vent about to erupt / a burning slick.
		if not is_boss and not is_amphibious and _hazard_wary():
			var haz_push = HazardSense.push(global_position, velocity, EntityCache.get_group("lava_vent"), EntityCache.get_group("oil_slick"))
			if haz_push != Vector2.ZERO:
				velocity = haz_push * maxf(velocity.length(), current_move_speed * speed_modifier)

		# Separation nudge - see the field comment above for why this exists.
		# _cached_separation is now written by SeparationBatcher.gd, which
		# computes it for every eligible enemy mech in ONE batched call per
		# cadence instead of each mech running its own individually-timed
		# PhysicsShapeQueryParameters2D query (see that autoload + rust_ext/
		# src/separation.rs for the full rationale) - this just reads
		# whatever the batcher last wrote, blended into velocity every frame
		# so it stays smooth rather than snapping.
		if not is_boss and not _diag_skip_separation:
			if _cached_separation != Vector2.ZERO:
				velocity += _cached_separation * current_move_speed * SEPARATION_WEIGHT

		# AI combat shooting (out of range = hold charge, same as the player)
		if dist < engagement_distance + 150.0 and not _diag_skip_shoot and not (in_cover and cover_brain.hiding()):
			var _t_shoot_diag = Time.get_ticks_usec()
			if is_boss:
				_shoot(target.global_position, true, true, delta)
			else:
				# See _ai_shoot_timer's own comment above.
				_ai_shoot_timer -= delta
				if _ai_shoot_timer <= 0.0:
					_ai_shoot_timer = 1.0 / AI_SHOOT_CHECK_HZ
					_shoot(suppress_pos if suppress_pos != Vector2.ZERO else _ai_aim_point(target.global_position, dist), true, true, delta)
			_perf_diag_shoot_usec += Time.get_ticks_usec() - _t_shoot_diag


var elemental_resistances: Dictionary = {}
# Stun/Shock/Freeze Guard tiles (see StatusResistTile.gd): status name -> fraction of an incoming status duration that
# still gets through (1.0 = unprotected). Rebuilt on every grid recalculation; read by apply_status().
var status_duration_mult: Dictionary = {}
var _status_resist_sum: Dictionary = {} # scratch for the recalculation: status -> summed Guard resistance

# Reactive Plating (design request: "reactive armor options which melee
# mechs will abuse"). Passive/unconditional from mere presence, same as
# AnchorTile - no energy routing required. Wearer counter-hits whatever
# damaged them, but ONLY if the attacker is close enough that "explosive
# plating" makes physical sense (see REACTIVE_PLATING_TRIGGER_RADIUS in
# apply_damage) - a ranged mech plinking from across the map is too far
# away to ever eat the counter-blast, but anything that rammed in (or is
# just standing point-blank) is. That's the deliberate "melee abuses this"
# lever: a mech that's already committed to close-range brawling takes
# more hits at exactly the range this triggers, AND punishes whatever it's
# trading blows with.
var has_reactive_plating: bool = false
# Ice embrittlement (IceEffects): share of actuator flow blocked while the timer runs, and the ice energy that froze us
# (drives shatter violence). pending_shatter is set by a big kinetic hit and resolved after damage lands.
var embrittle_timer: float = 0.0
var embrittle_block: float = 0.0
var frozen_ice_energy: float = 0.0
var pending_shatter: Dictionary = {}
# Share of the incoming hit that is Kinetic (0..1), set by the shot just before it calls apply_damage and cleared right after;
# -1 = unknown (derive from the element name). Lets a mixed Ice+Kinetic shot shatter a frozen target (IceEffects.try_shatter).
var hit_kinetic_ratio: float = -1.0
# Damage per second of the current burn; set from the igniting shot's size (StatusEffectRunner.apply_burn), reset when it ends.
var burn_dps: float = 5.0
# Enemy shield doctrine (SquadDirector): the element this bot's shield is tuned against, and how much of its shield energy
# is retinted to it (MechGridSim._finalize_grid_state). -1 = none. Works wherever the shield sits in the grid.
var shield_counter_element: int = -1
var shield_counter_strength: float = 1.0
var poison_dps: float = 4.0 # same idea for poison / bleeding (StatusEffectRunner.apply_poison / apply_bleed)
var bleed_dps: float = 6.0
# The mech whose shot is hitting this one, set/cleared alongside hit_kinetic_ratio. Part damage reaches global HP with no
# source, so this is how a shatter knows who fired it (and spares them). Never read outside that call.
var hit_source: Node = null
var reactive_plating_reflect_pct: float = 0.0 # % of incoming (post-mitigation) damage reflected back to the attacker
# Per-attacker cooldown (mirrors _ram_cooldowns' shape) - without this, a
# sustained beam/DoT source standing close would eat a reactive counter-hit
# EVERY tick, not just once per "hit".
var _reactive_plating_cooldowns: Dictionary = {}

func _apply_shield_mitigation(amount: float, element: String) -> float:
	return _get_MechDamage()._apply_shield_mitigation(amount, element)

const AEGIS_HIT_CAP_RATIO = 0.15 # Aegis: no single hit can exceed 15% of max shield HP
const DEFLECTOR_BURST_RADIUS = 220.0
# Corporate Sponsorships: Aegis Dynamics' elemental Aegis - "elemental" means
# every SynergyType except RAW/KINETIC/PIERCE/EXPLOSION (the locked design's
# own phrasing), matching EnergyPacket.SynergyType's real enum order
# (RAW, FIRE, ICE, LIGHTNING, VORTEX, POISON, EXPLOSION, KINETIC, PIERCE, VAMPIRIC).
const ELEMENTAL_SYNERGY_NAMES = ["FIRE", "ICE", "LIGHTNING", "VORTEX", "POISON", "VAMPIRIC"]

func _deflect_overflow(amount: float):
	return _get_MechDamage()._deflect_overflow(amount)

# Flat per-hit chance, same for everyone - deliberately simple/predictable
# rather than scaling with PIERCE stacking, per the user's call. Easy for a
# player to learn ("pierce hits sometimes just end the fight") and easy for
# the existing AI counter-pressure (SquadDirector.player_kill_methods /
# _apply_kill_method_counter_pressure) to detect and counter if the player
# leans on it too hard.
const PIERCE_EXECUTION_CHANCE = 0.04

func _is_pierce_execution_exempt() -> bool:
	return _get_MechDamage()._is_pierce_execution_exempt()

# Smoke Grenade damage mitigation: PIERCE and EXPLOSION are exempt (per
# design - a smoke cloud stops line-of-sight-style weapons, not shrapnel or
# armor-piercing rounds), everything else takes SMOKE_DAMAGE_MULT. Shared
# by apply_damage/apply_part_damage below - part-hit damage does NOT route
# through apply_damage's full pipeline (see apply_part_damage's own header),
# so this needs its own call site there too, same as _apply_shield_mitigation.
const SMOKE_DAMAGE_MULT = 0.5

func is_in_smoke() -> bool:
	for cloud in EntityCache.get_group("smoke_cloud"):
		if is_instance_valid(cloud) and cloud.is_point_inside(global_position):
			return true
	return false

func _apply_smoke_mitigation(amount: float, element: String) -> float:
	return _get_MechDamage()._apply_smoke_mitigation(amount, element)

# Perf plan (wave-138 playtest overlay: this function was invisible to
# FpsCounter's breakdown, same blind spot as ProjectileBroadphase) - thin
# timing wrapper, same rename-body pattern as Mech._shoot/_shoot_impl.
# FpsCounter reads-AND-RESETS _perf_apply_damage_usec once/sec.
static var _perf_apply_damage_usec: int = 0

func apply_damage(amount: float, element: String = "RAW", source: Node = null, was_reflected: bool = false, source_label_override: String = ""):
	var _t_dmg = Time.get_ticks_usec()
	_apply_damage_body(amount, element, source, was_reflected, source_label_override)
	_perf_apply_damage_usec += Time.get_ticks_usec() - _t_dmg

func _apply_damage_body(amount: float, element: String = "RAW", source: Node = null, was_reflected: bool = false, source_label_override: String = ""):
	return _get_MechDamage()._apply_damage_body(amount, element, source, was_reflected, source_label_override)

static func resolve_attacker_label(source: Node) -> String:
	return MechDamage.resolve_attacker_label(source)

func _log_incoming_damage(amount: float, element: String, source: Node, label_override: String = ""):
	return _get_MechDamage()._log_incoming_damage(amount, element, source, label_override)

func _show_floating_text(text: String, color: Color):
	return _get_MechDamage()._show_floating_text(text, color)

func apply_part_damage(slot: int, amount: float, element: String = "RAW"):
	return _get_MechDamage().apply_part_damage(slot, amount, element)

# Per-the user's design: a hit that gets past shields (or punches through as
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
	return _get_MechDamage()._roll_component_disable(comp, amount, element)

# --- Limb breakage + offline-tile bookkeeping ---------------------------------
# Share of the mech's max_hp a limb can soak before it breaks. Torso never breaks
# (that is what global HP is for). Limbs stay broken for the rest of the fight;
# only a Garage repair restores them.
const LIMB_INTEGRITY_SHARE = {
	HexTile.BodySlot.ARM_L: 0.30, HexTile.BodySlot.ARM_R: 0.30,
	HexTile.BodySlot.LEG_L: 0.35, HexTile.BodySlot.LEG_R: 0.35,
	HexTile.BodySlot.HEAD: 0.22, HexTile.BodySlot.BACKPACK: 0.28,
}
const LEG_BROKEN_SPEED_MULT = 0.6 # per broken leg (two broken legs = a crawl)
const SLOT_LABELS = {
	HexTile.BodySlot.ARM_L: "LEFT ARM", HexTile.BodySlot.ARM_R: "RIGHT ARM",
	HexTile.BodySlot.LEG_L: "LEFT LEG", HexTile.BodySlot.LEG_R: "RIGHT LEG",
	HexTile.BodySlot.HEAD: "HEAD", HexTile.BodySlot.BACKPACK: "BACKPACK",
}

var _offline_watch: Array = [] # tiles knocked offline, polled so a reboot re-enables their function
var _offline_poll_t: float = 0.0

func _on_tile_went_offline(tile) -> void:
	is_grid_dirty = true # re-route energy and rebuild weapon/capability lists without it
	if not _offline_watch.has(tile):
		_offline_watch.append(tile)

# Cheap: only walks tiles that are actually offline, 4x per second.
func _poll_offline_tiles(delta: float) -> void:
	if _offline_watch.is_empty():
		return
	_offline_poll_t += delta
	if _offline_poll_t < 0.25:
		return
	_offline_poll_t = 0.0
	var still: Array = []
	for t in _offline_watch:
		if is_instance_valid(t) and t.is_disabled and not t.power_lost:
			still.append(t)
		elif is_instance_valid(t) and not t.is_disabled:
			is_grid_dirty = true # rebooted: bring its function back
	_offline_watch = still

func _break_component(comp) -> void:
	if comp.is_broken:
		return
	comp.is_broken = true
	comp.integrity = 0.0
	is_grid_dirty = true
	_show_floating_text(SLOT_LABELS.get(comp.slot_type, "PART") + " DESTROYED", Color(1.0, 0.2, 0.2))
	if _renderer and _renderer.has_method("apply_broken_parts"):
		_renderer.apply_broken_parts()
	_recalculate_grid() # pay the cost now so weapons/abilities drop immediately

func broken_leg_count() -> int:
	var n := 0
	for slot in [HexTile.BodySlot.LEG_L, HexTile.BodySlot.LEG_R]:
		if components.has(slot) and components[slot].is_broken:
			n += 1
	return n

# Restores every broken limb (Garage repair / new life).
func repair_broken_parts() -> void:
	for comp in components.values():
		if comp.is_broken:
			comp.is_broken = false
			comp.integrity = -1.0
	_offline_watch.clear()
	is_grid_dirty = true
	if _renderer and _renderer.has_method("apply_broken_parts"):
		_renderer.apply_broken_parts()

func _find_disable_priority_tile(comp):
	return _get_MechDamage()._find_disable_priority_tile(comp)

func apply_status(effect_name: String, duration: float):
	return _get_MechDamage().apply_status(effect_name, duration)

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
# Overclocking (prestige system) grants permanent per-component mass
# reduction (ComponentEquipment.mass_reduction) - floor so a heavily
# Overclocked loadout can never push total_mass to zero/negative and
# distort _get_mass_speed_mult()'s division.
const MIN_TOTAL_MASS = 10.0

func _get_mass_speed_mult() -> float:
	return clamp(1.0 - (total_mass - MASS_BASELINE) * MASS_SPEED_COEFF, MASS_SPEED_MIN_MULT, MASS_SPEED_MAX_MULT)

func update_status_effects(delta: float):
	return _get_MechDamage().update_status_effects(delta)

func _break_cloak():
	if not cloak_system:
		cloak_system = CloakSystem.new(self)
	cloak_system.break_cloak()

func _get_ambush_multiplier() -> float:
	if not cloak_system:
		cloak_system = CloakSystem.new(self)
	return cloak_system.get_ambush_multiplier()

# --- Smoke Grenade (equippable ability) -----------------------------------
# Single-charge consumable, unlike Cloak's continuous drain - see
# SmokeGrenadeTile.gd's header. Called from this Mech's own _physics_process
# on Ctrl held (see the "Smoke Grenade charge regen" block above - each call
# just no-ops until smoke_charge refills, so holding naturally rate-limits
# to one drop per recharge cycle) and from _begin_flee() for AI Grunts that
# happen to have one equipped ("pop smoke and run").
func try_drop_smoke_grenade() -> bool:
	if not has_smoke_grenade or max_smoke_charge <= 0.0 or smoke_charge < max_smoke_charge:
		return false
	smoke_charge = 0.0
	var cloud = load("res://scripts/visuals/SmokeCloud.gd").new()
	cloud.radius = smoke_radius
	cloud.lifetime = smoke_duration
	cloud.global_position = global_position
	if get_parent():
		get_parent().add_child(cloud)
	return true

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
	# Corporate Sponsorships: Keeneye Sensing's Counter-Jammer tile - see
	# SensorTile.gd's header.
	if has_jammer_immunity:
		return
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

# --- Heal Beacon (Support ability) ----------------------------------------
# Thin wrapper only - see HealBeaconSystem.gd for the actual pulse-timer
# tick and heal emission. Stays a real Mech method (not e.g.
# mech.heal_beacon_system.tick()) since _physics_process calls it directly
# by this name - lazily constructing here matches the same pattern
# CloakSystem/JammerModuleSystem already use.
func _update_healer(delta: float):
	if not heal_beacon_system:
		heal_beacon_system = HealBeaconSystem.new(self)
	heal_beacon_system.tick(delta)

func _update_shield_pulse(delta: float):
	if not shield_pulse_system:
		shield_pulse_system = AegisShieldPulseSystem.new(self)
	shield_pulse_system.tick(delta)

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
	Sfx.death(is_boss, global_position)

	# AAA roadmap Hitstop: a boss going down deserves more weight than a
	# regular kill - slightly longer freeze than the Pierce-execution one
	# (see HitstopManager.trigger()'s defaults), same self-restoring guard.
	if is_boss:
		HitstopManager.trigger(0.06)

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

	# Extra lives (Main._on_player_died, see SaveManager.DIFFICULTY_LIVES):
	# that handler revives in place by resetting is_dead back to false
	# DURING this exact signal, synchronously, before died.emit() above
	# returns. Without this check, die() ran to completion regardless and
	# queue_free()'d the mech a few lines below no matter what the signal
	# handler just did - the revival reset HP/is_dead correctly, and then
	# the node got destroyed anyway a moment later ("dead dead" with lives
	# still remaining, per the playtest report). If a life was actually
	# consumed, this mech survives and none of the destruction below
	# should run at all.
	if not is_dead:
		return

	# The player node is owned by Main (game over hides it, then the garage
	# restores it) - freeing it here left Main holding a dead reference and
	# aborted _open_garage() on a real game over.
	if is_player:
		return

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
	return _get_MechLoadoutBuilder().build_loadout_for_role(role_name)

# Same "reach the SquadDirector from a Mech" pattern already used elsewhere
# (e.g. MissileRackTile._fire_combined_projectile's SquadDirector.
# log_mortar_shot() lookup) - null for the player and anything spawned
# outside a live SquadDirector's world (Test Range, debug spawns).
func _get_stock_build_evolution():
	if _stock_evo_override != null:
		return _stock_evo_override
	var main = get_tree().current_scene if is_inside_tree() else null
	if main and "world" in main and main.world and main.world.has_node("SquadDirector"):
		var director = main.world.get_node("SquadDirector")
		if "stock_build_evolution" in director:
			return director.stock_build_evolution
	return null



var _MechLoadoutBuilder = null
func _get_MechLoadoutBuilder():
	if _MechLoadoutBuilder == null:
		_MechLoadoutBuilder = MechLoadoutBuilder.new(self)
	return _MechLoadoutBuilder

var _MechDamage = null
func _get_MechDamage():
	if _MechDamage == null:
		_MechDamage = MechDamage.new(self)
	return _MechDamage

var _MechGridSim = null
func _get_MechGridSim():
	if _MechGridSim == null:
		_MechGridSim = MechGridSim.new(self)
	return _MechGridSim