extends Node

# Regression harness for ReverseAccumulatorTile (per the user: "a hex tile
# that is like, a reverse accumulator that reduces an adjacent weapon
# mount's required energy to fire" - the deliberate inverse of Accumulator,
# meant to offset the new RAPID_FIRE_CHARGE_MULT cost on normal fire).
# Verifies:
#   1. A single adjacent Reverse Accumulator discounts Mech._get_adjacent_
#      reverse_accumulator_discount()'s result by its own get_charge_discount().
#   2. Multiple adjacent Reverse Accumulators stack additively.
#   3. Only tiles actually touching the coord count - a non-adjacent one
#      contributes nothing, same as Accumulator's own adjacency scan.
#   4. get_charge_discount() scales with rarity (_get_power_multiplier),
#      same as Accumulator's get_bank_charge/get_bank_amplify.
#   5. RAPID_FIRE_CHARGE_MULT genuinely exists as a real constant on Mech
#      and is > 1.0 (a real cost, not a no-op).

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const ReverseAccumulatorTileScript = preload("res://scripts/tiles/ReverseAccumulatorTile.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var comp = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.RARE)
	var hexes: Array[HexCoord] = [
		HexCoord.new(0, 0), # the "mount" coord - not a real Weapon Mount, just a probe point
		HexCoord.new(1, 0), HexCoord.new(-1, 0), # two adjacent slots
		HexCoord.new(3, 0), # far away, NOT adjacent
	]
	comp.valid_hexes = hexes
	comp._rebuild_valid_hex_set()

	var mech = MechScript.new()
	add_child(mech)
	mech.set_physics_process(false)

	# --- 1/3: single adjacent tile contributes, a distant one doesn't ------
	var rev_a = ReverseAccumulatorTileScript.new()
	rev_a.rarity = HexTile.Rarity.COMMON
	comp.hex_grid.add_tile(HexCoord.new(1, 0), rev_a)
	var rev_far = ReverseAccumulatorTileScript.new()
	comp.hex_grid.add_tile(HexCoord.new(3, 0), rev_far)

	var discount_one = mech._get_adjacent_reverse_accumulator_discount(comp.hex_grid, HexCoord.new(0, 0))
	_check("one adjacent Reverse Accumulator contributes its own get_charge_discount()",
		abs(discount_one - rev_a.get_charge_discount()) < 0.001)
	_check("a non-adjacent Reverse Accumulator (3 hexes away) contributes nothing",
		discount_one < rev_a.get_charge_discount() + rev_far.get_charge_discount() - 0.001)

	# --- 2: a second adjacent tile stacks additively ------------------------
	var rev_b = ReverseAccumulatorTileScript.new()
	rev_b.rarity = HexTile.Rarity.COMMON
	comp.hex_grid.add_tile(HexCoord.new(-1, 0), rev_b)
	var discount_two = mech._get_adjacent_reverse_accumulator_discount(comp.hex_grid, HexCoord.new(0, 0))
	_check("two adjacent Reverse Accumulators stack additively (got %.4f, expect %.4f)" % [discount_two, rev_a.get_charge_discount() + rev_b.get_charge_discount()],
		abs(discount_two - (rev_a.get_charge_discount() + rev_b.get_charge_discount())) < 0.001)

	# --- 4: discount scales with rarity, same shape as Accumulator's bonuses ---
	var rev_mythic = ReverseAccumulatorTileScript.new()
	rev_mythic.rarity = HexTile.Rarity.MYTHIC
	var rev_common = ReverseAccumulatorTileScript.new()
	rev_common.rarity = HexTile.Rarity.COMMON
	_check("higher rarity gives a bigger per-tile discount",
		rev_mythic.get_charge_discount() > rev_common.get_charge_discount())

	# --- 5: the rapid-fire cost constant is real and actually a cost -------
	_check("Mech.RAPID_FIRE_CHARGE_MULT exists and is a genuine cost (> 1.0)",
		MechScript.RAPID_FIRE_CHARGE_MULT > 1.0)

	if failures == 0:
		print("PASS: Reverse Accumulator adjacency discount stacks correctly, scales with rarity, and Mech's rapid-fire charge cost is real")
	get_tree().quit(0 if failures == 0 else 1)
