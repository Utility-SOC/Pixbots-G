class_name SensorTile
extends HexTile

# Corporate Sponsorships (task #17): Keeneye Sensing's shared base for its
# three signature tiles (CounterJammerTile/CounterCloakTile/CounterBothTile).
# Design locked: "offers a counter jammer/counter cloak set of
# tiles... they bypass jammers and cloaks," plus a baseline passive sight
# bonus (a recommendation, accepted) so the brand has standing value even
# in fights with no jammer/cloak-equipped enemies at all.
#
# A purely PASSIVE presence effect, not an energy-processing one - mere
# equipped presence (detected in
# Mech._collect_weapon_mounts_and_tile_capabilities via tile_type +
# get_sensor_mode()) grants the capability; process_energy() is a plain
# pass-through so these tiles never disrupt routing if something happens to
# feed them energy.
#
# What "bypasses jammers and cloaks" actually resolves to, given what those
# two systems really do in this codebase:
#   - Jammer: Main._update_player_blind_state() genuinely hides every enemy
#     mech (.visible = false) while the player stands in a hostile jammer
#     field, and Mech.apply_synergy_jam() genuinely mutes a synergy's damage
#     output for a fixed duration - both are real, gateable effects. A
#     Counter-Jammer tile (mech.has_jammer_immunity) skips both.
#   - Cloak: is_cloaked never actually gates targeting or visibility anywhere
#     in this codebase (verified via search) - it's purely a modulate.a fade
#     plus CloakSystem's ambush damage multiplier on the CLOAKED attacker's
#     own outgoing damage. There's nothing to "detect" in the sense of
#     restoring vision. A Counter-Cloak tile (mech.has_cloak_detection)
#     instead negates the ambush multiplier when YOU'RE the one getting hit -
#     see Mech.apply_damage()'s cloak-detection check for the honest caveat
#     about its timing precision.

var mode: String = "jammer" # "jammer" | "cloak" | "both"

func _init(p_mode: String = "jammer"):
	mode = p_mode
	tile_type = "Sensor Array"
	category = TileCategory.SPECIAL
	base_color = Color(0.5, 0.85, 0.75)

func get_weight() -> float:
	return TileStatsRegistry.get_stat("SensorTile", "weight", 3.5)

func get_sensor_mode() -> String:
	return mode

func get_sight_bonus() -> float:
	# Raised from 400 - per the user: "the npc's should be given longer
	# visual range/better sensors," paired with Mech.SIGHT_RANGE's own bump.
	return TileStatsRegistry.get_stat("SensorTile", "sight_bonus", 600.0)

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	return [packet]
