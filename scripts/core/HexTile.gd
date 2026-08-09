class_name HexTile
extends Resource

enum TileCategory {
	CONDUIT, PROCESSOR, STORAGE, ROUTER, CONVERTER, OUTPUT, SPECIAL
}

enum Rarity {
	COMMON, UNCOMMON, RARE, LEGENDARY, MYTHIC
}

enum BodySlot {
	NONE, TORSO, ARM_L, ARM_R, LEG_L, LEG_R, HEAD, BACKPACK, DRONE
}
# DRONE is deliberately NOT a slot that ever appears in a Mech's own
# `components` dict - it's the slot_type of the small standalone
# ComponentEquipment owned by a DroneBayTile (see DroneBayTile.gd), which
# gets equipped onto the Drone's OWN separate Mech-like node (Drone.gd) when
# it's spawned into the world. Keeping it out of the main mech's
# `components`/_recalculate_grid() loop is what lets the drone's weapon fire
# from the drone's own flying position instead of the main mech's.

@export var tile_type: String = "Base"
@export var category: TileCategory = TileCategory.CONDUIT
@export var rarity: Rarity = Rarity.COMMON:
	set(val):
		rarity = val
		_roll_sync_adjustment()
		
@export var body_slot: BodySlot = BodySlot.NONE
@export var level: int = 1
@export var is_blocked: bool = false

# Corporate Sponsorships (task #17): "" means an ordinary tile. A brand tile
# is otherwise a plain Mythic-rarity tile - no separate rarity tier - just
# rendered BrandRegistry.BRAND_COLOR (dark blue) with the brand's logo mark
# instead of the normal Mythic tint (see MechRenderer/GarageGridRenderer's
# tile-color lookups). See BrandRegistry.gd's header for the full design.
@export var brand_id: String = ""

var grid_position: HexCoord = null
var base_color: Color = Color.GRAY
var sync_adjustment: int = 0

# Multi-cell footprint (relative to grid_position, the tile's "anchor")
# - empty for every tile except LanceMountTile, the first (and so far only)
# tile to ever span more than one hex. See HexGridComponent.add_tile/
# remove_tile/get_all_tiles for how this gets stored/deduped. Only ever
# populated AT PLACEMENT time (see GarageInventoryPanel._drop_footprint_tile)
# - a tile sitting in inventory always has this empty, which is why "is this
# a multi-cell tile TYPE" checks must use get_footprint_size() below, never
# this array's current size.
var footprint_offsets: Array = []

# How many hexes this tile's class occupies once placed. 1 for every normal
# tile; overridden by LanceMountTile to 3. Checked BEFORE placement (e.g. to
# decide drag/drop behavior for a tile still sitting in inventory), when
# footprint_offsets above is always still empty.
func get_footprint_size() -> int:
	return 1

# Geometry of a multi-cell footprint, checked at PLACEMENT time alongside
# get_footprint_size(): "line" = anchor + 2 more cells straight along the
# chosen direction (Lance Mount), "triangle" = anchor + its neighbors in the
# chosen direction and the next one clockwise, 3 mutually-adjacent hexes
# (Orbiting Array). Meaningless when get_footprint_size() == 1.
func get_footprint_shape() -> String:
	return "line"

func _roll_sync_adjustment():
	sync_adjustment = 0
	if rarity == Rarity.RARE:
		if randf() < 0.4:
			sync_adjustment = 1 if randf() < 0.5 else -1
	elif rarity == Rarity.LEGENDARY:
		if randf() < 0.8:
			var rolls = [1, -1, 2, -2]
			sync_adjustment = rolls[randi() % rolls.size()]

var max_hp: float = 30.0
var hp: float = 30.0
var is_disabled: bool = false
var disable_timer: float = 0.0
var times_disabled: int = 0
var time_since_last_hit: float = 0.0

# Set by Mech._roll_component_disable() for a catastrophic ("grave enough")
# hit instead of the normal timed disable/reboot cycle below - the tile stays
# fully offline with no self-recovery until a Garage repair clears it
# (see GarageMenu._on_repair_all). Distinct from the ordinary is_disabled
# timer so a routine knockout doesn't accidentally become permanent.
var power_lost: bool = false

func take_damage(amount: float):
	hp -= amount
	time_since_last_hit = 0.0
	if hp <= 0 and not is_disabled:
		is_disabled = true
		var base_cooldown = 3.0
		disable_timer = base_cooldown + (times_disabled * 2.0)
		times_disabled += 1
		hp = 0

