extends Node

# Regression harness for the unified frame-quanta capacity system (also
# covers Chopper's separate split-factor ability). Rewritten for the
# rarity+count Accumulator ladder (replaces the old Mythic-Accumulator-
# only dial - per the user: "accumulators need to be made available early
# in game" - basic/COMMON accumulators now grant a real 2x ceiling instead
# of doing nothing until Mythic). See HexTile.ACCUMULATOR_CAPACITY_TIERS/
# get_frame_multiplier_options()/Mech._get_adjacent_accumulator_capacity_
# tier(). Counting is cumulative (rarity-or-higher): a higher-rarity
# Accumulator always counts toward a lower tier's requirement too. Covers:
#   1. No accumulator adjacent -> Auto only ([1]).
#   2. A single COMMON accumulator (need 1) unlocks the 2x tier by itself.
#   3. A single UNCOMMON accumulator (needs 2, only has 1) falls back to
#      COMMON's tier via cumulative counting, NOT to nothing.
#   4. Two UNCOMMON accumulators meet UNCOMMON's own need-2 -> 4x tier.
#   5. Two RARE accumulators meet RARE's need-2 -> 16x tier.
#   6. Two LEGENDARY accumulators don't meet LEGENDARY's need-3, but DO
#      satisfy RARE's need-2 cumulatively (LEGENDARY >= RARE) -> 16x tier.
#   7. Three LEGENDARY accumulators meet LEGENDARY's own need-3 -> 32x tier.
#   8. A single MYTHIC accumulator (need 1) unlocks the FULL powers-of-two
#      ladder up to 256, not just its own ceiling as one option.
#   9. A mix (1 MYTHIC + 2 RARE) still reaches the Mythic tier - MYTHIC's
#      need-1 is satisfied regardless of what else is present.
#  10. cycle_mythic_frame_multiplier() now works on ANY mount rarity (the
#      old Mythic-mount-only gate is gone) - walks the full dynamic list
#      exactly once each, including wraparound.
#  11. Chopper split-factor aggregation: one dialed to 2 -> factor 2; two
#      stacked (2+2) -> factor 4; none/default-only -> factor 1.
#  12. End-to-end numeric split correctness: N resulting packets each carry
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

func _make_grid_with_accumulators(origin: HexCoord, acc_specs: Array):
	# acc_specs: Array of HexTile.Rarity values, one Accumulator per entry,
	# placed on however many of the 6 neighbor slots are needed (at most 6).
	var grid = HexGridComponentScript.new()
	var mount = WeaponMountTileScript.new()
	grid.add_tile(origin, mount)
	for i in range(acc_specs.size()):
		var acc = AccumulatorTileScript.new()
		acc.rarity = acc_specs[i]
		grid.add_tile(origin.neighbor(i), acc)
	return {"grid": grid, "mount": mount}

