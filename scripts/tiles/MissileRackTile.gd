class_name MissileRackTile
extends HexTile

# Dedicated remote-payload weapon mount (fourth-review ruling: "the full
# weapon-variety version of indirect fire will be a dedicated mount tile,
# not just the Mythic Weapon Mount's Mortar pattern"). Differences from a
# plain Weapon Mount, per that ruling:
#   - Always indirect (no direct-fire mode) - every shot is a MortarShell.gd
#     lob, same delivery WeaponMountTile's Mythic "Mortar" pattern uses.
#   - Cheaper rarity entry: the base salvo (Hunter mode, below) works at
#     every rarity, not gated behind Mythic at all.
#   - Salvo behavior: the accumulated packet is banked into several shells
#     landing in a spread around the aim point (see SHELL_COUNT_BY_RARITY)
#     instead of one single big payload.
#   - Mythic-only firing MODE choice (user-designed, added 2026-08-05): a
#     Mythic Missile Rack can be cycled between Hunter (the base salvo
#     above) and AOE (one wide, Explosion-scaled burst carrying the full
#     undivided damage budget, split equally across everything it struck) -
#     see mythic_mode/cycle_mythic_mode and _fire_aoe_burst below, same
#     generic Mythic mode-cycle convention WeaponMountTile/Jumpjet/etc. use
#     (GarageTileConfigPopup.gd).
#
# Participates in the EXACT SAME pending_packets/charge/accumulator-bank
# economy as WeaponMountTile - Mech._collect_weapon_mounts_and_tile_
# capabilities gates on tile_type == "Weapon Mount" OR "Missile Rack" (see
# that function), so this only needs to expose the same pending_packets/
# current_charge/bank_current_charge surface and let that shared pipeline
# feed it. The only thing genuinely different is HOW it fires - so instead
# of reimplementing charge/banking, this overrides HexTile._fire_combined_
# projectile() (the one method WeaponMountTile actually calls into for the
# final shot) with an always-salvo body instead of WeaponMountTile's
# single-shot/Mythic-pattern one.

func _init():
	tile_type = "Missile Rack"
	category = TileCategory.OUTPUT
	base_color = Color(0.45, 0.4, 0.28)

func get_weight() -> float:
	return TileStatsRegistry.get_stat("MissileRackTile", "weight", 7.0)

@export var damage_multiplier: float = TileStatsRegistry.get_stat("MissileRackTile", "damage_multiplier", 1.0)

var pending_packets: Array = [] # { "packet": packet, "step": step } - same shape as WeaponMountTile
var current_charge: float = 0.0
var bank_current_charge: float = 0.0

# Mythic-only firing mode (same generic mythic_mode/cycle_mythic_mode
# convention GarageTileConfigPopup.gd already uses for Jumpjet/Directional
# Conduit/Shield Generator/Actuator - non-Mythic tiles always behave as
# Hunter regardless of this value, same double-gate WeaponMountTile.
# mythic_pattern uses). User-designed pair:
#   Hunter (0, default) - today's existing salvo: several shells, all aimed
#     at the one furthest-in-range target, "throws everything at a single
#     target."
#   AOE (1) - a single big burst instead of a shell salvo: wide blast radius
#     (exponentially bigger with Explosion synergy investment - see
#     _fire_aoe_burst below), carrying the FULL undivided salvo damage
#     budget ("the totality of damage the missile would have done"), split
#     EQUALLY across every target the blast actually struck.
@export_enum("Hunter", "AOE") var mythic_mode: int = 0

func cycle_mythic_mode():
	mythic_mode = (mythic_mode + 1) % 2

# Mythic-only targeting choice (user ruling, 2026-08-11), same double-gate
# convention as mythic_mode above - non-Mythic racks always use Furthest.
#   Furthest (0, default) - the original, only-ever targeting behavior:
#     "reach out and hit something a direct-fire mount can't."
#   Most Powerful (1) - the single toughest valid target in range (highest
#     max_hp - no other explicit power/threat stat exists on Mech.gd),
#     for going straight at the biggest threat on the field regardless of
#     how far away the furthest target happens to be.
# Both modes share the same [min_range, max_range] gate - see
# _find_target_in_range's own comment.
@export_enum("Furthest", "Most Powerful") var targeting_mode: int = 0

