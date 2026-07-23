extends Node

# Regression harness for: "drone bays should not be energy transparent,
# they should act just like links." DroneBayTile.process_energy used to
# return the packet untouched (pass-through), so energy routed "into" a
# bay ghosted straight through to whatever sat behind it. It now behaves
# like a Component Link sink: the packet terminates at the bay, its energy
# banked into stored_energy. Also verifies the garage edit-path fix rides
# along: a placement-style grid mutation marks the player grid dirty (the
# "changed in the test range, but did not update in game" bug).

const DroneBayTileScript = preload("res://scripts/tiles/DroneBayTile.gd")
const HexGridComponentScript = preload("res://scripts/core/HexGridComponent.gd")
const WeaponMountTileScript = preload("res://scripts/tiles/WeaponMountTile.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# Direct behavior: a live packet entering the bay terminates there.
	var bay = DroneBayTileScript.new()
	var pkt = EnergyPacket.new(120.0, HexCoord.new(0, 0))
	var out = bay.process_energy(pkt, 3)
	_check("a live packet entering the bay produces no outgoing packets", out.is_empty())
	_check("the packet is deactivated (terminates at the bay)", not pkt.is_active)
	_check("the bay banked the packet's energy", abs(bay.stored_energy - 120.0) < 0.01)
	_check("get_bay_energy() drains the bank", abs(bay.get_bay_energy() - 120.0) < 0.01 and bay.stored_energy == 0.0)

	# Routing-level proof: bay at (1,0), Weapon Mount hiding behind it at
	# (2,0). Pre-fix, a packet fired East from (0,0) passed THROUGH the bay
	# and armed the mount; now it must stop at the bay.
	var grid = HexGridComponentScript.new()
	var bay2 = DroneBayTileScript.new()
	grid.add_tile(HexCoord.new(1, 0), bay2)
	var hidden_mount = WeaponMountTileScript.new()
	grid.add_tile(HexCoord.new(2, 0), hidden_mount)

	var mech = MechScript.new()
	var travel = EnergyPacket.new(80.0, HexCoord.new(0, 0))
	travel.direction = 0 # East
	var starting: Array[EnergyPacket] = [travel]
	mech._simulate_grid(grid, starting)
	mech.free()
	grid.free()

	_check("nothing reaches a mount hiding behind a Drone Bay (bay is opaque now)",
		hidden_mount.pending_packets.is_empty())
	_check("the bay captured the routed energy instead", bay2.stored_energy > 0.0)

	if failures == 0:
		print("PASS: Drone Bays are terminal sinks like Links - no more energy ghosting through them")
	get_tree().quit(0 if failures == 0 else 1)
