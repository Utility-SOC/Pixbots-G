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
# picks its OWN target: the FURTHEST enemy within [MIN_RANGE, max_range].
# max_range reuses Projectile.gd's exact kinetic-scales-range formula
# (BASE_RANGE + KINETIC_RANGE_BONUS * kinetic_ratio - see that file's field
# comment for "kinetic should be able to make range MUCH longer") so a
# Missile Rack's own Kinetic investment pays off exactly like it does for
# every other weapon, just with a higher base via RANGE_MULT on top - same
# "final multiplier over the whole computed range" slot Projectile.gd
# already has for range_mult/beam shots, not a parallel range system.
const ProjectileScript = preload("res://scripts/entities/Projectile.gd")
const RANGE_MULT = 2.5 # "ultra long range" - well past a direct-fire mount's reach
const MIN_RANGE = 350.0 # can't hit anything closer than this - not a point-defense gun

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

	var target = _find_furthest_target_in_range(muzzle, by_player, max_range)
	if target == null:
		return # nothing in [MIN_RANGE, max_range] - dry-fire, same as any weapon with no target

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
		_fire_aoe_burst(mech, world, muzzle, target_pos, packet, total_mag, by_player, base_damage)
	else:
		_fire_hunter_salvo(mech, world, muzzle, target_pos, packet, by_player, effective_speed, base_damage)

# Hunter mode (default at every rarity, and Mythic mythic_mode == 0): several
# shells, all aimed at the one furthest-in-range target - "throws everything
# at a single target." This is the pre-existing salvo behavior, unchanged,
# just extracted into its own function so _fire_combined_projectile can
# branch to AOE mode instead.
func _fire_hunter_salvo(mech, world: Node, muzzle: Vector2, target_pos: Vector2, packet: EnergyPacket, by_player: bool, effective_speed: float, base_damage: float):
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
		shell.setup(muzzle, impact_pos, flight_time, per_shell_damage, packet.synergies.duplicate(), by_player, mech, packet.aoe_bonus, 1.0, false, mythic_frame_multiplier)
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

func _fire_aoe_burst(mech, world: Node, muzzle: Vector2, target_pos: Vector2, packet: EnergyPacket, total_mag: float, by_player: bool, base_damage: float):
	var r_explosion = (packet.synergies.get(EnergyPacket.SynergyType.EXPLOSION, 0.0) / total_mag) if total_mag > 0.0 else 0.0
	var radius_mult = AOE_BASE_RADIUS_MULT * exp(AOE_EXPLOSION_EXP_K * r_explosion)
	var flight_time = clamp(muzzle.distance_to(target_pos) / SHELL_SPEED_BASE, 0.12, 2.2)

	# load(path), not the bare global class name - see HexTile._fire_mortar's
	# matching comment for why (compile-time circular-dependency failure).
	var shell = load("res://scripts/attacks/MortarShell.gd").acquire()
	shell.setup(muzzle, target_pos, flight_time, base_damage, packet.synergies.duplicate(), by_player, mech, packet.aoe_bonus, radius_mult, true, mythic_frame_multiplier)
	world.add_child(shell)


# Scans the opposing EntityCache group (same convention as MortarShell.
# _detonate/Projectile.gd's own homing-target scans) for the single FARTHEST
# valid target inside [MIN_RANGE, max_range] from the muzzle - null if none
# qualify. Furthest, not nearest: this is meant to reach out and hit
# something a direct-fire mount can't, not to plink the closest target.
# Returns the target NODE itself (not just its position) - the call site
# reads its .velocity for lead prediction.
func _find_furthest_target_in_range(muzzle: Vector2, by_player: bool, max_range: float):
	var candidates: Array = EntityCache.get_group("enemy") if by_player else EntityCache.get_group("player")
	var best = null
	var best_dist = -1.0
	for c in candidates:
		if not is_instance_valid(c) or c.get("is_dead"):
			continue
		var d = muzzle.distance_to(c.global_position)
		if d < MIN_RANGE or d > max_range:
			continue
		if d > best_dist:
			best_dist = d
			best = c
	return best
