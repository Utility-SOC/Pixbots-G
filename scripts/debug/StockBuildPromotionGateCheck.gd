extends Node

# Regression check for StockBuildEvolution._flush()'s promotion gate (per
# the user: "anything that does better than the current best in X out of Y
# sessions gets promoted to the new best template"). Used to promote
# whichever single deviation in the tracked batch had the highest fitness,
# as long as it beat the current build's average even once - a lucky
# outlier could flip the champion. Now requires the deviation to have beaten
# the current build in at least PROMOTION_WIN_RATE (50%) of the tracked
# batch before it's trusted.
#
# Deliberately does NOT touch a real SquadDirector/add it to the tree -
# StockBuildEvolution only needs its director argument to duck-type
# `stock_builds` (Array) and `request_save_learned_state()` (Callable).
# A real SquadDirector's request_save_learned_state() eventually writes the
# REAL "learned_state" save file via _process()/_exit_tree() - a throwaway
# test must never risk that (see this session's own established headless-
# test-safety rule). FakeDirector below is a safe, real-save-free stand-in.

const StockBuildEvolutionScript = preload("res://scripts/ai/StockBuildEvolution.gd")
const StockBuildScript = preload("res://scripts/ai/StockBuild.gd")

class FakeDirector:
	var stock_builds: Array = []
	var save_requested: bool = false
	func request_save_learned_state():
		save_requested = true

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _make_champion(fitness: float, template_name: String = "T1", role: String = "brawler", rarity: int = HexTile.Rarity.COMMON):
	var b = StockBuildScript.new(template_name, role, rarity)
	b.times_used = 1
	b.total_fitness = fitness
	b.serialized_components = {"tag": "champion"}
	return b

func _ready():
	# --- 1: a batch where only a minority of trials beat the champion
	# (2 of 8) must NOT promote, even though the single best entry beat it.
	var fake1 = FakeDirector.new()
	var champion1 = _make_champion(100.0)
	fake1.stock_builds = [champion1]
	var evo1 = StockBuildEvolutionScript.new(fake1)
	var fitnesses_minority = [110.0, 120.0, 90.0, 80.0, 70.0, 60.0, 50.0, 40.0] # 2 of 8 beat 100
	for f in fitnesses_minority:
		evo1.record_deviation_result("T1", "brawler", HexTile.Rarity.COMMON, {"tag": "dev_%d" % int(f)}, f)
	var after1 = evo1.get_stock_build("T1", "brawler", HexTile.Rarity.COMMON)
	_check("a 2-of-8 minority win rate does NOT promote (champion unchanged)",
		after1 == champion1 and after1.serialized_components.get("tag") == "champion")
	_check("no save was requested when nothing promoted",
		not fake1.save_requested)

	# --- 2: a batch where a majority of trials beat the champion (5 of 8)
	# DOES promote, and picks the best of the winning entries.
	var fake2 = FakeDirector.new()
	var champion2 = _make_champion(100.0)
	fake2.stock_builds = [champion2]
	var evo2 = StockBuildEvolutionScript.new(fake2)
	var fitnesses_majority = [110.0, 150.0, 130.0, 120.0, 105.0, 90.0, 80.0, 70.0] # 5 of 8 beat 100, best=150
	for f in fitnesses_majority:
		evo2.record_deviation_result("T1", "brawler", HexTile.Rarity.COMMON, {"tag": "dev_%d" % int(f)}, f)
	var after2 = evo2.get_stock_build("T1", "brawler", HexTile.Rarity.COMMON)
	_check("a 5-of-8 majority win rate DOES promote",
		after2 != champion2)
	_check("promotion picks the single BEST winning entry (fitness 150), not just any winner",
		after2.serialized_components.get("tag") == "dev_150")
	_check("a real promotion requests a save",
		fake2.save_requested)

	# --- 3: no existing build for the key (current == null) - promotes the
	# best entry unconditionally once the batch flushes, no win-rate gate
	# needed since there's nothing to beat yet.
	var fake3 = FakeDirector.new()
	var evo3 = StockBuildEvolutionScript.new(fake3)
	var fitnesses_fresh = [10.0, 5.0, 20.0, 1.0, 15.0, 8.0, 12.0, 3.0] # best=20, all "win" trivially
	for f in fitnesses_fresh:
		evo3.record_deviation_result("T2", "sniper", HexTile.Rarity.RARE, {"tag": "fresh_%d" % int(f)}, f)
	var after3 = evo3.get_stock_build("T2", "sniper", HexTile.Rarity.RARE)
	_check("with no existing build, the batch's best entry is promoted unconditionally",
		after3 != null and after3.serialized_components.get("tag") == "fresh_20")

	# --- 4: partial batch flushed early (Garage-open checkpoint, fewer than
	# MAX_TRACKED_DEVIATIONS accumulated) applies the SAME proportional
	# win-rate gate, not a fixed absolute count.
	var fake4 = FakeDirector.new()
	var champion4 = _make_champion(100.0, "T3", "scout", HexTile.Rarity.COMMON)
	fake4.stock_builds = [champion4]
	var evo4 = StockBuildEvolutionScript.new(fake4)
	# Only 1 of 4 beats the champion - ceil(4 * 0.5) = 2 required, so this
	# should NOT promote on an early flush.
	for f in [110.0, 90.0, 80.0, 70.0]:
		evo4.record_deviation_result("T3", "scout", HexTile.Rarity.COMMON, {"tag": "partial_%d" % int(f)}, f)
	evo4.flush_all_pending()
	var after4 = evo4.get_stock_build("T3", "scout", HexTile.Rarity.COMMON)
	_check("an early partial-batch flush (1 of 4 wins) still respects the proportional win-rate gate",
		after4 == champion4)

	if failures == 0:
		print("PASS: StockBuildEvolution promotion requires a consistent win rate across the tracked batch, not a single lucky outlier, and never touches real save state")
	get_tree().quit(0 if failures == 0 else 1)
