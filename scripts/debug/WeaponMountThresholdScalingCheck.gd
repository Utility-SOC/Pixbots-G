extends Node

# Regression harness for the unified frame-quanta capacity system (replaces
# the old standalone energy-threshold system this file used to test - see
# HexTile.get_frame_multiplier_options()/cycle_mythic_frame_multiplier(),
# AccumulatorTile.mythic_capacity_dial, and ReverseAccumulatorTile.gd's new
# "Chopper" split ability). Covers:
#   1. Base options with nothing adjacent.
#   2. A Mythic Accumulator at its default dial (1) contributes nothing -
#      no freebie just from proximity.
#   3. One Mythic Accumulator dialed to 64 adds exactly one +64 tier.
#   4. Two stacked (64 + 16) add exactly one +80 tier (not a whole ladder).
#   5. A non-Mythic Accumulator, even forcibly dialed to 64, contributes
#      nothing - proves the Mythic-only gate on the consumer side, not
#      just the producer's own cycle-gate.
#   6. cycle_mythic_frame_multiplier() walks the full dynamic list exactly
#      once each, including wraparound.
#   7. Cycling is a no-op at non-Mythic rarity.
#   8. Chopper split-factor aggregation: one dialed to 2 -> factor 2; two
#      stacked (2+2) -> factor 4; none/default-only -> factor 1.
#   9. End-to-end numeric split correctness: N resulting packets each carry
#      total/N magnitude and sum back to the original (mirrors the user's
#      own 600k -> 2x300k / 4x150k example).