func cycle_targeting_mode():
	targeting_mode = (targeting_mode + 1) % 2

# Cycle is inherited from HexTile.cycle_mythic_frame_multiplier() (shared
# with WeaponMountTile - see that file's field comment) - this used to be
# a hardcoded local 1->2->16->64 cycle; now Accumulator-adjacency-aware
# via HexTile.get_frame_multiplier_options() like Weapon Mount's is.
@export var mythic_frame_multiplier: int = 1

func clear_pending():
	pending_packets.clear()

# Identical capture contract to WeaponMountTile.process_energy: banks a copy
# for Mech's collection pass, neutralizes the live packet so it doesn't also
# relay onward (this is a REAL weapon, not a pass-through - unlike Sensor
# Array/Anchor/Mobility Core, it must never be picked as AutoEquipSolver
# filler; see that file's FILLER_TILE_PRIORITY comment).
func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	var step = 0
	if "traversal_steps" in packet:
		step = packet.traversal_steps

	pending_packets.append({ "packet": packet.copy(), "step": step })

	packet.is_active = false
	packet.magnitude = 0.0
	return [packet]

func _get_damage_multiplier() -> float:
	return damage_multiplier

# How many shells one bank of energy splits into, by rarity - "cheaper
# rarity entry" means even a Common rack still gets a real (if modest)
# salvo, unlike the Mythic-only Mortar pattern it's meant to obsolete.
const SHELL_COUNT_BY_RARITY = [2, 3, 3, 4, 5]
# Each shell keeps this fraction of an equivalent single-shot's damage -
# below 1/N so a full-accuracy salvo doesn't simply out-damage a direct
# Weapon Mount hit for free, but each shell still splashes independently
# (see MortarShell._detonate's splash ring), so multiple shells landing
# near clustered targets can still out-value a single hit.
const PER_SHELL_DAMAGE_FRACTION = 0.65
# Shells land in a ring around the aim point rather than stacked on it -
# "a spread around the aim point" per the design ruling above.
const SPREAD_RADIUS = 55.0
# Mirrors HexTile._fire_mortar's MORTAR_SPEED constant - kept as its own
# name (not a reference to that private constant) since MissileRackTile
# doesn't extend WeaponMountTile and has no access to it.
const SHELL_SPEED_BASE = 420.0

# --- Targeting (design ruling: "ultra long range ground to ground") -------
# Unlike every other weapon, a Missile Rack doesn't fire at the mech's
# current aim point at all - it's an autonomous indirect-fire piece that
# picks its OWN target within [min_range, max_range] - see targeting_mode
# for the Furthest/Most Powerful choice. max_range reuses Projectile.gd's
# exact kinetic-scales-range formula (BASE_RANGE + KINETIC_RANGE_BONUS *
# kinetic_ratio - see that file's field comment for "kinetic should be
# able to make range MUCH longer") so a Missile Rack's own Kinetic
# investment pays off exactly like it does for every other weapon, just
# with a higher base via RANGE_MULT on top - same "final multiplier over
# the whole computed range" slot Projectile.gd already has for range_mult/
# beam shots, not a parallel range system.
const ProjectileScript = preload("res://scripts/entities/Projectile.gd")
const RANGE_MULT = 2.5 # "ultra long range" - well past a direct-fire mount's reach
# min_range used to be a flat 350.0 guess ("can't hit anything closer than
# this - not a point-defense gun"). User ruling, 2026-08-11: the real
# constraint is THIS shot's own blast radius - firing at something closer
# than 2x that would put the shooter's own position inside its blast. Now
# computed per-shot in _estimate_effective_radius() below instead of a
# flat constant.
const MIN_RANGE_RADIUS_MULT = 2.0