# Relative disable-roll risk by component type - see Mech._roll_component_disable
# for how this is used. Splitters are the juiciest target (routing hub, losing
# one collapses a lot of downstream packet flow), Reflector/Resonator/Amplifier
# are valuable-but-secondary, everything else is comparatively low priority.
func get_disable_risk() -> float:
	match tile_type:
		"Splitter":
			return 1.0
		"Reflector", "Resonator", "Amplifier", "Heal Beacon":
			return 0.55
		_:
			return 0.2

# Mass contribution for the melee/ramming physics pillar (see Mech._recalculate_grid
# for where these get summed into total_mass, and update_status_effects for the
# resulting movement-speed penalty/bonus). Base default covers any tile type
# that doesn't override this below; subclasses override with a value that's
# rationally in line with what the part actually is - power sources and
# propulsion/actuator hardware are heavy, routing/link tiles are nearly weightless.
func get_weight() -> float:
	return 3.0

func process_durability(delta: float):
	time_since_last_hit += delta
	if time_since_last_hit >= 5.0 and times_disabled > 0 and not is_disabled:
		times_disabled = 0

	if power_lost:
		return # Only a Garage repair brings this back - see take_damage/power_lost above

	if is_disabled:
		disable_timer -= delta
		if disable_timer <= 0:
			is_disabled = false
			hp = max_hp # Fully restored on reboot

func _init(_type: String = "Base", _category: TileCategory = TileCategory.CONDUIT):
	tile_type = _type
	category = _category

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	if is_disabled:
		# Degraded capacity: acts as a straight pass-through, ignoring the tile's special logic
		return [packet]
	# Base implementation just passes it through
	return [packet]

func get_exit_direction(entry_direction: int) -> int:
	return (entry_direction + 3) % 6

func can_enter_from(direction: int) -> bool:
	return not is_blocked

# --- Garage simulation timeline support (Timeline Scrubber + Packet
# Inspector, Status.md queue) -----------------------------------------------
# The scrubber replays the simulation from a cached step-0 packet snapshot
# up to whatever step the player drags to, RATHER than buffering every
# intermediate frame - the sim is fully deterministic (no RNG anywhere in
# process_energy), so re-running it is free and exact. That only works if
# every tile's own mutable state (a Resonator's path residue, a Catalyst's
# gate counter, ...) gets wiped back to baseline before each replay -
# reset_simulation_state() is the one place that happens. Stateful tile
# subclasses (ResonatorTile, SplitterTile, CatalystTile, ...) override this
# and call super() first, so a future stateful tile just needs to do the
# same to stay scrubber-safe.
const PACKET_HISTORY_CAP = 5
# entry_direction (int 0-5) -> Array of snapshot Dictionaries, oldest
# first, capped at PACKET_HISTORY_CAP - what the Packet Inspector reads.
var packet_history: Dictionary = {}

func record_packet_history(entry_direction: int, packet: EnergyPacket) -> void:
	var snap = {
		"magnitude": packet.magnitude,
		"synergies": packet.synergies.duplicate(),
		"dominant": packet.get_dominant_synergy(),
		# Whether this packet is ALREADY carrying a picked-up status-effect
		# proc (see EnergyPacket.proc_synergies / ResonatorTile._process_sync)
		# as it enters this tile - the Packet Inspector's "what it picked up"
		# visualization. Read at record time, upstream of this tile's own
		# processing, so it reflects residue picked up anywhere earlier on
		# the packet's path, not just at this exact tile.
		"picked_up": not packet.proc_synergies.is_empty(),
	}
	if not packet_history.has(entry_direction):
		packet_history[entry_direction] = []
	var hist: Array = packet_history[entry_direction]
	hist.append(snap)
	if hist.size() > PACKET_HISTORY_CAP:
		hist.pop_front()

func reset_simulation_state() -> void:
	packet_history.clear()
	# pending_packets isn't declared on the base HexTile class (only on
	# WeaponMountTile/Link tiles/DroneBayTile), so a bare identifier
	# reference here fails to compile even behind the "in self" guard -
	# get() is the dynamic, always-legal way to reach a property that only
	# SOME subclasses declare. Godot Arrays share their backing storage, so
	# clear() on the fetched reference mutates the real property in place.
	if "pending_packets" in self:
		var pp = get("pending_packets")
		if pp is Array:
			pp.clear()

