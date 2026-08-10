extends Node

# The headless AutoEquipSolver perf baseline Status.md's "Evolving stock
# builds + wave archetype shaping (2026-08-05)" entry explicitly flagged as
# missing ("worth adding one before this gets touched again"). Prompted by
# live playtest evidence (9 screenshots, waves 160-166) showing Mech.
# build_loadout_for_role costing 1300-2700ms/sec whenever enemies spawn -
# the single biggest confirmed perf problem this session. Measures
# AutoEquipSolver.solve() directly, at a realistic MYTHIC-rarity/large-
# inventory scale (matching what TileRarityScalingCheck.gd's own output
# showed a real Mythic torso assembling - over 100 Directional Conduits
# alone), same-process multi-trial style as MechPhysicsCostDiagnostic.gd/
# ProjectileTargetingPerfCheck.gd.
#
# _topology_cache (the wrapping solve()'s own perf fix, see AutoEquipSolver.
# gd's header) is explicitly CLEARED before each trial - a real cache hit
# is fast by design and not what this is measuring; the live-game problem
# is that wave-160's rarity/template churn (see this session's own root-
# cause research) means a large share of real spawns never GET a cache
# hit, so "every trial is a cold _solve_impl call" is the faithful stress
# scenario, not an unrealistic worst case.

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const AutoEquipSolverScript = preload("res://scripts/core/AutoEquipSolver.gd")
const DirectionalConduitTileScript = preload("res://scripts/tiles/DirectionalConduitTile.gd")
const SplitterTileScript = preload("res://scripts/tiles/SplitterTile.gd")
const AmplifierTileScript = preload("res://scripts/tiles/AmplifierTile.gd")
const ReflectorTileScript = preload("res://scripts/tiles/ReflectorTile.gd")

const TRIALS = 8
# Roughly matches TileRarityScalingCheck.gd's own observed real-game scale
# for a Mythic torso's placed-tile composition (111 Directional Conduits,
# 5 Splitters, etc.) - large enough to make inventory-scan cost (if that's
# what dominates) show up clearly, not a token handful of tiles.
const INVENTORY_SIZE = 150

func _build_large_mythic_inventory() -> Array:
	var inventory: Array = []
	for i in range(int(INVENTORY_SIZE * 0.7)):
		var t = DirectionalConduitTileScript.new()
		t.rarity = HexTile.Rarity.MYTHIC
		inventory.append(t)
	for i in range(int(INVENTORY_SIZE * 0.1)):
		var t = SplitterTileScript.new()
		t.rarity = HexTile.Rarity.MYTHIC
		inventory.append(t)
	for i in range(int(INVENTORY_SIZE * 0.1)):
		var t = AmplifierTileScript.new()
		t.rarity = HexTile.Rarity.MYTHIC
		inventory.append(t)
	for i in range(inventory.size(), INVENTORY_SIZE):
		var t = ReflectorTileScript.new()
		t.rarity = HexTile.Rarity.MYTHIC
		inventory.append(t)
	return inventory

func _ready():
	var world = Node2D.new()
	add_child(world)

	print("--- AutoEquipSolver.solve() cost, MYTHIC torso, %d-tile inventory, %d trials (topology cache cleared before each) ---" % [INVENTORY_SIZE, TRIALS])

	var wall_samples: Array = []
	for t in range(TRIALS):
		var torso = ComponentEquipmentScript.create_starter_torso("brawler", HexTile.Rarity.MYTHIC)
		world.add_child(torso)
		var inventory = _build_large_mythic_inventory()

		AutoEquipSolverScript._topology_cache.clear()
		var solver = AutoEquipSolverScript.new()
		var t0 = Time.get_ticks_usec()
		solver.solve(torso, inventory)
		var elapsed_ms = (Time.get_ticks_usec() - t0) / 1000.0
		wall_samples.append(elapsed_ms)
		torso.queue_free()

	var wall_mean = 0.0
	for s in wall_samples:
		wall_mean += s
	wall_mean /= wall_samples.size()
	print("    wall-clock per solve() call: mean=%.3fms  samples=%s" % [wall_mean, wall_samples])

	var bfs_ms = AutoEquipSolverScript._perf_bfs_usec / 1000.0
	var lengthen_ms = AutoEquipSolverScript._perf_lengthen_path_usec / 1000.0
	var reattach_ms = AutoEquipSolverScript._perf_reattach_usec / 1000.0
	var scan_ms = AutoEquipSolverScript._perf_placement_scan_usec / 1000.0
	var cache_key_ms = AutoEquipSolverScript._perf_cache_key_usec / 1000.0
	var extract_plan_ms = AutoEquipSolverScript._perf_extract_plan_usec / 1000.0
	var accounted = bfs_ms + lengthen_ms + reattach_ms + scan_ms + cache_key_ms + extract_plan_ms
	var total_wall = 0.0
	for s in wall_samples:
		total_wall += s

	print("")
	print("=== Internal breakdown across all %d trials (total, not per-trial) ===" % TRIALS)
	print("cache_key (sorts+formats whole inventory, EVERY call incl. hits): %8.3fms  (%.1f%% of accounted)" % [cache_key_ms, 100.0 * cache_key_ms / max(0.001, accounted)])
	print("bfs (spanning tree from Core):        %8.3fms  (%.1f%% of accounted)" % [bfs_ms, 100.0 * bfs_ms / max(0.001, accounted)])
	print("lengthen_path (single-target restart-scan): %8.3fms  (%.1f%% of accounted)" % [lengthen_ms, 100.0 * lengthen_ms / max(0.001, accounted)])
	print("reattach (demote/_try_reattach reroute BFS): %8.3fms  (%.1f%% of accounted)" % [reattach_ms, 100.0 * reattach_ms / max(0.001, accounted)])
	print("placement_scan (inventory linear scans):     %8.3fms  (%.1f%% of accounted)" % [scan_ms, 100.0 * scan_ms / max(0.001, accounted)])
	print("extract_plan (re-walks grid to build cache entry, miss only):  %8.3fms  (%.1f%% of accounted)" % [extract_plan_ms, 100.0 * extract_plan_ms / max(0.001, accounted)])
	print("accounted total: %.3fms  vs total wall-clock: %.3fms  (%.1f%% accounted for)" % [accounted, total_wall, 100.0 * accounted / max(0.001, total_wall)])
	print("")

	var costs = {"cache_key": cache_key_ms, "bfs": bfs_ms, "lengthen_path": lengthen_ms, "reattach": reattach_ms, "placement_scan": scan_ms, "extract_plan": extract_plan_ms}
	var dominant = "cache_key"
	var dominant_ms = -1.0
	for k in costs:
		if costs[k] > dominant_ms:
			dominant = k
			dominant_ms = costs[k]
	print("VERDICT: '%s' is the dominant measured cost center (%.3fms of %.3fms accounted, %.1f%% of the wall-clock total) - this is where Step 2's fix should target." % [dominant, dominant_ms, accounted, 100.0 * dominant_ms / max(0.001, total_wall)])

	get_tree().quit(0)
