class_name ChipSplicer
extends RefCounted

# Chip Splicing's merge algorithm - pure, stateless (every func is static,
# no instance state, no Node/scene-tree coupling) so it's independently
# testable and reusable from both the Garage UI (TileActionMenu.gd) and
# anywhere else a splice might someday be needed. Mirrors the shape of a
# small pure-math helper rather than a composed-RefCounted-with-state
# helper like BossEvolution.gd, since there's no owning object here.
#
# A chip is {"traits": Array[{"stat": String, "value": float}]}. A plain
# chip has exactly 1 trait; a Corrupted (spliced) chip has 2+, unbounded.
#
# Two-tier mechanic (confirmed directly with the user across several
# rounds - see the plan at
# C:\Users\Utility\.claude\plans\effervescent-drifting-kazoo.md for the
# full design conversation):
#
#   Tier 1 (first splice): exactly two PLAIN chips with DIFFERENT stats.
#   No match required. Both source stats get BOOSTED beyond their
#   original values, plus one randomly-rolled NEGATIVE trait on a stat
#   neither source used. Two same-stat plain chips do NOT go through
#   Tier 1 - they fall through to Tier 2 instead (see classify_splice).
#
#   Tier 2 (re-splice): merging a Corrupted chip with anything else
#   (plain or itself Corrupted). REQUIRES at least one shared stat to be
#   eligible at all - a hard eligibility gate, not just a bonus
#   interaction. Every stat in the union of both chips' traits: appears
#   on only one side -> carried over UNCHANGED; appears on both ->
#   summed PURELY ALGEBRAICALLY, no boost (this is the one case that
#   never stacks a multiplier - confirmed explicitly). Trait count is
#   UNBOUNDED - no cap, no eviction of the weakest trait.

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")

const SPLICE_BOOST_MULT = 1.25       # Tier 1: each source trait's bonus multiplied by this
const NEG_TRAIT_MIN_MAG = 0.05       # Tier 1 rolled negative trait magnitude, -5%..
const NEG_TRAIT_MAX_MAG = 0.20       #                                        ..-20%

static func _round2(x: float) -> float:
	return round(x * 100.0) / 100.0

static func _stat_names(chip: Dictionary) -> Array:
	var out = []
	for t in chip.get("traits", []):
		out.append(str(t["stat"]))
	return out

# "tier1" | "tier2" | "invalid". Tier1 iff both chips are single-trait AND
# carry different stats. Tier2 iff the union of stat names has ANY
# overlap - this single check also correctly implements "same-stat plain
# chips fall through to Tier 2": they fail Tier1's "different stats"
# clause, then trivially satisfy Tier2's overlap requirement (their one
# shared stat). No overlap at all -> invalid.
static func classify_splice(chip_a: Dictionary, chip_b: Dictionary) -> String:
	var traits_a = chip_a.get("traits", [])
	var traits_b = chip_b.get("traits", [])
	if traits_a.is_empty() or traits_b.is_empty():
		return "invalid"
	if traits_a.size() == 1 and traits_b.size() == 1 and str(traits_a[0]["stat"]) != str(traits_b[0]["stat"]):
		return "tier1"
	var stats_a = {}
	for s in _stat_names(chip_a):
		stats_a[s] = true
	for s in _stat_names(chip_b):
		if stats_a.has(s):
			return "tier2"
	return "invalid"

# Both source chips must be single-trait with different stats (classify_
# splice's Tier1 precondition) - not re-checked here, the caller
# (splice_chips) already gated on it.
static func splice_tier1(chip_a: Dictionary, chip_b: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var trait_a = chip_a["traits"][0]
	var trait_b = chip_b["traits"][0]
	var stat_a = str(trait_a["stat"])
	var stat_b = str(trait_b["stat"])
	var boosted_a = 1.0 + (float(trait_a["value"]) - 1.0) * SPLICE_BOOST_MULT
	var boosted_b = 1.0 + (float(trait_b["value"]) - 1.0) * SPLICE_BOOST_MULT

	var pool = []
	for s in ComponentEquipmentScript.CHIP_STAT_POOL:
		if s != stat_a and s != stat_b:
			pool.append(s)
	var neg_stat = pool[rng.randi() % pool.size()]
	var neg_mag = rng.randf_range(NEG_TRAIT_MIN_MAG, NEG_TRAIT_MAX_MAG)

	return {"traits": [
		{"stat": stat_a, "value": _round2(boosted_a)},
		{"stat": stat_b, "value": _round2(boosted_b)},
		{"stat": neg_stat, "value": _round2(1.0 - neg_mag)},
	]}

# At least one shared stat required (classify_splice's Tier2 precondition,
# not re-checked here). Union-sum gives "unmatched carries over unchanged"
# for free - a stat touched by only one side just gets that side's own
# bonus back untouched, no separate branch needed. A stat whose net bonus
# rounds to ~0.00 is dropped entirely - no dead zero-value entries.
static func splice_tier2(chip_a: Dictionary, chip_b: Dictionary) -> Dictionary:
	var bonus_by_stat: Dictionary = {}
	for t in chip_a["traits"] + chip_b["traits"]:
		var stat = str(t["stat"])
		bonus_by_stat[stat] = bonus_by_stat.get(stat, 0.0) + (float(t["value"]) - 1.0)

	var result_traits = []
	for stat in bonus_by_stat:
		var bonus = _round2(bonus_by_stat[stat])
		if abs(bonus) < 0.005: # rounds to 0.00 at hundredths -> vanishes
			continue
		result_traits.append({"stat": stat, "value": 1.0 + bonus})
	return {"traits": result_traits}

# Public entry point. Returns {} (empty dict = failure, same convention as
# ComponentEquipment.unequip_chip()) if the splice is ineligible OR if a
# Tier 2 splice fully cancels out to zero resulting traits - the caller
# must NOT consume either input chip on failure. A full-cancel destroying
# both real chips for nothing felt like the wrong default; rejecting the
# splice outright (nothing lost, try a different pairing) is the safer
# call - flag to the user if the alternative (consume both anyway) is
# preferred instead.
static func splice_chips(chip_a: Dictionary, chip_b: Dictionary, rng: RandomNumberGenerator = null) -> Dictionary:
	var tier = classify_splice(chip_a, chip_b)
	if tier == "invalid":
		return {}
	if tier == "tier1":
		var real_rng = rng if rng else RandomNumberGenerator.new()
		if not rng:
			real_rng.randomize()
		return splice_tier1(chip_a, chip_b, real_rng)
	# tier2
	var result = splice_tier2(chip_a, chip_b)
	if result["traits"].is_empty():
		return {}
	return result
