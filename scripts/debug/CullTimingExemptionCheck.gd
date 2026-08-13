extends Node

# Regression harness for the 2026-08-11 cull-timing fix (see Mech.gd's
# _simulate_grid comment for the full root-cause writeup): a packet whose
# magnitude has dropped below NEGLIGIBLE_MAGNITUDE_FLOOR must NOT be culled
# if its next hop lands on a real tile - it's still correctly in transit,
# not wandering pointlessly. Only a low-magnitude packet with nothing real
# ahead of it should actually get culled.
#
# Repros the exact shape of the original bug at minimal scale: a straight
# run of equal-split Splitters (each halving magnitude, half discarded off
# into empty space) deep enough that the surviving half drops under the
# 2.0 floor while it still has real tiles left to cross before the sink.

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")
const SplitterTileScript = preload("res://scripts/tiles/SplitterTile.gd")
const ComponentLinkTileScript = preload("res://scripts/tiles/ComponentLinkTile.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# Core (power 10, Common) -> 4x equal-split Splitter (East continues,
	# South discarded into empty space) -> Link sink.
	# Magnitude along the East chain: 10 -> 5 -> 2.5 -> 1.25 -> 0.625.
	# The last two hops are already under the 2.0 floor while still having
	# a real tile ahead - exactly the gap the fix closes.
	var torso = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.COMMON)
	var hexes: Array[HexCoord] = []
	for q in range(6):
		hexes.append(HexCoord.new(q, 0))
		hexes.append(HexCoord.new(q, 1)) # discard hexes south of the chain
	torso.valid_hexes = hexes
	torso._rebuild_valid_hex_set()

	var core = CoreTileScript.new()
	core.body_slot = HexTile.BodySlot.TORSO
	core.rarity = HexTile.Rarity.COMMON
	core.active_faces.clear()
	core.active_faces.append(0) # East
	torso.hex_grid.add_tile(HexCoord.new(0, 0), core)

	for q in range(1, 5):
		var splitter = SplitterTileScript.new()
		splitter.body_slot = HexTile.BodySlot.TORSO
		splitter.rarity = HexTile.Rarity.COMMON
		var faces: Array[int] = [0, 2] # East continues, South-ish is discarded
		splitter.active_faces = faces
		torso.hex_grid.add_tile(HexCoord.new(q, 0), splitter)

	var l_arm_sink = ComponentLinkTileScript.new(HexTile.BodySlot.ARM_L, true)
	l_arm_sink.body_slot = HexTile.BodySlot.TORSO
	l_arm_sink.rarity = HexTile.Rarity.COMMON
	torso.hex_grid.add_tile(HexCoord.new(5, 0), l_arm_sink)

	var t_pkts = core.generate_energy(torso.hex_grid)
	for p in t_pkts:
		p.position = HexCoord.new(0, 0)

	var mech = MechScript.new()
	# force_gdscript=true: this specific synthetic chain (real tiles only
	# 6 hexes wide) happens not to trigger the pre-fix bug via the Rust fast
	# path even with the old cull code reverted and rebuilt - confirmed by
	# hand via git-checkout-old-file + rebuild + rerun, both forced-GDScript
	# (correctly FAILED on old code) and default/Rust-first (unexpectedly
	# PASSED on old code even though hexgrid_sim.rs's cull block was also
	# reverted). Root cause not chased further - flagged as its own
	# follow-up (see MEMORY.md project notes) rather than block this check.
	# Forcing GDScript here keeps this check deterministic and meaningful;
	# RustGridSimParityCheck.gd is the actual GDScript/Rust parity harness.
	mech._simulate_grid(torso.hex_grid, t_pkts, true)
	var transfers = mech._collect_transfers(torso)

	_check("a packet that drops under the negligible-magnitude floor mid-chain still reaches the sink",
		transfers.has(HexTile.BodySlot.ARM_L) and transfers[HexTile.BodySlot.ARM_L].size() > 0)
	if transfers.has(HexTile.BodySlot.ARM_L) and transfers[HexTile.BodySlot.ARM_L].size() > 0:
		_check("the surviving packet kept the expected halved-4x magnitude (~0.625), not zeroed out early",
			abs(transfers[HexTile.BodySlot.ARM_L][0].magnitude - 0.625) < 0.01)

	mech.free()

	if failures == 0:
		print("PASS: negligible-magnitude packets still in real transit are exempt from the perf cull")
	get_tree().quit(0 if failures == 0 else 1)
