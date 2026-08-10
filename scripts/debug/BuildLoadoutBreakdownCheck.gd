extends Node

# Regression check for build_loadout_for_role's own internal perf
# breakdown (2026-08-10 playtest, wave 172, 3fps: AutoEquipSolver's own
# solve() breakdown read all 0ms while Mech._perf_build_loadout_usec read
# 1716ms - the cost isn't inside solve() at all, it's somewhere else in
# build_loadout_for_role that was never separately measured before).
# Confirms the four new counters (_perf_stock_lookup_usec/_perf_stock_
# replay_usec/_perf_fresh_inventory_usec/_perf_post_solve_serialize_usec)
# actually fire on the right path: a stock-build MISS goes through fresh_
# inventory/post_solve_serialize (never stock_replay), and a stock-build
# HIT goes through stock_replay (never fresh_inventory/post_solve_
# serialize) - stock_lookup fires on both, it's unconditional.
#
# SAFETY: deliberately does NOT construct a real SquadDirector.gd anywhere
# in this file. This exact test overwrote the user's real learned_state.
# json (2026-08-10 - templates/solver_profiles from a wave-172 playthrough
# replaced with near-empty data, no recovery) the first time it was
# written, because a real SquadDirector added to the tree with empty
# arrays got its _exit_tree()/save-flush triggered on cleanup. Never do
# that again - see feedback_headless_test_userdata_safety memory / this
# session's own established FakeDirector pattern (StockBuildPromotionGate
# Check.gd, SubArchetypeSlotCheck.gd). Mech._get_stock_build_evolution()
# only needs `get_tree().current_scene.world.get_node("SquadDirector").
# stock_build_evolution` to resolve - a bare Node exposing exactly that
# property satisfies it without ever instantiating the real class.

const MechScript = preload("res://scripts/entities/Mech.gd")
const StockBuildEvolutionScript = preload("res://scripts/ai/StockBuildEvolution.gd")

class FakeDirector:
	var stock_builds: Array = []
	func request_save_learned_state():
		pass # no-op - never touches user:// (see this file's own header)

class FakeSquadDirectorNode extends Node:
	var stock_build_evolution

var world: Node = null # duck-typed "main.world" - see Mech._get_stock_build_evolution()

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _reset_counters():
	MechScript._perf_stock_lookup_usec = 0
	MechScript._perf_stock_replay_usec = 0
	MechScript._perf_fresh_inventory_usec = 0
	MechScript._perf_post_solve_serialize_usec = 0

func _spawn_bot(template_name: String, role: String, rarity: int, slot: int) -> Node:
	var bot = MechScript.new()
	bot.is_player = false
	bot.combat_role = role
	bot.base_rarity = rarity
	bot.spawn_template_name = template_name
	bot.sub_archetype_slot = slot
	add_child(bot)
	return bot

func _ready():
	world = Node.new()
	add_child(world)
	var fake_director_node = FakeSquadDirectorNode.new()
	fake_director_node.name = "SquadDirector"
	fake_director_node.stock_build_evolution = StockBuildEvolutionScript.new(FakeDirector.new())
	world.add_child(fake_director_node)

	# --- 1: first spawn for a brand-new (template, role, rarity, slot) - no
	# stock build exists yet, so this MUST take the fresh-solve path.
	_reset_counters()
	var bot_a = _spawn_bot("Escort", "brawler", HexTile.Rarity.RARE, 0)
	_check("stock_lookup fires even on a first-ever spawn (the lookup itself always runs)",
		MechScript._perf_stock_lookup_usec > 0)
	_check("a stock-build miss takes the fresh_inventory path",
		MechScript._perf_fresh_inventory_usec > 0)
	_check("a stock-build miss takes the post_solve_serialize path (establishing the new stock build)",
		MechScript._perf_post_solve_serialize_usec > 0)
	_check("a stock-build miss never touches stock_replay",
		MechScript._perf_stock_replay_usec == 0)
	bot_a.queue_free()

	# --- 2: a stock build now exists for (Escort, brawler, RARE, slot 0) -
	# repeated spawns should mostly take the stock-replay path (deviation
	# testing is a real, intentional ~17.5% random roll - should_test_
	# deviation() - so this loops until it actually lands on the replay
	# path at least once rather than depending on a single lucky roll).
	var saw_stock_replay = false
	for i in range(20):
		_reset_counters()
		var bot_b = _spawn_bot("Escort", "brawler", HexTile.Rarity.RARE, 0)
		if MechScript._perf_stock_replay_usec > 0:
			saw_stock_replay = true
			_check("a stock-build hit never touches fresh_inventory",
				MechScript._perf_fresh_inventory_usec == 0)
			_check("a stock-build hit never touches post_solve_serialize (unless it also rolled a deviation test)",
				MechScript._perf_post_solve_serialize_usec == 0)
			bot_b.queue_free()
			break
		bot_b.queue_free()
	_check("across repeated spawns of an established (template, role, rarity, slot), the stock_replay path fires at least once",
		saw_stock_replay)

	if failures == 0:
		print("PASS: build_loadout_for_role's stock_lookup/stock_replay/fresh_inventory/post_solve_serialize counters each fire on exactly the right path")
	get_tree().quit(0 if failures == 0 else 1)
