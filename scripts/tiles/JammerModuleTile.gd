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

func get_weight() -> float:
	return 4.0 # a pulse-jammer emitter, moderate hardware

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null) -> Array[EnergyPacket]:
	if packet.magnitude <= 0.0 or not packet.is_active: return []

	packet.is_active = false
	stored_energy += packet.magnitude * (1.0 + rarity * 0.5)

	return []

func get_jam_energy() -> float:
	var e = stored_energy
	stored_energy = 0.0
	return e

func get_pulse_radius() -> float:
	# x1.7: fields read as too small/subtle in play relative to how good
	# they look - rarity scaling (more power = bigger field) unchanged,
	# just the whole curve scaled up.
	return (220.0 + rarity * 60.0) * 1.7

func get_pulse_interval() -> float:
	match rarity:
		Rarity.MYTHIC: return 4.0
		Rarity.LEGENDARY: return 5.0
		Rarity.RARE: return 6.5
		Rarity.UNCOMMON: return 8.0
		_: return 10.0

func get_effect_duration() -> float:
	return 1.5 + rarity * 0.5