# --- Fill-paint template stamping (playtest: "if I hover over a splitter,
# before I hover a blank space then fill, it will match the first
# splitter") -----------------------------------------------------------
# Virtual, no-op by default. Overridden by tile types with meaningful
# player-configured state (SplitterTile's active_faces/output_ratios, ...)
# so that dragging a paint-fill line starting from an EXISTING placed tile
# of the same type stamps its configuration onto every newly placed copy,
# instead of each one keeping whatever config it happened to roll as loot.
# See GarageInventoryPanel.handle_process/_drop_fill_line.
func copy_config_from(_other: HexTile) -> void:
	pass

# --- Shared "acts as a weapon mount" behavior -----------------------------
# Both WeaponMountTile and ComponentLinkTile (when it's wired as an
# Accessory/Torso Return "vent" with nowhere else to route energy) can end
# up firing projectiles - this used to be copy-pasted near-verbatim in both
# files (plus a third, fully orphaned copy in the now-deleted
# ComponentLinkTile_methods.gd). Living here once means a fix like the
# muzzle-position recalculation below applies to every tile type that fires,
# not just whichever copy happened to get updated.
const _ProjectileClass = preload("res://scripts/entities/Projectile.gd")
# Explicit preload rather than the bare global class name (same fresh-
# checkout/fresh-class-cache workaround already established elsewhere in
# this codebase - see MapGenerator.gd's DestructibleObstacleScript and
# LootManager.gd's own header comment): a brand-new class_name script isn't
# in a headless run's global class cache until the editor has rescanned the
# project, so a bare `ProjectilePool.acquire()` reference can fail to
# resolve on a fresh run.
const _ProjectilePoolScript = preload("res://scripts/core/ProjectilePool.gd")

func _get_power_multiplier() -> float:
	var mult = 1.0
	if rarity == Rarity.UNCOMMON: mult = 1.2
	elif rarity == Rarity.RARE: mult = 1.5
	elif rarity == Rarity.LEGENDARY: mult = 3.0
	elif rarity == Rarity.MYTHIC: mult = 5.0
	return mult * (1.0 + (level - 1) * 0.1)

# Weapon Mount Capacity (the user: "especially at higher rarities would have
# more capacity before firing, so instead of getting 100 projectiles in a
# split second from a heavily fuelled shotgun, it could just have 10% as
# many projectiles, but much bigger"). Shotgun/Radial Burst used to always
# fire a fixed pellet count (5 / 8) no matter how invested the mount was -
# a dense capacitor-bank grid with many such mounts firing at once really
# could produce ~100 total projectiles in one volley. A mount's power
# multiplier (rarity AND level - patterns only unlock at Mythic today, so
# level is the practical lever within that) now scales its pellet count
# DOWN as it grows, with each remaining pellet's payload scaled UP by the
# same factor - total output per volley is unchanged, just redistributed
# across fewer, proportionally bigger shots. This is also a direct answer
# to "too many projectiles tanks performance": the mounts most likely to
# spam a screen full of pellets (heavily leveled Mythic ones) are exactly
# the ones this eases off the hardest.
const SHOTGUN_MAX_PELLETS = 5
const SHOTGUN_MIN_PELLETS = 2
const RADIAL_MAX_PELLETS = 8
const RADIAL_MIN_PELLETS = 4

func _pattern_pellet_count(max_pellets: int, min_pellets: int) -> int:
	# _get_power_multiplier() is 5.0 at a fresh Mythic level-1 mount (the
	# baseline every pattern already assumes) and grows further with level
	# upgrades - capacity_factor stays 1.0 (full pellet count) at that
	# baseline, then eases the count down as the mount gets more invested.
	var capacity_factor = _get_power_multiplier() / 5.0
	return clamp(int(round(max_pellets / capacity_factor)), min_pellets, max_pellets)

