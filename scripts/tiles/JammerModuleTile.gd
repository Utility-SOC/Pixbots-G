class_name JammerModuleTile
extends HexTile

# Equippable pulse-jammer, distinct from the JammerMech role (which is a
# whole separate mech class doing a continuous power-debuff aura). This tile
# goes in a backpack (scout bots rarely, support bots more often) and fires
# a periodic AoE pulse against the player in one of two modes:
#   VISION  - blacks out the player's screen briefly if they're in range
#   SYNERGY - mutes one specific elemental synergy in the player's damage
# Mode and target synergy are rolled once per tile instance so drops have
# variety; higher rarity = bigger radius, shorter cooldown, longer effect.

enum JamMode { VISION, SYNERGY }

@export var jam_mode: JamMode = JamMode.VISION
@export var target_synergy: int = EnergyPacket.SynergyType.RAW

# Optional forced_synergy: when >= 0, this tile is being deliberately built to
# counter whatever synergy the player's been over-relying on (see
# SquadDirector.counter_jam_synergy / Mech._get_reactive_jam_synergy and
# ComponentEquipment.create_dual_utility_backpack/create_support_backpack).
# Forces SYNERGY mode instead of the usual random VISION/SYNERGY coin flip,
# since a deliberately-aimed jammer that then rolls VISION mode would just
# waste the reactive targeting.
func _init(forced_synergy: int = -1):
	super._init("Jammer Module", HexTile.TileCategory.OUTPUT)
	base_color = Color(0.15, 0.15, 0.22)
	if forced_synergy >= 0:
		jam_mode = JamMode.SYNERGY
		target_synergy = forced_synergy
	else:
		jam_mode = JamMode.VISION if randf() < 0.5 else JamMode.SYNERGY
		# Skip RAW (index 0) as a jam target - jamming "no element" is a no-op.
		target_synergy = 1 + (randi() % (EnergyPacket.SynergyType.size() - 1))

var stored_energy: float = 0.0

# Player-facing config (Utility-SOC: "I need to be able to configure the
# jammers I install") - jam_mode/target_synergy were previously only ever
# rolled once at _init() with no way to change them after the fact.
# Deliberately NOT Mythic-gated like GarageTileConfigPopup's other cycle-
# mode tiles (Weapon Mount/Jumpjet/etc.) - these are base stats a jammer
# always has, not an unlocked mythic ability.
func cycle_jam_mode():
	jam_mode = JamMode.SYNERGY if jam_mode == JamMode.VISION else JamMode.VISION

func cycle_target_synergy():
	# Skip RAW (index 0), same as the random roll in _init() does - jamming
	# "no element" is a no-op.
	var count = EnergyPacket.SynergyType.size()
	target_synergy = 1 + (target_synergy % (count - 1))

func get_weight() -> float:
	return TileStatsRegistry.get_stat("JammerModuleTile", "weight", 4.0) # a pulse-jammer emitter, moderate hardware

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	if packet.magnitude <= 0.0 or not packet.is_active: return []

	packet.is_active = false
	stored_energy += packet.magnitude * (1.0 + rarity * TileStatsRegistry.get_stat("JammerModuleTile", "energy_storage_rarity_coeff", 0.5))

	return []

func get_jam_energy() -> float:
	var e = stored_energy
	stored_energy = 0.0
	return e

func get_pulse_radius() -> float:
	# x1.7: fields read as too small/subtle in play relative to how good
	# they look - rarity scaling (more power = bigger field) unchanged,
	# just the whole curve scaled up.
	var base = TileStatsRegistry.get_stat("JammerModuleTile", "pulse_radius_base", 220.0)
	var coeff = TileStatsRegistry.get_stat("JammerModuleTile", "pulse_radius_rarity_coeff", 60.0)
	var scale = TileStatsRegistry.get_stat("JammerModuleTile", "pulse_radius_scale", 1.7)
	return (base + rarity * coeff) * scale

func get_pulse_interval() -> float:
	return TileStatsRegistry.get_stat_by_rarity("JammerModuleTile", "pulse_interval_by_rarity", rarity, [10.0, 8.0, 6.5, 5.0, 4.0])

func get_effect_duration() -> float:
	return TileStatsRegistry.get_stat("JammerModuleTile", "effect_duration_base", 1.5) + rarity * TileStatsRegistry.get_stat("JammerModuleTile", "effect_duration_rarity_coeff", 0.5)
