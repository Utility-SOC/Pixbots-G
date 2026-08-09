extends Node

# Regression harness for the accumulator-scaled Mythic firing threshold
# (design request: "I want the capacity options for the weapons mount to
# directly attenuate upward when accumulators are equipped, allowing for
# shots much larger than 12,000,000 energy, and with reverse accumulators
# smaller than 300,000"). Reuses the exact same adjacency scan the
# accumulator bank-charge system already relies on
# (Mech._get_adjacent_accumulator_bonus/_get_adjacent_reverse_accumulator_
# discount, made static so WeaponMountTile can call them with no live Mech
# instance needed).

const WeaponMountTileScript = preload("res://scripts/tiles/WeaponMountTile.gd")
const AccumulatorTileScript = preload("res://scripts/tiles/AccumulatorTile.gd")
const ReverseAccumulatorTileScript = preload("res://scripts/tiles/ReverseAccumulatorTile.gd")
const HexGridComponentScript = preload("res://scripts/core/HexGridComponent.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var origin = HexCoord.new(0, 0)
	var neighbor_coord = origin.neighbor(0)

	# --- No accumulators adjacent: base 5-option list, unchanged ---
	var grid_a = HexGridComponentScript.new()
	var mount_a = WeaponMountTileScript.new()
	grid_a.add_tile(origin, mount_a)
	var options_a = mount_a.get_threshold_options(grid_a, origin)
	_check("with nothing adjacent, options match the base 5-entry list exactly",
		options_a == [0, 300000, 600000, 900000, 1200000])

	# --- One Mythic Accumulator adjacent: ceiling extends well past 12M ---
	var grid_b = HexGridComponentScript.new()
	var mount_b = WeaponMountTileScript.new()
	grid_b.add_tile(origin, mount_b)
	var acc = AccumulatorTileScript.new()
	acc.rarity = HexTile.Rarity.MYTHIC
	grid_b.add_tile(neighbor_coord, acc)
	var options_b = mount_b.get_threshold_options(grid_b, origin)
	_check("an adjacent Mythic Accumulator adds new, higher tiers beyond the base 5",
		options_b.size() > 5)
	_check("the base tiers are still all present (compose, don't replace)",
		options_b.size() >= 5 and options_b.slice(0, 5) == [0, 300000, 600000, 900000, 1200000])
	var max_b = options_b.max()
	_check("the highest reachable threshold clears 12,000,000 with real Accumulator investment (got %d)" % max_b,
		max_b > 12000000)

	# --- Two Mythic Accumulators stacked: ceiling goes even higher ---
	var grid_c = HexGridComponentScript.new()
	var mount_c = WeaponMountTileScript.new()
	grid_c.add_tile(origin, mount_c)
	var acc1 = AccumulatorTileScript.new()
	acc1.rarity = HexTile.Rarity.MYTHIC
	grid_c.add_tile(origin.neighbor(0), acc1)
	var acc2 = AccumulatorTileScript.new()
	acc2.rarity = HexTile.Rarity.MYTHIC
	grid_c.add_tile(origin.neighbor(1), acc2)
	var options_c = mount_c.get_threshold_options(grid_c, origin)
	_check("stacking a second adjacent Accumulator pushes the ceiling higher still (%d > %d)" % [options_c.max(), max_b],
		options_c.max() > max_b)

	# --- One Reverse Accumulator adjacent: floor extends below 300k ---
	var grid_d = HexGridComponentScript.new()
	var mount_d = WeaponMountTileScript.new()
	grid_d.add_tile(origin, mount_d)
	var rev = ReverseAccumulatorTileScript.new()
	rev.rarity = HexTile.Rarity.MYTHIC
	grid_d.add_tile(neighbor_coord, rev)
	var options_d = mount_d.get_threshold_options(grid_d, origin)
	_check("an adjacent Reverse Accumulator adds new, lower non-zero tiers",
		options_d.size() > 5)
	var non_zero = options_d.filter(func(v): return v > 0)
	_check("the lowest non-zero threshold drops below 300,000 (got %d)" % non_zero.min(),
		non_zero.min() < 300000)
	_check("the 0 (disabled/auto-fire) option is still present and untouched",
		options_d.has(0))
	_check("no reverse-scaled tier ever collapses to 0 or negative (floored well above zero)",
		non_zero.min() >= 1000)

	# --- cycle_mythic_firing_threshold() actually walks the DYNAMIC list ---
	var grid_e = HexGridComponentScript.new()
	var mount_e = WeaponMountTileScript.new()
	grid_e.add_tile(origin, mount_e)
	var acc_e = AccumulatorTileScript.new()
	acc_e.rarity = HexTile.Rarity.MYTHIC
	grid_e.add_tile(neighbor_coord, acc_e)
	var full_options = mount_e.get_threshold_options(grid_e, origin)
	var seen = []
	for i in range(full_options.size()):
		seen.append(mount_e.mythic_firing_threshold)
		mount_e.cycle_mythic_firing_threshold(grid_e, origin)
	var seen_set = {}
	for v in seen:
		seen_set[v] = true
	_check("every visited value is unique and matches the computed options list",
		seen_set.size() == full_options.size())
	_check("cycling wraps back to the start after a full cycle",
		mount_e.mythic_firing_threshold == full_options[0])

	if failures == 0:
		print("PASS: Weapon Mount firing-threshold options correctly scale up with adjacent Accumulators and down with adjacent Reverse Accumulators, composing with (not replacing) the base 5-tier list")
	get_tree().quit(0 if failures == 0 else 1)
