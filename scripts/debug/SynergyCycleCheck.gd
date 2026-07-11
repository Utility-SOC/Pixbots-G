extends Node

# Regression harness for the synergy-config ergonomics ruling: every
# element-cycling tile defaults to RAW and cycles BOTH directions
# (left/right click in the config popup), and an unconfigured (RAW)
# Infuser is a pure pass-through instead of minting free energy.

const CatalystTileScript = preload("res://scripts/tiles/CatalystTile.gd")
const InfuserTileScript = preload("res://scripts/tiles/InfuserTile.gd")
const MicrocoreTileScript = preload("res://scripts/tiles/MicrocoreTile.gd")

func _ready():
	var failures = 0
	var RAW = EnergyPacket.SynergyType.RAW
	var VAMPIRIC = EnergyPacket.SynergyType.VAMPIRIC

	# --- Catalyst: RAW default, both directions, wrap both ways ---
	var cat = CatalystTileScript.new()
	if cat.target_synergy != RAW:
		push_error("FAIL: Catalyst should default to RAW, got %d" % cat.target_synergy)
		failures += 1
	cat.cycle_synergy()
	var after_fwd = cat.target_synergy
	cat.cycle_synergy_backward()
	if after_fwd != EnergyPacket.SynergyType.FIRE or cat.target_synergy != RAW:
		push_error("FAIL: Catalyst forward/backward cycle broken")
		failures += 1
	cat.cycle_synergy_backward() # RAW - 1 wraps to the top
	if cat.target_synergy != VAMPIRIC:
		push_error("FAIL: Catalyst backward from RAW should wrap to VAMPIRIC, got %d" % cat.target_synergy)
		failures += 1
	if failures == 0:
		print("1) Catalyst: RAW default, both directions, clean wrap")

	# --- Infuser: RAW default = inert pass-through, cycles both ways ---
	var inf = InfuserTileScript.new()
	if inf.secondary_synergy != RAW:
		push_error("FAIL: Infuser should default to RAW, got %d" % inf.secondary_synergy)
		failures += 1
	var packet = EnergyPacket.new(100.0)
	var mag_before = packet.magnitude
	var out = inf.process_energy(packet, 0)
	if out[0].magnitude != mag_before or out[0].synergies.size() != 1:
		push_error("FAIL: RAW Infuser must be a pure pass-through (mag %.1f -> %.1f)" % [mag_before, out[0].magnitude])
		failures += 1
	inf.cycle_synergy_backward()
	if inf.secondary_synergy != VAMPIRIC:
		push_error("FAIL: Infuser backward from RAW should wrap to VAMPIRIC")
		failures += 1
	inf.secondary_synergy = EnergyPacket.SynergyType.POISON
	var packet2 = EnergyPacket.new(100.0)
	inf.process_energy(packet2, 0)
	if packet2.synergies.get(EnergyPacket.SynergyType.POISON, 0.0) <= 0.0:
		push_error("FAIL: configured Infuser stopped infusing")
		failures += 1
	if failures == 0:
		print("2) Infuser: RAW default is inert, configured infusion still works, wraps both ways")

	# --- Microcore: per-face backward cycle (start-value-agnostic - the
	# CoreTile base presets face outputs, which is fine; what matters is
	# that backward exactly undoes forward and wraps modulo the enum). ---
	var micro = MicrocoreTileScript.new()
	var start = micro.get_face_output(0)
	micro.cycle_face_output(0)
	micro.cycle_face_output_backward(0)
	var undone = micro.get_face_output(0) == start
	micro.cycle_face_output_backward(0)
	var wrapped = micro.get_face_output(0) == (start + EnergyPacket.SynergyType.size() - 1) % EnergyPacket.SynergyType.size()
	if not undone or not wrapped:
		push_error("FAIL: Microcore face backward cycle broken (undone=%s wrapped=%s)" % [undone, wrapped])
		failures += 1
	else:
		print("3) Microcore: backward exactly undoes forward and wraps cleanly")

	if failures == 0:
		print("PASS: RAW defaults + bidirectional cycling everywhere")
	get_tree().quit(0 if failures == 0 else 1)