func get_muzzle_position(mech) -> Vector2:
	# Perf fix (live playtest: "shoot_fired" the dominant remaining cost
	# after the pattern-fanout/AI-throttle fixes - the user's own
	# suggestion: "more precalculating and caching rather than on the fly
	# calculation"). Mech.gd ALREADY caches its own MechRenderer child in
	# _renderer, set once in _ready() - this was doing its own fresh
	# string-keyed get_node_or_null("MechRenderer") tree lookup on every
	# single shot instead of just reading that existing cache. Guarded
	# duck-typed check (not a direct mech._renderer access) because this
	# also runs against ComponentDiagramView's PreviewMechContext preview
	# stub, a bare Node2D with no _renderer field at all (see
	# _attach_part_hitbox's matching comment on that same stub) - falls
	# back to the original lookup for that one non-Mech caller.
	var renderer = mech._renderer if ("_renderer" in mech and mech._renderer) else mech.get_node_or_null("MechRenderer")
	if not renderer:
		return mech.global_position

	var is_left = (body_slot == BodySlot.ARM_L)
	var is_right = (body_slot == BodySlot.ARM_R)

	if is_left and renderer.drawn_parts.has("Arm_true"):
		var arm = renderer.drawn_parts["Arm_true"]
		var h = 28.0 * (1.0 + rarity * 0.15)
		return arm.global_position + Vector2(0, h).rotated(arm.global_rotation)
	elif is_right and renderer.drawn_parts.has("Arm_false"):
		var arm = renderer.drawn_parts["Arm_false"]
		var h = 28.0 * (1.0 + rarity * 0.15)
		return arm.global_position + Vector2(0, h).rotated(arm.global_rotation)

	return mech.global_position

# Saturation consolidation state (see ProjectileManager.consolidation_factor):
# while the screen is past its live-projectile budget, this mount banks every
# volley's packet here and only actually fires every K-th call, with the
# banked packets merged in - same total energy delivered downrange, a
# fraction of the Area2D population. Per-mount state, so different mounts
# never cross-contaminate elements.
var _consolidation_buffer: EnergyPacket = null
var _consolidation_shots: int = 0

# Perf investigation (playtest video, real 34-enemy/495-live-shot stress
# scenario at 1-2fps): FpsCounter's existing "shoot" breakdown (Mech.
# _perf_shoot_usec) times the WHOLE of _shoot_impl, including every call
# into this function - but doesn't distinguish the cheap consolidation/
# pattern math above from the actual add_child(proj) call below, which is
# where Projectile._ready() (ratio/stat calc + _build_visuals()'s several
# child Polygon2D/particle/Trail2D/Timer/VisibleOnScreenNotifier2D nodes)
# runs synchronously. Static, shared across every HexTile instance/subclass
# that fires - same aggregation pattern as Mech._perf_shoot_usec - so a real
# session's numbers (not another noisy synthetic harness - see
# ProjectileBroadphaseProfileDiagnostic.gd's and MechPhysicsCostDiagnostic.
# gd's own header comments for why those proved unreliable) can show
# whether "shoot" cost at volume is dominated by this construction step or
# by something else in the merge/pattern logic above it. Reset once/sec by
# FpsCounter, same as every other _perf_*_usec counter in this codebase.
static var _perf_projectile_construct_usec: int = 0