const WeaponMountTileScript = preload("res://scripts/tiles/WeaponMountTile.gd")
const AccumulatorTileScript = preload("res://scripts/tiles/AccumulatorTile.gd")
const ReverseAccumulatorTileScript = preload("res://scripts/tiles/ReverseAccumulatorTile.gd")
const HexGridComponentScript = preload("res://scripts/core/HexGridComponent.gd")
const EnergyPacketScript = preload("res://scripts/core/EnergyPacket.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var origin = HexCoord.new(0, 0)
	var n0 = origin.neighbor(0)
	var n1 = origin.neighbor(1)

	# --- 1: no accumulators adjacent -----------------------------------------
	var grid_a = HexGridComponentScript.new()
	var mount_a = WeaponMountTileScript.new()
	grid_a.add_tile(origin, mount_a)
	_check("with nothing adjacent, options match the base list exactly",
		mount_a.get_frame_multiplier_options(grid_a, origin) == [1, 2, 16, 64])

	# --- 2: Mythic Accumulator at default dial (1) contributes nothing ------
	var grid_b = HexGridComponentScript.new()
	var mount_b = WeaponMountTileScript.new()
	grid_b.add_tile(origin, mount_b)
	var acc_default = AccumulatorTileScript.new()
	acc_default.rarity = HexTile.Rarity.MYTHIC
	grid_b.add_tile(n0, acc_default)
	_check("a Mythic Accumulator left at its default dial (1) contributes no bonus",
		mount_b.get_frame_multiplier_options(grid_b, origin) == [1, 2, 16, 64])

	# --- 3: one Mythic Accumulator dialed to 64 adds exactly one +64 tier ---
	var grid_c = HexGridComponentScript.new()
	var mount_c = WeaponMountTileScript.new()
	grid_c.add_tile(origin, mount_c)
	var acc_c = AccumulatorTileScript.new()
	acc_c.rarity = HexTile.Rarity.MYTHIC
	acc_c.mythic_capacity_dial = 64
	grid_c.add_tile(n0, acc_c)
	_check("one Mythic Accumulator dialed to 64 adds exactly one +64 tier",
		mount_c.get_frame_multiplier_options(grid_c, origin) == [1, 2, 16, 64, 128])

	# --- 4: two stacked (64 + 16) add exactly one +80 tier -------------------
	var grid_d = HexGridComponentScript.new()
	var mount_d = WeaponMountTileScript.new()
	grid_d.add_tile(origin, mount_d)
	var acc_d1 = AccumulatorTileScript.new()
	acc_d1.rarity = HexTile.Rarity.MYTHIC
	acc_d1.mythic_capacity_dial = 64
	grid_d.add_tile(n0, acc_d1)
	var acc_d2 = AccumulatorTileScript.new()
	acc_d2.rarity = HexTile.Rarity.MYTHIC
	acc_d2.mythic_capacity_dial = 16
	grid_d.add_tile(n1, acc_d2)
	_check("two stacked Accumulators (64+16) add exactly one +80 tier, not a whole ladder",
		mount_d.get_frame_multiplier_options(grid_d, origin) == [1, 2, 16, 64, 144])

	# --- 5: non-Mythic Accumulator contributes nothing, even if dial forced -
	var grid_e = HexGridComponentScript.new()
	var mount_e = WeaponMountTileScript.new()
	grid_e.add_tile(origin, mount_e)
	var acc_e = AccumulatorTileScript.new()
	acc_e.rarity = HexTile.Rarity.RARE
	acc_e.mythic_capacity_dial = 64 # forced directly, bypassing the cycle's own gate
	grid_e.add_tile(n0, acc_e)
	_check("a non-Mythic Accumulator contributes nothing even with its dial forced to 64",
		mount_e.get_frame_multiplier_options(grid_e, origin) == [1, 2, 16, 64])

	# --- 6/7: cycling walks the full list once each, wraps, no-ops below Mythic
	var grid_f = HexGridComponentScript.new()
	var mount_f = WeaponMountTileScript.new()
	grid_f.add_tile(origin, mount_f)
	var acc_f = AccumulatorTileScript.new()
	acc_f.rarity = HexTile.Rarity.MYTHIC
	acc_f.mythic_capacity_dial = 64
	grid_f.add_tile(n0, acc_f)

	mount_f.rarity = HexTile.Rarity.RARE # non-Mythic mount: cycling must no-op
	var before = mount_f.mythic_frame_multiplier
	mount_f.cycle_mythic_frame_multiplier(grid_f, origin)
	_check("cycling is a no-op at non-Mythic rarity",
		mount_f.mythic_frame_multiplier == before)

	mount_f.rarity = HexTile.Rarity.MYTHIC
	var full_options = mount_f.get_frame_multiplier_options(grid_f, origin)
	var seen_set = {}
	for i in range(full_options.size()):
		seen_set[mount_f.mythic_frame_multiplier] = true
		mount_f.cycle_mythic_frame_multiplier(grid_f, origin)
	_check("cycling through the whole dynamic list visits every option exactly once",
		seen_set.size() == full_options.size())
	_check("cycling wraps back to the start after a full cycle",
		mount_f.mythic_frame_multiplier == full_options[0])

	# --- 8: Chopper split-factor aggregation ---------------------------------
	var grid_g = HexGridComponentScript.new()
	var mount_g = WeaponMountTileScript.new()
	grid_g.add_tile(origin, mount_g)
	_check("no adjacent Chopper -> split factor floors to 1",
		MechScript._get_adjacent_chopper_split_factor(grid_g, origin) == 1)

	var chop_g1 = ReverseAccumulatorTileScript.new()
	chop_g1.rarity = HexTile.Rarity.MYTHIC
	chop_g1.mythic_split_factor = 2
	grid_g.add_tile(n0, chop_g1)
	_check("one Mythic Chopper dialed to 2 gives a split factor of 2",
		MechScript._get_adjacent_chopper_split_factor(grid_g, origin) == 2)

	var chop_g2 = ReverseAccumulatorTileScript.new()
	chop_g2.rarity = HexTile.Rarity.MYTHIC
	chop_g2.mythic_split_factor = 2
	grid_g.add_tile(n1, chop_g2)
	_check("two Mythic Choppers each dialed to 2 combine additively to a split factor of 4",
		MechScript._get_adjacent_chopper_split_factor(grid_g, origin) == 4)

	var grid_h = HexGridComponentScript.new()
	var mount_h = WeaponMountTileScript.new()
	grid_h.add_tile(origin, mount_h)
	var chop_h_dialed = ReverseAccumulatorTileScript.new()
	chop_h_dialed.rarity = HexTile.Rarity.MYTHIC
	chop_h_dialed.mythic_split_factor = 2
	grid_h.add_tile(n0, chop_h_dialed)
	var chop_h_default = ReverseAccumulatorTileScript.new()
	chop_h_default.rarity = HexTile.Rarity.MYTHIC
	# left at default (1) - must contribute nothing, not a spurious +1
	grid_h.add_tile(n1, chop_h_default)
	_check("a default-dialed (1) adjacent Chopper contributes nothing alongside a real one (got %d, expect 2)" % MechScript._get_adjacent_chopper_split_factor(grid_h, origin),
		MechScript._get_adjacent_chopper_split_factor(grid_h, origin) == 2)

	# --- 9: end-to-end numeric split correctness ------------------------------
	# Mirrors the exact peel-loop HexTile._fire_combined_projectile uses.
	var original = EnergyPacketScript.new(600000.0, null)
	original.synergies.clear()
	original.synergies[EnergyPacketScript.SynergyType.RAW] = 600000.0
	var n = 2
	var pieces: Array = []
	var remaining = original
	for i in range(n - 1):
		pieces.append(remaining.split(1.0 / float(n) / (1.0 - (1.0 / float(n)) * i)))
	pieces.append(remaining)

	var total_check = 0.0
	var all_equal_share = true
	for p in pieces:
		total_check += p.magnitude
		if abs(p.magnitude - 300000.0) > 1.0:
			all_equal_share = false
	_check("a 600,000-magnitude packet split 2 ways gives 2 pieces of ~300,000 each (mirrors the user's own example)",
		all_equal_share)
	_check("the split pieces sum back to the original total magnitude",
		abs(total_check - 600000.0) < 1.0)

	if failures == 0:
		print("PASS: unified frame-quanta capacity system (Weapon Mount/Missile Rack/Accumulator dial) and Chopper split-factor aggregation both correct")
	get_tree().quit(0 if failures == 0 else 1)
