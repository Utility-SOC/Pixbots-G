extends Node

# Regression harness for: "tons of energy going to the left arm link
# nothing inside the left arm."
#
# Root cause: Mech._simulate_grid's closed-loop safety cap was only 100
# steps. That function is used BOTH by real combat (_recalculate_grid,
# once per loadout change) AND by the Garage's dummy transfer preview
# (GarageSimulationRunner._compute_initial_packets, "2. Add actual transfer
# packets from Torso"). The Mythic-overcharge feature (EnergyPacket.
# NORMAL_MAGNITUDE_CAP) deliberately rewards long closed annexes of Mythic
# tiles that build energy before dropping it to a sink/weapon - but on a
# large Mythic torso, simply CROSSING the grid once can take well over 100
# steps, which silently dropped every packet before it ever reached a Link
# tile. The Torso's OWN live view uses a completely separate engine
# (GarageSimulationRunner._advance_step, uncapped until natural drain), so
# the energy visibly circulating there gave no hint that the transfer
# computation itself was cutting it off early - "tons of energy going to
# the left arm link" (true, in the Torso's own view) "nothing inside the
# left arm" (also true - the dummy transfer computation never got that far).
#
# Fixed by raising Mech._simulate_grid's SIMULATE_GRID_STEP_CAP from 100 to
# 1000 - cheap since this only ever runs once per loadout change, never
# per-frame.

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")
const ComponentLinkTileScript = preload("res://scripts/tiles/ComponentLinkTile.gd")
const ReflectorTileScript = preload("res://scripts/tiles/ReflectorTile.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# A straight run of 149 Mythic Reflectors (pure pass-through, no
	# magnitude change) between the Core and the Left Arm Link - a packet
	# needs 150 simulation steps just to cross it once, comfortably past
	# the old 100-step cap but well inside the new one.
	var torso = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.MYTHIC)
	var hexes: Array[HexCoord] = []
	for q in range(151):
		hexes.append(HexCoord.new(q, 0))
	torso.valid_hexes = hexes
	torso._rebuild_valid_hex_set()

	var core = CoreTileScript.new()
	core.body_slot = HexTile.BodySlot.TORSO
	core.rarity = HexTile.Rarity.MYTHIC
	core.active_faces.clear()
	core.active_faces.append(0) # East, down the long path
	torso.hex_grid.add_tile(HexCoord.new(0, 0), core)

	for q in range(1, 150):
		var refl = ReflectorTileScript.new()
		refl.body_slot = HexTile.BodySlot.TORSO
		refl.rarity = HexTile.Rarity.MYTHIC
		refl.rotation_steps = 0
		torso.hex_grid.add_tile(HexCoord.new(q, 0), refl)

	var l_arm_sink = ComponentLinkTileScript.new(HexTile.BodySlot.ARM_L, true)
	l_arm_sink.body_slot = HexTile.BodySlot.TORSO
	l_arm_sink.rarity = HexTile.Rarity.MYTHIC
	torso.hex_grid.add_tile(HexCoord.new(150, 0), l_arm_sink)

	var t_pkts = core.generate_energy(torso.hex_grid)
	for p in t_pkts:
		p.position = HexCoord.new(0, 0)

	var mech = MechScript.new()
	mech._simulate_grid(torso.hex_grid, t_pkts)
	var transfers = mech._collect_transfers(torso)

	_check("a packet needing 150 steps to cross the grid still reaches the Left Arm Link",
		transfers.has(HexTile.BodySlot.ARM_L) and transfers[HexTile.BodySlot.ARM_L].size() > 0)
	if transfers.has(HexTile.BodySlot.ARM_L) and transfers[HexTile.BodySlot.ARM_L].size() > 0:
		_check("the transferred packet kept its full magnitude (pure pass-through Reflectors, no cap/split involved)",
			abs(transfers[HexTile.BodySlot.ARM_L][0].magnitude - core.get_power_output()) < 0.01)

	mech.free()

	if failures == 0:
		print("PASS: long Mythic paths/loops no longer get silently cut off before reaching a Link tile")
	get_tree().quit(0 if failures == 0 else 1)