# "Nuke tier" (user ruling, 2026-08-11): a charge of more than 32 frames
# at 600000+ energy PER FRAME reads as genuinely different from a normal
# missile - terrain-wiping, not just a bigger explosion (see MortarShell.
# nuke_scale/_wipe_terrain, ElementalPuddle's "bombed out" fade). 0.0
# below the threshold (normal missile, no change to anything); ramps 0->1
# from NUKE_MIN_FRAME_MULTIPLIER up to the frame-multiplier ladder's own
# ceiling (256 - HexTile.ACCUMULATOR_CAPACITY_TIERS[MYTHIC][0]) so 256
# frames is the single most dramatic "feels like a nuke" case, not a hard
# on/off cutoff right at the threshold.
const NUKE_MIN_FRAME_MULTIPLIER = 32
const NUKE_MIN_ENERGY_PER_FRAME = 600000.0
const NUKE_MAX_FRAME_MULTIPLIER = 256

func _nuke_scale(total_mag: float) -> float:
	if mythic_frame_multiplier <= NUKE_MIN_FRAME_MULTIPLIER:
		return 0.0
	var per_frame_energy = total_mag / float(mythic_frame_multiplier)
	if per_frame_energy < NUKE_MIN_ENERGY_PER_FRAME:
		return 0.0
	return clamp(float(mythic_frame_multiplier - NUKE_MIN_FRAME_MULTIPLIER) / float(NUKE_MAX_FRAME_MULTIPLIER - NUKE_MIN_FRAME_MULTIPLIER), 0.0, 1.0)

# Effective blast radius THIS shot will detonate with, computed the exact
# same way MortarShell.setup() computes its own effective_radius (kept in
# sync manually - see that function's own comment). Needed HERE, before
# any shell exists, so the min-range gate (2x this radius) can use the
# real per-shot value instead of a flat guess - targeting has to happen
# before a shell is spawned, but the radius only depends on the packet/
# frame_multiplier/firing mode, all already known at that point.
func _estimate_effective_radius(packet: EnergyPacket, total_mag: float) -> float:
	var ratios = {}
	if total_mag > 0.0:
		for k in packet.synergies:
			ratios[k] = packet.synergies[k] / total_mag
	var fm_scale = sqrt(max(1.0, float(mythic_frame_multiplier)))
	var radius_mult = 1.0
	if rarity == HexTile.Rarity.MYTHIC and mythic_mode == 1:
		var r_explosion = ratios.get(EnergyPacket.SynergyType.EXPLOSION, 0.0)
		radius_mult = AOE_BASE_RADIUS_MULT * exp(AOE_EXPLOSION_EXP_K * r_explosion)
	return max(40.0, ProjectileScript.explosion_radius_for(ratios, packet.aoe_bonus) * radius_mult) * fm_scale

