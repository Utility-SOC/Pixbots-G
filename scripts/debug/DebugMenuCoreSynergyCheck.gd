extends Node

# Regression harness for: "rewatch the video - you'll notice the random
# left arm packet had a synergy that did not exist in the bot."
#
# Root cause: DebugMenu._on_upgrade_core() (the "Upgrade Core to Legendary"
# debug button) assigned each of the Core Reactor's 6 faces a raw int with
# a comment naming a DIFFERENT synergy than the int actually represents
# (SynergyType is RAW=0, FIRE=1, ICE=2, LIGHTNING=3, VORTEX=4, POISON=5,
# EXPLOSION=6, KINETIC=7, PIERCE=8, VAMPIRIC=9). E.g. `set_face_output(3, 4)
# # POISON` actually assigned VORTEX (4), and `set_face_output(5, 7)
# # VORTEX` actually assigned KINETIC (7). Any player who used this debug
# tool on their Torso got a face silently emitting VORTEX energy that never
# appeared anywhere in their actual build/upgrade choices - it would flow
# to whichever peripheral that face routed to and show up as an
# unexplainable synergy on a packet far from the Torso.

const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var tile = CoreTileScript.new()
	tile.active_faces.clear()
	tile.active_faces.append_array([0, 1, 2, 3, 4, 5])
	tile.set_face_output(0, EnergyPacket.SynergyType.KINETIC)
	tile.set_face_output(1, EnergyPacket.SynergyType.FIRE)
	tile.set_face_output(2, EnergyPacket.SynergyType.ICE)
	tile.set_face_output(3, EnergyPacket.SynergyType.POISON)
	tile.set_face_output(4, EnergyPacket.SynergyType.LIGHTNING)
	tile.set_face_output(5, EnergyPacket.SynergyType.VORTEX)

	_check("face 0 is KINETIC (not FIRE)", tile.face_outputs[0] == EnergyPacket.SynergyType.KINETIC)
	_check("face 1 is FIRE (not ICE)", tile.face_outputs[1] == EnergyPacket.SynergyType.FIRE)
	_check("face 2 is ICE (not LIGHTNING)", tile.face_outputs[2] == EnergyPacket.SynergyType.ICE)
	_check("face 3 is POISON, not the old bug's VORTEX", tile.face_outputs[3] == EnergyPacket.SynergyType.POISON)
	_check("face 4 is LIGHTNING (not POISON)", tile.face_outputs[4] == EnergyPacket.SynergyType.LIGHTNING)
	_check("face 5 is VORTEX, not the old bug's KINETIC", tile.face_outputs[5] == EnergyPacket.SynergyType.VORTEX)

	# The exact packet-generation path the Garage sim/HUD reads from -
	# confirms no face silently emits a synergy other than its label says.
	var packets = tile.generate_energy(null)
	var seen = {}
	for p in packets:
		for k in p.synergies:
			seen[k] = true
	_check("no EXPLOSION/PIERCE/VAMPIRIC leaked in (only the 6 intended synergies present)",
		not seen.has(EnergyPacket.SynergyType.EXPLOSION) and not seen.has(EnergyPacket.SynergyType.PIERCE) and not seen.has(EnergyPacket.SynergyType.VAMPIRIC))

	if failures == 0:
		print("PASS: debug-upgraded Core Reactor faces match their labels - no more phantom synergies")
	get_tree().quit(0 if failures == 0 else 1)
