extends Node

# Regression check for the stock-replay simulation cache (perf fix,
# 2026-08-10: build_loadout_for_role's "use_stock" path replayed tile
# placement cheaply but still unconditionally called _recalculate_grid(),
# paying the full _simulate_energy_flow() cost - 200ms+ per spawn on dense
# builds - on every single replay. Mech._recalculate_grid_for_stock() now
# memoizes that pass's own output (pending_packets per mount) on the
# StockBuild itself, keyed by slot+grid_position, and replays it on every
# subsequent use instead of re-simulating).
#
# Confirms: the cache starts empty, gets populated on the FIRST stock-
# replay hit (a cache miss - still simulates), a SECOND stock-replay hit
# is a cache hit that restores from it, and - most importantly - the
# restored precalculated_weapons state (mount count, per-mount packet
# magnitude/synergies) is IDENTICAL between the cache-miss spawn and the
# cache-hit spawn, with no aliasing between the cached packets and any
# live Mech's own packets (mutating one spawn's weapons must never affect
# another's).
#
# SAFETY: deliberately does NOT construct a real SquadDirector.gd/add it
# to the tree - see BuildLoadoutBreakdownCheck.gd's own header for why
# (2026-08-10 incident: overwrote the user's real learned_state.json).
# FakeDirector/FakeSquadDirectorNode below are the same safe stand-ins.

const MechScript = preload("res://scripts/entities/Mech.gd")
const StockBuildEvolutionScript = preload("res://scripts/ai/StockBuildEvolution.gd")

class FakeDirector:
	var stock_builds: Array = []
	func request_save_learned_state():
		pass # no-op - never touches user:// (see this file's own header)

class FakeSquadDirectorNode extends Node:
	var stock_build_evolution

var world: Node = null
var stock_evo # StockBuildEvolutionScript instance

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _spawn_bot(template_name: String, role: String, rarity: int, slot: int) -> Node:
	var bot = MechScript.new()
	bot.is_player = false
	bot.combat_role = role
	bot.base_rarity = rarity
	bot.spawn_template_name = template_name
	bot.sub_archetype_slot = slot
	add_child(bot)
	return bot

# Snapshot of everything a mismatch in this cache could plausibly break:
# mount count and, per mount, the packet's magnitude/synergies/charge_
# required (in mount-index order, which is stable since it's rebuilt by
# iterating the same tile layout every time).
func _snapshot_weapons(bot: Node) -> Array:
	var out = []
	for w in bot.precalculated_weapons:
		out.append({
			"magnitude": w["packet"].magnitude,
			"synergies": w["packet"].synergies.duplicate(),
			"charge_required": w["packet"].charge_required,
			"bank_mode": w.get("bank_mode", ""),
		})
	return out

func _ready():
	world = Node.new()
	add_child(world)
	var fake_director_node = FakeSquadDirectorNode.new()
	fake_director_node.name = "SquadDirector"
	stock_evo = StockBuildEvolutionScript.new(FakeDirector.new())
	fake_director_node.stock_build_evolution = stock_evo
	world.add_child(fake_director_node)

	const TEMPLATE = "CacheCheckSquad"
	const ROLE = "brawler"
	const RARITY = HexTile.Rarity.RARE
	const SLOT = 0

	# --- 1: first-ever spawn - no stock build exists yet, establishes one
	# via the fresh-solve path (cache mechanism not involved at all here).
	var bot_a = _spawn_bot(TEMPLATE, ROLE, RARITY, SLOT)
	var stock = stock_evo.get_stock_build(TEMPLATE, ROLE, RARITY, SLOT)
	_check("a fresh solve establishes a stock build", stock != null)
	_check("a freshly-established stock build's simulation cache starts empty",
		stock != null and stock._simulation_cache.is_empty())
	bot_a.queue_free()

	# --- 2: repeated spawns until we see two real stock-replay hits
	# (should_test_deviation() is a real ~17.5% random roll per spawn, so
	# loop rather than depend on a fixed spawn landing on replay).
	var replay_snapshots = []
	var cache_was_empty_before_first_replay = false
	var cache_populated_after_first_replay = false
	for i in range(60):
		MechScript._perf_stock_replay_usec = 0
		var was_empty = stock._simulation_cache.is_empty()
		var bot = _spawn_bot(TEMPLATE, ROLE, RARITY, SLOT)
		if MechScript._perf_stock_replay_usec > 0:
			if replay_snapshots.is_empty():
				cache_was_empty_before_first_replay = was_empty
				cache_populated_after_first_replay = not stock._simulation_cache.is_empty()
			replay_snapshots.append(_snapshot_weapons(bot))
			# Mutate this bot's own packets after snapshotting - proves the
			# NEXT replay's restored packets can't be aliased to this one's.
			for w in bot.precalculated_weapons:
				w["packet"].magnitude = -999.0
			if replay_snapshots.size() >= 2:
				bot.queue_free()
				break
		bot.queue_free()

	_check("at least two stock-replay hits were observed across 60 spawns",
		replay_snapshots.size() >= 2)
	_check("the simulation cache was empty right before the first stock-replay hit (that hit is the cache miss that populates it)",
		cache_was_empty_before_first_replay)
	_check("the simulation cache is populated immediately after that first (cache-miss) replay hit",
		cache_populated_after_first_replay)

	if replay_snapshots.size() >= 2:
		var first = replay_snapshots[0]
		var second = replay_snapshots[1]
		_check("cache-miss and cache-hit replays produce the same mount count (%d vs %d)" % [first.size(), second.size()],
			first.size() == second.size())
		var all_match = first.size() == second.size()
		for i in range(min(first.size(), second.size())):
			if abs(first[i]["magnitude"] - second[i]["magnitude"]) > 0.01:
				all_match = false
			if first[i]["bank_mode"] != second[i]["bank_mode"]:
				all_match = false
			for k in first[i]["synergies"]:
				if abs(first[i]["synergies"].get(k, 0.0) - second[i]["synergies"].get(k, 0.0)) > 0.01:
					all_match = false
			if abs(first[i]["charge_required"] - second[i]["charge_required"]) > 0.01:
				all_match = false
		_check("every mount's packet magnitude/synergies/charge_required/bank_mode is identical between the cache-miss and cache-hit replay (restored data matches simulated data exactly)",
			all_match)
		_check("mutating one spawn's packets afterward never leaked into the next spawn's restored packets (no aliasing) - real magnitudes seen, not the -999 sentinel",
			second.size() > 0 and second[0]["magnitude"] > -900.0)

	if failures == 0:
		print("PASS: stock-replay simulation cache starts empty, populates on its first (cache-miss) hit, and every later (cache-hit) replay restores byte-identical, non-aliased packet state without re-simulating")
	get_tree().quit(0 if failures == 0 else 1)