func _fire_combined_projectile(mech, packet: EnergyPacket, step: int, _pattern_child: bool = false, _extra_angle: float = 0.0, _chopper_child: bool = false):
	if not _ProjectileClass: return

	# Whole-volley consolidation under saturation (playtest: rational
	# weaponsfire at high difficulty was hitting 1-3 fps). Applied only to
	# top-level volleys - pattern children of a volley that DOES fire still
	# split normally, skipped volleys simply skip their split too.
	# saturation_k is hoisted to function scope (GDScript block-scopes `var`
	# inside `if`) so the Shotgun/Radial pattern branches below can reuse the
	# exact same saturation reading instead of recomputing it - see their own
	# comment on why they need it too.
	var saturation_k = 1
	if not _pattern_child and not _chopper_child:
		saturation_k = ProjectileManager.consolidation_factor()
		if saturation_k > 1:
			if _consolidation_buffer == null:
				_consolidation_buffer = packet.copy()
			else:
				_consolidation_buffer.add_synergies_batch(packet.synergies)
			_consolidation_shots += 1
			if _consolidation_shots < saturation_k:
				return
			packet = _consolidation_buffer
			_consolidation_buffer = null
			_consolidation_shots = 0
		elif _consolidation_buffer != null:
			# Saturation just ended: fold the leftover bank into this shot so
			# banked energy is never silently dropped.
			_consolidation_buffer.add_synergies_batch(packet.synergies)
			packet = _consolidation_buffer
			_consolidation_buffer = null
			_consolidation_shots = 0

	# Chopper split (ReverseAccumulatorTile.gd, renamed-in-place - see that
	# file's header): "takes what would fire as ONE combined shot and fires
	# it as N smaller shots instead," same total magnitude redistributed
	# evenly via EnergyPacket.split()'s existing "peel one even share at a
	# time" idiom (already used by SplitterTile/ComponentLinkTile - no new
	# math). Deliberately mutually exclusive with the mythic_pattern branch
	# below (a Chopper-split mount's pattern setting is skipped for that
	# release) - this bounds worst-case fanout to chopper_split alone
	# instead of chopper_split * pattern_pellets, the same class of
	# uncapped-fanout problem the saturation cap above exists to prevent.
	if not _pattern_child and not _chopper_child and packet.chopper_split > 1:
		var n = packet.chopper_split
		if saturation_k > 1:
			n = max(1, ceili(float(n) / saturation_k))
		if n > 1:
			for i in range(n - 1):
				var piece = packet.split(1.0 / float(n) / (1.0 - (1.0 / float(n)) * i))
				_fire_combined_projectile(mech, piece, step, false, 0.0, true)
			_fire_combined_projectile(mech, packet, step, false, 0.0, true)
			return

	# MYTHIC Weapon Mount firing patterns: split the volley into a shotgun
	# spread or a 360-degree radial burst by recursively firing scaled-down
	# child packets. _pattern_child guards recursion (children are marked
	# true and skip this whole check, so no fractal explosion risk).
	# Previously also required step == 0 ("this packet took zero hex-hops
	# from the Core"), which on any grid where the mount isn't the Core's
	# immediate neighbor - i.e. almost every non-trivial build, and
	# essentially every dense Mythic-tier one - meant the pattern silently
	# never fired at all, degrading to a single normal shot regardless of
	# the mode selected. Beam (pattern 3, below) never had this restriction,
	# confirming it was an oversight specific to Shotgun/Radial rather than
	# an intentional "patterns only apply to instant volleys" design call.
	if not _pattern_child and not _chopper_child and "mythic_pattern" in self and rarity == Rarity.MYTHIC:
		var pattern = int(get("mythic_pattern"))
		if pattern == 4: # Mortar: remote payload at the aim point (see MortarShell.gd)
			_fire_mortar(mech, packet)
			return
		if pattern == 1: # Shotgun: up to 5 pellets, +/-24 deg spread
			var pellet_count = _pattern_pellet_count(SHOTGUN_MAX_PELLETS, SHOTGUN_MIN_PELLETS)
			# Perf plan (wave-138 playtest: pattern fanout was the dominant
			# "shoot" cost, uncapped by the saturation system that already
			# throttles every OTHER mount) - each pellet independently pays
			# the full per-shot construction cost via its own recursive
			# _fire_combined_projectile call, so an 8-shard Radial burst was
			# ~8x a normal mount's cost with zero saturation relief. Applied
			# AFTER _pattern_pellet_count's own capacity_factor clamp
			# (compose, don't override), same divide-by-k-with-a-floor shape
			# as whole-volley consolidation above. At saturation_k == 1
			# (the vast majority of real play) this is an exact no-op.
			# per_pellet_amplify is derived from the FINAL pellet_count
			# below, so total volley damage is unchanged either way - fewer,
			# proportionally bigger pellets, same total energy delivered.
			if saturation_k > 1:
				pellet_count = max(SHOTGUN_MIN_PELLETS, ceili(float(pellet_count) / saturation_k))
			var per_pellet_amplify = (SHOTGUN_MAX_PELLETS * 0.4) / float(pellet_count)
			var angle_step = 48.0 / max(1, pellet_count - 1)
			for i in range(pellet_count):
				var pellet = packet.copy()
				pellet.amplify(per_pellet_amplify)
				var angle_deg = -24.0 + angle_step * i if pellet_count > 1 else 0.0
				_fire_combined_projectile(mech, pellet, 0, true, deg_to_rad(angle_deg))
			return
		elif pattern == 2: # Radial burst: up to 8 shots, full circle
			var shard_count = _pattern_pellet_count(RADIAL_MAX_PELLETS, RADIAL_MIN_PELLETS)
			# See the Shotgun branch's own comment just above - same
			# saturation-aware fanout cap, same damage-neutral mechanism.
			if saturation_k > 1:
				shard_count = max(RADIAL_MIN_PELLETS, ceili(float(shard_count) / saturation_k))
			var per_shard_amplify = (RADIAL_MAX_PELLETS * 0.5) / float(shard_count)
			for i in range(shard_count):
				var shard = packet.copy()
				shard.amplify(per_shard_amplify)
				_fire_combined_projectile(mech, shard, 0, true, TAU * float(i) / shard_count)
			return
		# pattern 3 (Beam) falls through - single projectile, tuned below.

	# Task #35: Projectile pooling was built and measured (ProjectilePool.gd,
	# same-process interleaved A/B, 5 measured rounds each) - pool
	# acquire()+release() came out a clean, consistent 12% SLOWER than plain
	# new()+queue_free(), even in the benchmark's best-case 100%-reuse
	# scenario. _build_visuals()'s per-shot node construction dominates the
	# cost and isn't pooled (synergy-dependent, torn down/rebuilt every
	# reuse regardless - see Projectile._build_visuals()), so there was
	# never much left for pooling to save. Reverted to plain new(); left
	# ProjectilePool.gd in the tree unused, matching the packet_tax.rs/
	# BossBrain precedent from earlier this session.
	var proj = _ProjectileClass.new()
	var base_damage = packet.magnitude * _get_damage_multiplier() * _get_power_multiplier()

	# Guaranteed crit at the (former, still-normal) magnitude ceiling -
	# tied to NORMAL_MAGNITUDE_CAP rather than MAX_MAGNITUDE so existing
	# capacitor-bank builds keep the payoff they always had; an all-Mythic
	# overcharge packet clears this threshold too since it's strictly above it.
	var is_crit = (packet.magnitude >= EnergyPacket.NORMAL_MAGNITUDE_CAP) or (randf() < 0.05)
	if is_crit:
		base_damage *= 2.0

	# Perf (2026-07-27, real-session measurement via ProjectileConstructCostDiagnostic.gd:
	# this "merge/pattern math" region - not Projectile construction itself -
	# was 65.5% of total shoot cost). Every field below used to be guarded by
	# a "field in X" runtime existence check (or .get()/.set() dynamic
	# dispatch) as if proj/mech/packet might not have it - they always do:
	# proj is always _ProjectileClass.new() (a const preload of Projectile.gd,
	# never swapped), which unconditionally declares every field touched
	# here, mech always has is_player/last_aim_position/stat_modifiers
	# (Mech.gd's own field declarations, inherited by Drone), and packet
	# (EnergyPacket) always declares is_banked_shot/range_mult/aoe_bonus/
	# proc_synergies. Every one of those checks was a guaranteed-true no-op
	# paid on every single shot fired in the game - direct assignment is
	# identical behavior, just without the redundant reflection lookup.
	proj.fired_by_player = mech.is_player
	proj.source_mech = mech
	proj.source_label = Mech.resolve_attacker_label(mech)
	proj.damage = base_damage
	proj.is_crit = is_crit
	proj.synergies = packet.synergies.duplicate()
	proj.proc_synergies = packet.proc_synergies.duplicate()
	proj.stat_modifiers = mech.stat_modifiers.duplicate()
	proj.weapon_rarity = rarity
	proj.aoe_bonus = packet.aoe_bonus
	proj.is_banked_shot = packet.is_banked_shot
	proj.range_mult = packet.range_mult
	# Per-mount visual signature (Utility-SOC: "easier to tell which
	# projectile is coming from which weapon mount") - a stable hash of
	# this mount's own (body_slot, grid_position), NOT anything about the
	# packet/synergy, so the same mount always reads the same accent color
	# shot after shot regardless of what's flowing through it. grid_position
	# genuinely can be null (a tile not yet placed in a grid), so this guard
	# stays - it's the only one in this block that isn't always-true.
	if grid_position:
		var sig_hash = (int(body_slot) * 97 + grid_position.q * 31 + grid_position.r * 17)
		proj.mount_signature_hue = float(((sig_hash % 360) + 360) % 360) / 360.0
	# Beam pattern: concentrated - faster, piercing, modest damage bonus, and
	# now real extended range (previously got no range advantage at all
	# despite being the piercing sniper mode). is_beam also forces
	# angle_offset to 0 below - a Beam is supposed to ALWAYS go dead-on at
	# the mouse; it was inheriting the same entry_dir-vs-forward_dir spread
	# offset every other pattern uses (meant to simulate multi-barrel firing
	# angles), which could aim it anywhere from 15 to a full 180 degrees off
	# depending on how the mount happened to be wired into the grid - that
	# was the actual "unreliable" bug, not RNG.
	var is_beam = not _pattern_child and not _chopper_child and "mythic_pattern" in self and rarity == Rarity.MYTHIC and int(get("mythic_pattern")) == 3
	if is_beam:
		proj.damage *= 1.2
		proj.base_speed *= 2.5
		proj.pierce_count = max(proj.pierce_count, 4)
		proj.is_beam_shot = true
	# get_muzzle_position() does a get_node_or_null("MechRenderer") string
	# lookup + dictionary lookups on drawn_parts - real cost, computed once
	# and reused for both the spawn position and the direction calc below
	# (was computing the identical value twice for the same shot).
	var muzzle_pos = get_muzzle_position(mech)
	proj.global_position = muzzle_pos

	var aim_pos = mech.last_aim_position

	var base_direction = (aim_pos - muzzle_pos).normalized()
	if base_direction == Vector2.ZERO:
		base_direction = Vector2(0, -1)

	proj.target_direction = base_direction

	# Determine the "straight forward" direction based on which component we are in
	var forward_dir = 4 # Default South (Down) for Torso/Legs/Backpack
	if body_slot == BodySlot.ARM_L:
		forward_dir = 3 # West
	elif body_slot == BodySlot.ARM_R:
		forward_dir = 0 # East
	elif body_slot == BodySlot.HEAD:
		forward_dir = 1 # Northeast (Up)

	var angle_offset = 0.0

	# Mythic mounted-anywhere aim (WeaponMountTile.mythic_aim_direction):
	# a player-chosen offset from the mouse-aim direction that completely
	# REPLACES the wiring-derived offset below - the whole point being a
	# Mythic mount fires exactly where configured regardless of which hex
	# face happens to feed it, so it can be placed/rewired freely without
	# hunting for the "right" entry direction to get a desired firing angle.
	var has_mythic_aim = not is_beam and rarity == Rarity.MYTHIC and "mythic_aim_direction" in self
	if has_mythic_aim and int(get("mythic_aim_direction")) != 0:
		angle_offset = int(get("mythic_aim_direction")) * (PI / 3.0)
	elif not is_beam:
		var entry_dir = packet.direction
		var diff = (entry_dir - forward_dir + 6) % 6
		if diff == 1: angle_offset = deg_to_rad(15)
		elif diff == 5: angle_offset = deg_to_rad(-15)
		elif diff == 2: angle_offset = deg_to_rad(35)
		elif diff == 4: angle_offset = deg_to_rad(-35)
		elif diff == 3: angle_offset = deg_to_rad(180)

	proj.direction = base_direction.rotated(angle_offset + _extra_angle)

	if step > 0:
		var delay = (step * 0.05) # 50ms per step
		var timer = Timer.new()
		timer.wait_time = delay
		timer.one_shot = true
		timer.timeout.connect(func():
			if is_instance_valid(mech) and is_instance_valid(proj):
				# Recalculate muzzle position/direction right before firing so a
				# staggered multi-step shot doesn't spawn from a stale position
				# (previously only WeaponMountTile did this - Accessory/Torso
				# Return "vent" shots via ComponentLinkTile did not, which is
				# the "vomiting" bug where delayed vented shots could appear to
				# spawn in the wrong place).
				var new_muzzle_pos = get_muzzle_position(mech)
				proj.global_position = new_muzzle_pos

				var new_aim_pos = mech.last_aim_position
				var new_base_dir = (new_aim_pos - new_muzzle_pos).normalized()
				if new_base_dir == Vector2.ZERO:
					new_base_dir = Vector2(0, -1)
				proj.target_direction = new_base_dir
				proj.direction = new_base_dir.rotated(angle_offset)

				if mech.get_parent():
					var _t_construct = Time.get_ticks_usec()
					mech.get_parent().add_child(proj)
					_perf_projectile_construct_usec += Time.get_ticks_usec() - _t_construct
			elif is_instance_valid(proj):
				proj.queue_free()
			timer.queue_free()
		)
		mech.add_child(timer)
		timer.start()
	else:
		var _t_construct = Time.get_ticks_usec()
		if mech.get_parent():
			mech.get_parent().add_child(proj)
		else:
			mech.add_child(proj)
		_perf_projectile_construct_usec += Time.get_ticks_usec() - _t_construct

