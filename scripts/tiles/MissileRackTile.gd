class_name MissileRackTile
extends HexTile

# Dedicated remote-payload weapon mount (fourth-review ruling: "the full
# weapon-variety version of indirect fire will be a dedicated mount tile,
# not just the Mythic Weapon Mount's Mortar pattern"). Differences from a
# plain Weapon Mount, per that ruling:
#   - Always indirect (no direct-fire mode) - every shot is a MortarShell.gd
#     lob, same delivery WeaponMountTile's Mythic "Mortar" pattern uses.
#   - Cheaper rarity entry: the salvo behavior works at every rarity, not
#     gated behind Mythic + a specific mythic_pattern selection.
#   - Salvo behavior: the accumulated packet is banked into several shells
#     landing in a spread around the aim point (see SHELL_COUNT_BY_RARITY)
#     instead of one single big payload.
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

func _fire_combined_projectile(mech, packet: EnergyPacket, step: int, _pattern_child: bool = false, _extra_angle: float = 0.0):
	var world = mech.get_parent()
	if not world:
		return

	# Feed the director's mortar counter-doctrine (cloaks/jammers answer
	# artillery) exactly like WeaponMountTile's Mythic Mortar pattern does -
	# a Missile Rack salvo is exactly the kind of indirect-fire "artillery"
	# that doctrine exists to counter, and player shots only (see
	# MortarShell._detonate's matching gate: the AI countering itself would
	# be silly).
	if mech.get("is_player") == true:
		var main = mech.get_tree().current_scene if mech.is_inside_tree() else null
		if main and "world" in main and main.world and main.world.has_node("SquadDirector"):
			main.world.get_node("SquadDirector").log_mortar_shot()

	var target_pos: Vector2 = mech.get("last_aim_position") if "last_aim_position" in mech else mech.global_position + Vector2(0, -100)
	var muzzle = get_muzzle_position(mech)

	var total_mag = 0.0
	for k in packet.synergies:
		total_mag += packet.synergies[k]
	var pierce_ratio = (packet.synergies.get(EnergyPacket.SynergyType.PIERCE, 0.0) / total_mag) if total_mag > 0.0 else 0.0
	# Same pierce-scales-flight-speed identity as the Mythic Mortar pattern
	# (see HexTile._fire_mortar) - a Missile Rack investing in Pierce still
	# gets the "faster shells" payoff instead of losing that whole axis.
	var effective_speed = SHELL_SPEED_BASE * (1.0 + pierce_ratio * 2.0)

	var shell_count = int(TileStatsRegistry.get_stat_by_rarity("MissileRackTile", "shell_count", rarity, SHELL_COUNT_BY_RARITY))
	var base_damage = packet.magnitude * _get_damage_multiplier() * _get_power_multiplier()
	var per_shell_damage = (base_damage / float(shell_count)) * PER_SHELL_DAMAGE_FRACTION

	var MortarShellScript = load("res://scripts/attacks/MortarShell.gd")
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

		var shell = MortarShellScript.new()
		shell.setup(muzzle, impact_pos, flight_time, per_shell_damage, packet.synergies.duplicate(), mech.get("is_player") == true, mech, packet.aoe_bonus)
		world.add_child(shell)