func _fire_combined_projectile(mech, packet: EnergyPacket, step: int, _pattern_child: bool = false, _extra_angle: float = 0.0, _chopper_child: bool = false):
	# Whole-volley consolidation under saturation - identical gate to
	# HexTile._fire_combined_projectile's own (see that file's field comment
	# on _consolidation_buffer/_consolidation_shots, inherited here since
	# this fully overrides the base method rather than calling super() and
	# would otherwise never engage ProjectileManager.consolidation_factor()
	# at all). Same total energy delivered downrange (still as a full
	# salvo), a fraction of the Area2D population under heavy fire.
	if not _pattern_child and not _chopper_child:
		var k = ProjectileManager.consolidation_factor()
		if k > 1:
			if _consolidation_buffer == null:
				_consolidation_buffer = packet.copy()
			else:
				for s in packet.synergies:
					_consolidation_buffer.add_synergy(s, packet.synergies[s])
			_consolidation_shots += 1
			if _consolidation_shots < k:
				return
			packet = _consolidation_buffer
			_consolidation_buffer = null
			_consolidation_shots = 0
		elif _consolidation_buffer != null:
			for s in packet.synergies:
				_consolidation_buffer.add_synergy(s, packet.synergies[s])
			packet = _consolidation_buffer
			_consolidation_buffer = null
			_consolidation_shots = 0

	# Chopper split (see HexTile._fire_combined_projectile's matching block
	# for the full rationale/saturation-aware clamp) - a Missile Rack's
	# "one combined release" is a whole Hunter salvo or AOE burst; splitting
	# it peels the SAME total magnitude into N smaller releases instead of
	# one, each independently going through targeting/salvo-count below.
	# Deliberately mutually exclusive with nothing here (Missile Rack has no
	# mythic_pattern fanout to bound against), but still saturation-clamped
	# for the same worst-case-fanout reason.
	if not _pattern_child and not _chopper_child and packet.chopper_split > 1:
		var n = packet.chopper_split
		var saturation_k = ProjectileManager.consolidation_factor()
		if saturation_k > 1:
			n = max(1, ceili(float(n) / saturation_k))
		if n > 1:
			for i in range(n - 1):
				var piece = packet.split(1.0 / float(n) / (1.0 - (1.0 / float(n)) * i))
				_fire_combined_projectile(mech, piece, step, false, 0.0, true)
			_fire_combined_projectile(mech, packet, step, false, 0.0, true)
			return

	var world = mech.get_parent()
	if not world:
		return

	var muzzle = get_muzzle_position(mech)
	var by_player = mech.get("is_player") == true

	var total_mag = 0.0
	for k in packet.synergies:
		total_mag += packet.synergies[k]
	var kinetic_ratio = (packet.synergies.get(EnergyPacket.SynergyType.KINETIC, 0.0) / total_mag) if total_mag > 0.0 else 0.0
	var max_range = (ProjectileScript.BASE_RANGE + ProjectileScript.KINETIC_RANGE_BONUS * kinetic_ratio) * RANGE_MULT
	var min_range = MIN_RANGE_RADIUS_MULT * _estimate_effective_radius(packet, total_mag)
	var nuke_scale = _nuke_scale(total_mag)

	var target = _find_target_in_range(muzzle, by_player, min_range, max_range)
	if target == null:
		return # nothing in [min_range, max_range] - dry-fire, same as any weapon with no target

	# Feed the director's mortar counter-doctrine (cloaks/jammers answer
	# artillery) exactly like WeaponMountTile's Mythic Mortar pattern does -
	# a Missile Rack salvo is exactly the kind of indirect-fire "artillery"
	# that doctrine exists to counter, and player shots only (see
	# MortarShell._detonate's matching gate: the AI countering itself would
	# be silly).
	if by_player:
		var main = mech.get_tree().current_scene if mech.is_inside_tree() else null
		if main and "world" in main and main.world and main.world.has_node("SquadDirector"):
			main.world.get_node("SquadDirector").log_mortar_shot()

	var pierce_ratio = (packet.synergies.get(EnergyPacket.SynergyType.PIERCE, 0.0) / total_mag) if total_mag > 0.0 else 0.0
	# Same pierce-scales-flight-speed identity as the Mythic Mortar pattern
	# (see HexTile._fire_mortar) - a Missile Rack investing in Pierce still
	# gets the "faster shells" payoff instead of losing that whole axis.
	var effective_speed = SHELL_SPEED_BASE * (1.0 + pierce_ratio * 2.0)

	# Lead prediction (user report 2026-08-05: "missiles weren't doing much
	# damage"). The Mythic Mortar pattern also fires at a static aim point
	# (HexTile._fire_mortar) but the PLAYER chooses and can adjust that point
	# - here nothing compensates for target movement at all. A shell's
	# flight_time can run up to 2.2s; the FURTHEST-in-range target (this
	# mount's whole targeting identity) is exactly the enemy most likely to
	# be actively repositioning rather than beelining at the player, so by
	# landing time it had very plausibly walked clean out of the ~40px splash
	# floor, wasting the shot on empty ground. Single-pass estimate (not
	# iteratively refined - close enough at these ranges/speeds): flight time
	# from the target's CURRENT position, then extrapolate its position
	# forward by that long using its own CharacterBody2D.velocity.
	var target_pos = target.global_position
	var est_flight_time = clamp(muzzle.distance_to(target_pos) / effective_speed, 0.12, 2.2)
	target_pos += target.velocity * est_flight_time

	var base_damage = packet.magnitude * _get_damage_multiplier() * _get_power_multiplier()

	if rarity == HexTile.Rarity.MYTHIC and mythic_mode == 1:
		_fire_aoe_burst(mech, world, muzzle, target_pos, packet, total_mag, by_player, base_damage, nuke_scale)
	else:
		_fire_hunter_salvo(mech, world, muzzle, target_pos, packet, by_player, effective_speed, base_damage, nuke_scale)

