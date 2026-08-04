extends Node

# Phase 0 of the AI-tactics Rust-cutover plan (see
# C:\Users\Utility\.claude\plans\effervescent-drifting-kazoo.md) - produces
# the real numbers that decide whether Phase 3 (flow-field BFS rebuild port)
# is worth doing at all, and gives an honest baseline for Phase 4's boss
# retreat-raycast fan before any Rust port is attempted. MechPhysicsCostDiagnostic.gd
# can't produce either number itself (no MapGenerator in the tree, no is_boss
# mech spawned there), so this is the "small new diagnostic" the plan calls
# for instead.
#
# Same methodology as every other performance claim this session: direct
# Time.get_ticks_usec() bracketing of the real production call (not
# TIME_PHYSICS_PROCESS/wall-clock, which repeatedly proved unreliable),
# multiple trials with the first discarded as warmup.

const MapGeneratorScript = preload("res://scripts/core/MapGenerator.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")
const SolidGridBatcherScript = preload("res://scripts/core/SolidGridBatcher.gd")

const REBUILD_TRIALS = 8
const RETREAT_TRIALS = 200 # cheap call (5 raycasts) - needs more reps to get a stable mean

func _ready():
	await _measure_flow_field_rebuild()
	await _smoke_test_solid_grid_real_map()
	await _measure_boss_retreat_raycast()
	get_tree().quit(0)

# Phase 1 integration smoke test: SolidGridLosCheck.gd already covers the
# grid-march algorithm's correctness against a small hand-built synthetic
# wall - this instead confirms the batcher doesn't choke on a REAL generated
# map's real obstacle population/dimensions (400x250, thousands of obstacle
# cells, not a tidy 20x20 grid), and that rebuild cost at real scale is sane.
func _smoke_test_solid_grid_real_map():
	print("--- SolidGridBatcher integration smoke test (real Normal-map MapGenerator) ---")
	var map = MapGeneratorScript.new()
	map.map_type = "Normal"
	add_child(map)
	await get_tree().process_frame

	var batcher = SolidGridBatcherScript.new()
	batcher._ensure_rust()
	if not batcher._rasterizer:
		print("    SKIPPED: SolidGridRs not built (DLL missing)")
		map.queue_free()
		await get_tree().process_frame
		return

	var t0 = Time.get_ticks_usec()
	batcher._rebuild_grid(map)
	var rebuild_ms = (Time.get_ticks_usec() - t0) / 1000.0
	print("    real-map grid rebuild (%d obstacle cells, %dx%d): %.3f ms" % [map.obstacles.size(), map.width, map.height, rebuild_ms])

	# Pick one real obstacle cell and confirm a line aimed straight at it from
	# a few cells away reports blocked, while a line well clear of it doesn't.
	var obstacle_cell: Vector2i = Vector2i(-1, -1)
	for pos in map.obstacles.keys():
		if pos.x > 5 and pos.y > 5 and pos.x < map.width - 5 and pos.y < map.height - 5:
			obstacle_cell = pos
			break
	if obstacle_cell.x < 0:
		print("    SKIPPED: no interior obstacle cell found to test against")
	else:
		var ts = float(map.tile_size)
		var target_center = Vector2((obstacle_cell.x + 0.5) * ts, (obstacle_cell.y + 0.5) * ts)
		var probe_from = Vector2((obstacle_cell.x - 4 + 0.5) * ts, (obstacle_cell.y + 0.5) * ts) # 4 cells to the left, same row
		var beyond = Vector2((obstacle_cell.x + 4 + 0.5) * ts, (obstacle_cell.y + 0.5) * ts) # 4 cells to the right, same row - path crosses the obstacle cell as an intermediate
		var results = batcher._rasterizer.batch_line_of_sight([
			{"from": probe_from, "to": target_center}, # aimed AT the obstacle cell - endpoint, should be visible (endpoints aren't tested)
			{"from": probe_from, "to": beyond}, # path THROUGH the obstacle cell - should be blocked
		])
		print("    aimed at real obstacle cell %s as destination (endpoint, expect true): %s" % [obstacle_cell, results[0]])
		print("    path crossing that same cell as an intermediate (expect false): %s" % [results[1]])
		if results[0] != true or results[1] != false:
			push_error("FAIL: real-map smoke test got unexpected result(s) - see above")
		else:
			print("    PASS: real-map smoke test behaves as expected")
	print("")

	map.queue_free()
	await get_tree().process_frame

