extends Node

# Regression harness for the "has_synergy() always returns true" bug found
# by a full-codebase audit: EnergyPacket.has_synergy(type) defaulted
# min_percentage=0.0, so `perc >= 0.0` passed even for a packet with ZERO of
# that synergy (0.0 >= 0.0 is true). MagnetTile/ActuatorTile call
# has_synergy(TYPE) with no explicit threshold specifically to check "does
# this packet carry ANY of this element" - the bug made their Lightning/
# Kinetic bonuses fire unconditionally on every packet, not just ones that
# actually carried that element.

const MagnetTileScript = preload("res://scripts/tiles/MagnetTile.gd")
const ActuatorTileScript = preload("res://scripts/tiles/ActuatorTile.gd")

var failures = 0

func _check(label: String, actual, expected):
	if actual != expected:
		push_error("FAIL: %s - got %s, expected %s" % [label, actual, expected])
		failures += 1
	else:
		print("ok: %s = %s" % [label, actual])

func _ready():
	# --- Direct unit tests of has_synergy() itself ---
	var raw_packet = EnergyPacket.new(10.0, null) # 100% RAW per _init
	_check("100%% RAW packet has_synergy(LIGHTNING) is false", raw_packet.has_synergy(EnergyPacket.SynergyType.LIGHTNING), false)
	_check("100%% RAW packet has_synergy(RAW) is true", raw_packet.has_synergy(EnergyPacket.SynergyType.RAW), true)

	var lightning_packet = EnergyPacket.new(10.0, null)
	lightning_packet.synergies.clear()
	lightning_packet.synergies[EnergyPacket.SynergyType.LIGHTNING] = 10.0
	_check("100%% LIGHTNING packet has_synergy(LIGHTNING) is true", lightning_packet.has_synergy(EnergyPacket.SynergyType.LIGHTNING), true)
	_check("100%% LIGHTNING packet has_synergy(FIRE) is false", lightning_packet.has_synergy(EnergyPacket.SynergyType.FIRE), false)

	# Explicit threshold behavior unchanged for a genuinely mixed packet
	var mixed_packet = EnergyPacket.new(10.0, null)
	mixed_packet.synergies.clear()
	mixed_packet.synergies[EnergyPacket.SynergyType.LIGHTNING] = 3.0
	mixed_packet.synergies[EnergyPacket.SynergyType.FIRE] = 7.0
	_check("30%% LIGHTNING packet has_synergy(LIGHTNING) [no threshold] is true", mixed_packet.has_synergy(EnergyPacket.SynergyType.LIGHTNING), true)
	_check("30%% LIGHTNING packet has_synergy(LIGHTNING, 0.5) is false", mixed_packet.has_synergy(EnergyPacket.SynergyType.LIGHTNING, 0.5), false)
	_check("30%% LIGHTNING packet has_synergy(LIGHTNING, 0.3) is true", mixed_packet.has_synergy(EnergyPacket.SynergyType.LIGHTNING, 0.3), true)

	# --- MagnetTile: Lightning bonus only fires on a packet that actually has it ---
	var magnet_raw = MagnetTileScript.new()
	magnet_raw.process_energy(EnergyPacket.new(10.0, null), 0)
	_check("Magnet: RAW packet does NOT get the Lightning bonus", magnet_raw.get_magnetic_power(), 10.0)

	var magnet_lightning = MagnetTileScript.new()
	var mag_lpkt = EnergyPacket.new(10.0, null)
	mag_lpkt.synergies.clear()
	mag_lpkt.synergies[EnergyPacket.SynergyType.LIGHTNING] = 10.0
	magnet_lightning.process_energy(mag_lpkt, 0)
	_check("Magnet: LIGHTNING packet DOES get the Lightning bonus", magnet_lightning.get_magnetic_power(), 15.0)

	# --- ActuatorTile: Kinetic/Lightning bonuses only fire when actually present ---
	var act_raw = ActuatorTileScript.new()
	act_raw.process_energy(EnergyPacket.new(10.0, null), 0)
	_check("Actuator: RAW packet does NOT get Kinetic/Lightning bonuses", act_raw.current_speed_bonus, 10.0 * act_raw.base_speed_multiplier)

	var act_kinetic = ActuatorTileScript.new()
	var act_kpkt = EnergyPacket.new(10.0, null)
	act_kpkt.synergies.clear()
	act_kpkt.synergies[EnergyPacket.SynergyType.KINETIC] = 10.0
	act_kinetic.process_energy(act_kpkt, 0)
	_check("Actuator: KINETIC packet DOES get the Kinetic bonus", act_kinetic.current_speed_bonus, 10.0 * act_kinetic.base_speed_multiplier * 1.5)

	if failures == 0:
		print("PASS: has_synergy() only returns true when the packet actually carries that synergy")
	get_tree().quit(0 if failures == 0 else 1)
