extends Node

# Regression harness for the "mythic components can handle up to 60,000
# energy travelling through" feature request (corrected in chat once we
# established the existing normal ceiling was already 150,000 - an
# all-Mythic loop should reach 600,000, not 60,000/150,000).
#
# Design per the user: "if every piece of that loop is mythic it goes up
# to 600000, if it hits anything non mythic it does a split, 150000 goes
# to the non mythic tile, the rest bounces back."
#
# Implementation: EnergyPacket.NORMAL_MAGNITUDE_CAP (150,000) is the
# effective ceiling any non-Mythic tile will ever accept. Mech._simulate_
# grid/GarageSimulationRunner._advance_step enforce this AT TILE ENTRY:
# if the tile about to process the packet isn't Mythic and the packet's
# magnitude exceeds NORMAL_MAGNITUDE_CAP, only NORMAL_MAGNITUDE_CAP worth
# splits off to enter the tile - the remainder reflects back (direction
# reversed, position unchanged) into whatever loop it came from. Mythic
# tiles never trigger this, so a packet that only ever touches Mythic
# tiles can keep circulating/accumulating all the way up to
# EnergyPacket.MAX_MAGNITUDE (600,000).

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
	_test_split_and_bounce_end_to_end()
	_test_mythic_path_never_splits()

	if failures == 0:
		print("PASS: mythic-overcharge split/bounce behaves as specified")
	get_tree().quit(0 if failures == 0 else 1)

# A packet at 400,000 magnitude (as if it had already been bouncing in an
# all-Mythic loop elsewhere) heads East out of (0,0) into a LEGENDARY
# Weapon Mount at (1,0). Only 150,000 should reach that mount; the
# remaining 250,000 should reflect back West out of (0,0) and land on a
# MYTHIC Weapon Mount at (-1,0) completely untouched (Mythic never splits).
func _test_split_and_bounce_end_to_end():
	var grid = HexGridComponentScript.new()

	var legendary_mount = WeaponMountTileScript.new()
	legendary_mount.rarity = HexTile.Rarity.LEGENDARY
	grid.add_tile(HexCoord.new(1, 0), legendary_mount)

	var mythic_mount = WeaponMountTileScript.new()
	mythic_mount.rarity = HexTile.Rarity.MYTHIC
	grid.add_tile(HexCoord.new(-1, 0), mythic_mount)

	var mech = MechScript.new()
	var pkt = EnergyPacket.new(400000.0, HexCoord.new(0, 0))
	pkt.direction = 0 # East, toward the Legendary mount
	var starting: Array[EnergyPacket] = [pkt]

	mech._simulate_grid(grid, starting)

	_check("the Legendary (non-Mythic) mount only received NORMAL_MAGNITUDE_CAP (150,000)",
		legendary_mount.pending_packets.size() == 1 and
		abs(legendary_mount.pending_packets[0].packet.magnitude - EnergyPacket.NORMAL_MAGNITUDE_CAP) < 1.0)

	_check("the bounced remainder (250,000) reflected all the way to the Mythic mount unharmed",
		mythic_mount.pending_packets.size() == 1 and
		abs(mythic_mount.pending_packets[0].packet.magnitude - 250000.0) < 1.0)

	mech.free()
	grid.free()

# Two MYTHIC mounts flanking the origin - nothing should ever split here,
# a plain sanity check that the rarity gate genuinely exempts Mythic tiles
# rather than splitting unconditionally above the cap.
func _test_mythic_path_never_splits():
	var grid = HexGridComponentScript.new()
	var mythic_mount = WeaponMountTileScript.new()
	mythic_mount.rarity = HexTile.Rarity.MYTHIC
	grid.add_tile(HexCoord.new(1, 0), mythic_mount)

	var mech = MechScript.new()
	var pkt = EnergyPacket.new(400000.0, HexCoord.new(0, 0))
	pkt.direction = 0
	var starting: Array[EnergyPacket] = [pkt]
	mech._simulate_grid(grid, starting)

	_check("a Mythic mount receives the full overcharged magnitude with no split",
		mythic_mount.pending_packets.size() == 1 and
		abs(mythic_mount.pending_packets[0].packet.magnitude - 400000.0) < 1.0)

	mech.free()
	grid.free()