func _measure_flow_field_rebuild():
	print("--- Flow-field BFS rebuild cost (real Normal-map MapGenerator) ---")
	var map = MapGeneratorScript.new()
	map.map_type = "Normal"
	add_child(map) # _ready() generates the full map + nav grid synchronously
	await get_tree().process_frame

	# A real mid-map cell with open terrain around it, not (0,0) which can
	# land in a forced border/edge case depending on generation.
	var target_cell = Vector2i(map.width / 2, map.height / 2)
	var attempts = 0
	while map.astar_grid.is_point_solid(target_cell) and attempts < 20:
		target_cell += Vector2i(1, 0)
		attempts += 1

	var samples: Array = []
	for t in range(REBUILD_TRIALS):
		MechScript._perf_flow_field_rebuild_usec = 0
		map._rebuild_flow_field(target_cell)
		samples.append(MechScript._perf_flow_field_rebuild_usec / 1000.0) # ms

	var steady = samples.slice(1) # discard trial 1 as warmup, same convention as every other benchmark this session
	var mean = 0.0
	for s in steady:
		mean += s
	mean /= steady.size()
	print("    %d trials (1 warmup discarded): %s ms" % [REBUILD_TRIALS, samples])
	print("    mean steady-state: %.4f ms/rebuild  (cadence: once per %.1fs, window radius %d cells)" % [mean, MapGeneratorScript.FLOW_FIELD_REFRESH, MapGeneratorScript.FLOW_FIELD_RADIUS])
	if mean > 1.0:
		print("    VERDICT: %.3f ms every %.1fs is worth investigating - proceed with Phase 3." % [mean, MapGeneratorScript.FLOW_FIELD_REFRESH])
	else:
		print("    VERDICT: sub-millisecond per rebuild at a %.1fs cadence - not worth a Rust port. Skip Phase 3, redirect effort to Phase 2/4." % MapGeneratorScript.FLOW_FIELD_REFRESH)
	print("")
	map.queue_free()
	await get_tree().process_frame

func _measure_boss_retreat_raycast():
	print("--- Boss retreat-raycast (_pick_retreat_dir, 5-ray fan) cost ---")
	var world = Node2D.new()
	add_child(world)
	var boss = MechScript.new()
	boss.is_player = false
	boss.is_boss = true
	boss.combat_role = "sniper" # forces get_position_style() == "kiter" without needing a real BossProfile resource
	world.add_child(boss)
	await get_tree().process_frame

	var brain = BossBrain.new(boss)
	var dir = Vector2.RIGHT
	var samples: Array = []
	for t in range(RETREAT_TRIALS):
		var before = MechScript._perf_boss_retreat_raycast_usec
		brain._pick_retreat_dir(dir)
		samples.append(MechScript._perf_boss_retreat_raycast_usec - before)

	var steady = samples.slice(1)
	var mean_usec = 0.0
	for s in steady:
		mean_usec += s
	mean_usec /= steady.size()
	print("    %d trials (1 warmup discarded), mean: %.2f us/call" % [RETREAT_TRIALS, mean_usec])
	print("    at real single-boss cadence (once per tick while kiting/hit-and-run-retreating), this is the whole Phase 4 grid-LOS candidate cost - population size 1, same shape packet_tax.rs lost on.")
	print("")
	world.queue_free()
	await get_tree().process_frame