func _ready():
	var origin = HexCoord.new(0, 0)

	# --- 1: no accumulators adjacent, non-Mythic mount -----------------------
	var s1 = _make_grid_with_accumulators(origin, [])
	_check("with nothing adjacent, a non-Mythic mount's options are Auto only",
		s1.mount.get_frame_multiplier_options(s1.grid, origin) == [1])

	# --- 1b: a Mythic mount "keeps its internal accumulator" (per the user) -
	# it's self-sufficient for the full ladder with NOTHING adjacent at all,
	# unlike every other rarity. Regression case: the rarity+count rework
	# initially made this purely adjacency-driven, which silently took this
	# away from Mythic mounts too.
	var s1b = _make_grid_with_accumulators(origin, [])
	s1b.mount.rarity = HexTile.Rarity.MYTHIC
	_check("a Mythic mount unlocks the full 256 ladder on its own, no Accumulator needed",
		s1b.mount.get_frame_multiplier_options(s1b.grid, origin) == [1, 2, 4, 8, 16, 32, 64, 128, 256])
	_check("a Mythic mount with no grid context at all (e.g. a bare debug spawn) still gets its full self-sufficient ladder",
		s1b.mount.get_frame_multiplier_options() == [1, 2, 4, 8, 16, 32, 64, 128, 256])

	# --- 2: a single COMMON accumulator (need 1) unlocks 2x by itself -------
	var s2 = _make_grid_with_accumulators(origin, [HexTile.Rarity.COMMON])
	_check("a single COMMON accumulator unlocks the 2x tier by itself",
		s2.mount.get_frame_multiplier_options(s2.grid, origin) == [1, 2])

	# --- 3: a single UNCOMMON accumulator (needs 2) falls back to COMMON's --
	# tier via cumulative counting, not to nothing.
	var s3 = _make_grid_with_accumulators(origin, [HexTile.Rarity.UNCOMMON])
	_check("a lone UNCOMMON accumulator (short of its own need-2) still grants COMMON's 2x tier, not nothing",
		s3.mount.get_frame_multiplier_options(s3.grid, origin) == [1, 2])

	# --- 4: two UNCOMMON accumulators meet UNCOMMON's own need-2 ------------
	var s4 = _make_grid_with_accumulators(origin, [HexTile.Rarity.UNCOMMON, HexTile.Rarity.UNCOMMON])
	_check("two UNCOMMON accumulators meet UNCOMMON's need-2, unlocking 4x",
		s4.mount.get_frame_multiplier_options(s4.grid, origin) == [1, 2, 4])

	# --- 5: two RARE accumulators meet RARE's need-2, unlocking 16x ---------
	var s5 = _make_grid_with_accumulators(origin, [HexTile.Rarity.RARE, HexTile.Rarity.RARE])
	_check("two RARE accumulators meet RARE's need-2, unlocking 16x",
		s5.mount.get_frame_multiplier_options(s5.grid, origin) == [1, 2, 4, 16])

	# --- 6: two LEGENDARY don't meet their own need-3, but DO satisfy -------
	# RARE's need-2 cumulatively (LEGENDARY >= RARE).
	var s6 = _make_grid_with_accumulators(origin, [HexTile.Rarity.LEGENDARY, HexTile.Rarity.LEGENDARY])
	_check("two LEGENDARY accumulators (short of their own need-3) still satisfy RARE's need-2 cumulatively",
		s6.mount.get_frame_multiplier_options(s6.grid, origin) == [1, 2, 4, 16])

	# --- 7: three LEGENDARY meet LEGENDARY's own need-3, unlocking 32x ------
	var s7 = _make_grid_with_accumulators(origin, [HexTile.Rarity.LEGENDARY, HexTile.Rarity.LEGENDARY, HexTile.Rarity.LEGENDARY])
	_check("three LEGENDARY accumulators meet LEGENDARY's own need-3, unlocking 32x",
		s7.mount.get_frame_multiplier_options(s7.grid, origin) == [1, 2, 4, 16, 32])

	# --- 8: a single MYTHIC accumulator (need 1) unlocks the FULL powers-of-
	# two ladder up to 256, not just 256 as one bare option.
	var s8 = _make_grid_with_accumulators(origin, [HexTile.Rarity.MYTHIC])
	_check("a single MYTHIC accumulator unlocks every power of two up to 256",
		s8.mount.get_frame_multiplier_options(s8.grid, origin) == [1, 2, 4, 8, 16, 32, 64, 128, 256])

	# --- 9: a mix (1 MYTHIC + 2 RARE) still reaches the Mythic tier ---------
	var s9 = _make_grid_with_accumulators(origin, [HexTile.Rarity.MYTHIC, HexTile.Rarity.RARE, HexTile.Rarity.RARE])
	_check("a mix including one MYTHIC accumulator reaches the full 256 ladder regardless of what else is present",
		s9.mount.get_frame_multiplier_options(s9.grid, origin) == [1, 2, 4, 8, 16, 32, 64, 128, 256])

	# --- 10: cycling works on ANY mount rarity now (old Mythic-mount-only ---
	# gate is gone), walks the full dynamic list exactly once each, wraps.
	var s10 = _make_grid_with_accumulators(origin, [HexTile.Rarity.RARE, HexTile.Rarity.RARE])
	s10.mount.rarity = HexTile.Rarity.COMMON # a COMMON mount, not Mythic
	var full_options = s10.mount.get_frame_multiplier_options(s10.grid, origin)
	var seen_set = {}
	for i in range(full_options.size()):
		seen_set[s10.mount.mythic_frame_multiplier] = true
		s10.mount.cycle_mythic_frame_multiplier(s10.grid, origin)
	_check("cycling on a COMMON-rarity mount (gated by adjacent Accumulators, not the mount's own rarity) visits every option exactly once",
		seen_set.size() == full_options.size())
	_check("cycling wraps back to the start after a full cycle",
		s10.mount.mythic_frame_multiplier == full_options[0])

	var n0 = origin.neighbor(0)
	var n1 = origin.neighbor(1)

	# --- 11: Chopper split-factor aggregation ---------------------------------
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

	# --- 12: end-to-end numeric split correctness -----------------------------
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
		print("PASS: rarity+count Accumulator capacity ladder (cumulative counting, mount-rarity-independent) and Chopper split-factor aggregation both correct")
	get_tree().quit(0 if failures == 0 else 1)