# Mortar pattern: the payload is delivered AT the aim position (travel
# time + ground telegraph + elemental AoE) instead of fired along a line.
# Speed constant sets how long targets get to react per unit distance.
const MORTAR_SPEED = 420.0

func _fire_mortar(mech, packet: EnergyPacket):
	var world = mech.get_parent()
	if not world:
		return
	var target_pos: Vector2 = mech.get("last_aim_position") if "last_aim_position" in mech else mech.global_position + Vector2(0, -100)
	var muzzle = get_muzzle_position(mech)
	# Pierce payoff: a full-pierce shell arrives ~3x faster than a RAW one
	# over the same distance - previously flight_time was purely a function
	# of distance, so no synergy investment had any effect on how fast a
	# mortar actually landed (elemental impact effects already fire for
	# real on landing via _detonate()'s reused Projectile._handle_hit()
	# pipeline - that part didn't need building). PIERCE, not KINETIC - it's
	# already the velocity stat everywhere else (see Projectile.gd's
	# _calculate_stats: "PIERCE is the velocity stat... KINETIC's whole
	# budget moved to range instead"), so a "zoomy mortar" is a pierce
	# build's payoff, matching that existing identity split.
	var total_mag = 0.0
	for k in packet.synergies:
		total_mag += packet.synergies[k]
	var pierce_ratio = (packet.synergies.get(EnergyPacket.SynergyType.PIERCE, 0.0) / total_mag) if total_mag > 0.0 else 0.0
	var effective_mortar_speed = MORTAR_SPEED * (1.0 + pierce_ratio * 2.0)
	var flight_time = clamp(muzzle.distance_to(target_pos) / effective_mortar_speed, 0.12, 2.2)
	var dmg = packet.magnitude * _get_damage_multiplier() * _get_power_multiplier()
	# load(path), not the bare global class name - MortarShell.acquire()
	# here triggered "Identifier 'MortarShell' not declared in the current
	# scope" at HexTile.gd's own compile time (a real circular-dependency-
	# shaped failure: HexTile is foundational enough that most of the tile
	# hierarchy - CoreTile, LootManager, DebugMenu, BrandTileFactory - failed
	# to compile right along with it, matching the "missiles work
	# intermittently, no projectile visible" playtest report exactly - a
	# live session launched before this broke kept running on its last-good
	# compiled state, but anything that forced a fresh reload hit the wall).
	# load() resolves at runtime, not parse time, so it can't hit this.
	var shell = load("res://scripts/attacks/MortarShell.gd").acquire()

	shell.setup(muzzle, target_pos, flight_time, dmg, packet.synergies.duplicate(), mech.get("is_player") == true, mech, packet.aoe_bonus)
	world.add_child(shell)

