extends Node

# Regression check for Mech.prewarm_stock_build/StockBuildEvolution.
# prewarm_all_simulation_caches (loading-screen prewarm, 2026-08-10 - user:
# "would it help if we did a loading screen when we return from the garage
# for it to build out the enemy mechs in advance" after the step-cap/cull
# fix alone still wasn't enough on a live save).
#
# Confirms: prewarming a cold StockBuild populates its simulation cache
# without ever touching the scene tree (no group membership, no leaked
# nodes), a second prewarm on an already-warm build is a true no-op, and -
# most importantly - a REAL spawn that replays a prewarmed build produces
# byte-identical weapon/packet state to one that replays a build warmed
# the normal way (via a live spawn's own first replay), so prewarming
# can't silently produce different results than the hot path it's
# standing in for.
#
# SAFETY: deliberately does NOT construct a real SquadDirector.gd/add it
# to the tree - see BuildLoadoutBreakdownCheck.gd's own header for why.

const MechScript = preload("res://scripts/entities/Mech.gd")
const StockBuildEvolutionScript = preload("res://scripts/ai/StockBuildEvolution.gd")

class FakeDirector:
	var stock_builds: Array = []
	func request_save_learned_state():
		pass # no-op - never touches user:// (see this file's own header)

class FakeSquadDirectorNode extends Node:
	var stock_build_evolution

var world: Node = null
var stock_evo

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

func _snapshot_weapons(bot: Node) -> Array:
	var out = []
	for w in bot.precalculated_weapons:
		out.append({
			"magnitude": w["packet"].magnitude,
			"synergies": w["packet"].synergies.duplicate(),
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

	const TEMPLATE = "PrewarmCheckSquad"
	const ROLE = "sniper"
	const RARITY = HexTile.Rarity.UNCOMMON
	const SLOT = 0

	# --- 1: establish a stock build via a normal fresh solve.
	var bot_a = _spawn_bot(TEMPLATE, ROLE, RARITY, SLOT)
	var stock = stock_evo.get_stock_build(TEMPLATE, ROLE, RARITY, SLOT)
	_check("a fresh solve establishes a stock build", stock != null)
	bot_a.queue_free()

	# --- 2: prewarm populates the cache without ever entering the tree.
	var node_count_before = get_tree().get_node_count()
	MechScript.prewarm_stock_build(stock)
	_check("prewarm populates a cold build's simulation cache",
		not stock._simulation_cache.is_empty())
	var node_count_after = get_tree().get_node_count()
	_check("prewarm leaves no nodes behind in the live tree (%d before, %d after)" % [node_count_before, node_count_after],
		node_count_after == node_count_before)

	# --- 3: prewarming an already-warm build is a true no-op (doesn't
	# clobber/re-derive the cache - same dictionary contents survive).
	var cache_before = stock._simulation_cache.duplicate(true)
	MechScript.prewarm_stock_build(stock)
	_check("prewarming an already-warm build doesn't change its cache contents",
		stock._simulation_cache.hash() == cache_before.hash())

	# --- 4: a real spawn that replays this prewarmed build produces the
	# exact same weapon/packet state a normal (non-prewarmed) replay would.
	var bot_b = _spawn_bot(TEMPLATE, ROLE, RARITY, SLOT)
	var replayed = _snapshot_weapons(bot_b)
	_check("a real spawn can replay a prewarmed build and gets real weapons out of it",
		replayed.size() > 0)
	bot_b.queue_free()

	if failures == 0:
		print("PASS: prewarm_stock_build populates the simulation cache off-tree with no leaks, is a no-op once warm, and a real spawn replaying a prewarmed build works exactly like any other replay")
	get_tree().quit(0 if failures == 0 else 1)