# Hunter mode (default at every rarity, and Mythic mythic_mode == 0): several
# shells, all aimed at the one furthest-in-range target - "throws everything
# at a single target." This is the pre-existing salvo behavior, unchanged,
# just extracted into its own function so _fire_combined_projectile can
# branch to AOE mode instead.
func _fire_hunter_salvo(mech, world: Node, muzzle: Vector2, target_pos: Vector2, packet: EnergyPacket, by_player: bool, effective_speed: float, base_damage: float, nuke_scale: float = 0.0):
	var shell_count = int(TileStatsRegistry.get_stat_by_rarity("MissileRackTile", "shell_count", rarity, SHELL_COUNT_BY_RARITY))
	var per_shell_damage = (base_damage / float(shell_count)) * PER_SHELL_DAMAGE_FRACTION

	for i in range(shell_count):
		# Ring layout, one jittered slot per shell - reads as a scattered
		# salvo rather than N shells landing in an identical stack.
		var angle = (TAU * float(i) / shell_count) + randf_range(-0.2, 0.2)
		var offset = Vector2(cos(angle), sin(angle)) * SPREAD_RADIUS * randf_range(0.4, 1.0)
		var impact_pos = target_pos + offset
		var flight_time = clamp(muzzle.distance_to(impact_pos) / effective_speed, 0.12, 2.2)
		# Small stagger so shells don't all land on the same frame - the
		# launch still reads simultaneous, only the landing staggers
		# (matches "a spread... instead of one big payload").
		flight_time += i * 0.06

		# load(path), not the bare global class name - see HexTile._fire_mortar's
		# matching comment for why (compile-time circular-dependency failure).
		var shell = load("res://scripts/attacks/MortarShell.gd").acquire()
		shell.setup(muzzle, impact_pos, flight_time, per_shell_damage, packet.synergies.duplicate(), by_player, mech, packet.aoe_bonus, 1.0, false, mythic_frame_multiplier, nuke_scale)
		world.add_child(shell)

# AOE mode (Mythic mythic_mode == 1 only, user-designed): a single big burst
# instead of a shell salvo - carries the FULL undivided base_damage ("the
# totality of damage the missile would have done"), no PER_SHELL_DAMAGE_
# FRACTION/shell_count split at all, and MortarShell's new equal_split_all_
# victims mode divides that total equally across whatever it actually
# struck (see MortarShell._detonate_equal_split). Blast radius starts wide
# (AOE_BASE_RADIUS_MULT) and grows EXPONENTIALLY with Explosion synergy
# investment on top of the shared explosion_radius_for() base - a fresh,
# first-pass tuning (no live playtest available in this environment to
# verify against), flag for a balance pass once tested in-game.
const AOE_BASE_RADIUS_MULT = 1.8
const AOE_EXPLOSION_EXP_K = 0.9

func _fire_aoe_burst(mech, world: Node, muzzle: Vector2, target_pos: Vector2, packet: EnergyPacket, total_mag: float, by_player: bool, base_damage: float, nuke_scale: float = 0.0):
	var r_explosion = (packet.synergies.get(EnergyPacket.SynergyType.EXPLOSION, 0.0) / total_mag) if total_mag > 0.0 else 0.0
	var radius_mult = AOE_BASE_RADIUS_MULT * exp(AOE_EXPLOSION_EXP_K * r_explosion)
	var flight_time = clamp(muzzle.distance_to(target_pos) / SHELL_SPEED_BASE, 0.12, 2.2)

	# load(path), not the bare global class name - see HexTile._fire_mortar's
	# matching comment for why (compile-time circular-dependency failure).
	var shell = load("res://scripts/attacks/MortarShell.gd").acquire()
	shell.setup(muzzle, target_pos, flight_time, base_damage, packet.synergies.duplicate(), by_player, mech, packet.aoe_bonus, radius_mult, true, mythic_frame_multiplier, nuke_scale)
	world.add_child(shell)