# WeaponMountTile has an explicit @export damage_multiplier; other tiles
# that fire (like ComponentLinkTile acting as a Return "vent") don't, so
# default to 1.0 rather than requiring every firing tile to declare one.
func _get_damage_multiplier() -> float:
	if "damage_multiplier" in self:
		return get("damage_multiplier")
	return 1.0

# Shared Mythic "firing quanta" dial - how many frames of energy a mount
# batches into one burst before releasing it (Auto/1 = fire whenever
# charged). Originated on MissileRackTile (its 1->2->16->64 cycle);
# WeaponMountTile now shares it too, replacing its old standalone
# mythic_firing_threshold energy-value system (design ruling: one unified
# capacity model for both weapon types instead of two incompatible ones).
# Shared here via the same "prop" in self duck-typed idiom
# _get_damage_multiplier() above already uses, rather than duplicating
# this in both tile files - see WeaponMountTile.gd/MissileRackTile.gd's
# own @export var mythic_frame_multiplier declarations.
const BASE_FRAME_MULTIPLIER_OPTIONS = [1, 2, 16, 64]

# grid/coord optional - a caller with no grid context (e.g. a debug spawn
# with no real component) just gets the base list, same convention
# get_threshold_options() (its predecessor) used.
func get_frame_multiplier_options(grid: HexGridComponent = null, coord: HexCoord = null) -> Array:
	var options = BASE_FRAME_MULTIPLIER_OPTIONS.duplicate()
	if grid == null or coord == null or not grid.has_tile(coord):
		return options
	var bonus = Mech._get_adjacent_accumulator_capacity_bonus(grid, coord)
	if bonus > 0:
		# One additional ceiling tier, not a whole new ladder - matches the
		# "each adjacent accumulator adds an additional capacity" request
		# literally (singular addition), unlike the old threshold system's
		# multi-tier ceiling extension.
		options.append(BASE_FRAME_MULTIPLIER_OPTIONS[-1] + bonus)
	return options

func cycle_mythic_frame_multiplier(grid: HexGridComponent = null, coord: HexCoord = null):
	if rarity != Rarity.MYTHIC or not ("mythic_frame_multiplier" in self):
		return
	var options = get_frame_multiplier_options(grid, coord)
	var idx = options.find(get("mythic_frame_multiplier"))
	if idx == -1: idx = 0
	set("mythic_frame_multiplier", options[(idx + 1) % options.size()])

# Specific variants can be created as subclasses extending HexTile