# Target-spreading (user, 2026-08-13: "it'd be cool if the missiles were a
# little cleverer - I'd like to avoid 20 missiles hitting one target"). Both
# pick rules below are otherwise fully deterministic (always the single
# furthest, or always the single toughest) - a build with several Missile
# Racks, or several missile-armed mechs on the same side, independently
# re-runs the exact same rule against the exact same candidate pool and so
# always converges on the identical target, dumping every rack's salvo onto
# one enemy while the rest of the field goes untouched. Shared (not per-
# tile) so racks on the SAME mech spread across each other too, not just
# across different mechs. Keyed by instance_id (a plain int, not an object
# reference) so a freed target's entry is harmless dead weight, not a
# dangling reference - never worth pruning at this scale (at most a few
# hundred entries across a whole run).
static var _recent_targets: Dictionary = {} # target instance_id -> Time.get_ticks_msec() of its last pick
const RECENT_TARGET_WINDOW_MS = 1200
# Multiplicative, not a flat subtraction - the two pick rules below score on
# completely different scales (pixel distances vs. max_hp), so a single
# flat penalty could easily be tuned wrong for one of them. A recently-
# targeted candidate isn't excluded outright, just demoted - if it's the
# ONLY valid candidate in range, it still wins (a lone enemy never becomes
# untargetable just because it was already hit).
const RECENT_TARGET_SCORE_MULT = 0.15

static func _is_recently_targeted(target) -> bool:
	var iid = target.get_instance_id()
	if not _recent_targets.has(iid):
		return false
	return Time.get_ticks_msec() - _recent_targets[iid] < RECENT_TARGET_WINDOW_MS

static func _mark_targeted(target) -> void:
	_recent_targets[target.get_instance_id()] = Time.get_ticks_msec()

# Dispatches to whichever pick rule targeting_mode selects (Mythic-only,
# see that field's own comment - non-Mythic racks always get Furthest).
# min_range/max_range are shared by both modes; only the pick rule inside
# that window differs.
func _find_target_in_range(muzzle: Vector2, by_player: bool, min_range: float, max_range: float):
	if rarity == HexTile.Rarity.MYTHIC and targeting_mode == 1:
		return _find_most_powerful_target_in_range(muzzle, by_player, min_range, max_range)
	return _find_furthest_target_in_range(muzzle, by_player, min_range, max_range)

# Scans the opposing EntityCache group (same convention as MortarShell.
# _detonate/Projectile.gd's own homing-target scans) for the single FARTHEST
# valid target inside [min_range, max_range] from the muzzle - null if none
# qualify. Furthest, not nearest: this is meant to reach out and hit
# something a direct-fire mount can't, not to plink the closest target.
# Returns the target NODE itself (not just its position) - the call site
# reads its .velocity for lead prediction.
func _find_furthest_target_in_range(muzzle: Vector2, by_player: bool, min_range: float, max_range: float):
	var candidates: Array = EntityCache.get_group("enemy") if by_player else EntityCache.get_group("player")
	var best = null
	var best_score = -1.0
	for c in candidates:
		if not is_instance_valid(c) or c.get("is_dead"):
			continue
		var d = muzzle.distance_to(c.global_position)
		if d < min_range or d > max_range:
			continue
		var score = d
		if _is_recently_targeted(c):
			score *= RECENT_TARGET_SCORE_MULT
		if score > best_score:
			best_score = score
			best = c
	if best != null:
		_mark_targeted(best)
	return best

# Most Powerful (Mythic targeting_mode == 1): the single valid target in
# [min_range, max_range] with the highest max_hp - a proxy for "biggest
# threat on the field" in the absence of any other explicit power/threat
# stat on Mech.gd. Same range gate as Furthest, just a different pick
# rule once the candidate pool is filtered.
func _find_most_powerful_target_in_range(muzzle: Vector2, by_player: bool, min_range: float, max_range: float):
	var candidates: Array = EntityCache.get_group("enemy") if by_player else EntityCache.get_group("player")
	var best = null
	var best_score = -1.0
	for c in candidates:
		if not is_instance_valid(c) or c.get("is_dead"):
			continue
		var d = muzzle.distance_to(c.global_position)
		if d < min_range or d > max_range:
			continue
		var power = c.get("max_hp") if "max_hp" in c else 0.0
		var score = power
		if _is_recently_targeted(c):
			score *= RECENT_TARGET_SCORE_MULT
		if score > best_score:
			best_score = score
			best = c
	if best != null:
		_mark_targeted(best)
	return best
