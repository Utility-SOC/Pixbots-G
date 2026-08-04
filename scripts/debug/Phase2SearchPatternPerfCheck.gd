extends Node

# Phase 2 continuation instrumentation for the AI-tactics Rust-cutover plan
# (see C:\Users\Utility\.claude\plans\effervescent-drifting-kazoo.md) -
# measures the REAL cost of SightAndSearch._execute_search (the expanding-
# square search-pattern state machine) before deciding whether it's worth a
# Rust port, same "gate on the real number" discipline Phase 0 used for
# Phase 3. Unlike the sight-check gate just shipped (which eliminated a real
# per-mech physics-server round-trip), most of this state machine is already
# cheap, unthrottled GDScript arithmetic (timer countdowns, distance
# comparisons) with no FFI cost to save - a Rust port only pays off if the
# real number says otherwise.
#
# IMPORTANT: target must stay within Mech.gd's own "near"/"far" LOD split
# (distance <= 1400, the same SIGHT_RANGE-matched threshold at
# Mech.gd:850) - a non-boss mech further than that takes the cheap "mosey"
# branch and never calls _execute_ai_tactics AT ALL, so _execute_search
# never runs (an earlier version of this script parked the target at
# (50000,50000) and silently measured the wrong code path - every trial came
# back exactly 0.0us, which was the tell). So mechs here are placed on the
# FAR SIDE of a real obstacle wall (via Phase 1/2's now-live LOS occlusion,
# same synthetic-wall setup as SolidGridLosCheck.gd) - close enough to stay
# in the near branch, but genuinely blocked from ever gaining sight, forcing
# persistent SEARCH state for the whole trial.
#
# 60 mechs (matches MechPhysicsCostDiagnostic.gd's established population
# size). 5 sim-seconds per trial is long enough for mechs to complete
# several expanding-square legs (SEARCH_LEG_UNIT=110, escalating
# 1,1,2,2,3...) so leg-advance/frontier-picking/obstacle-avoidance get
# genuinely exercised, not just the cheap per-tick bookkeeping path.

const MechScript = preload("res://scripts/entities/Mech.gd")
const MapGeneratorScript = preload("res://scripts/core/MapGenerator.gd")

const ENEMY_COUNT = 60
const MEASURE_TICKS = 300 # 5 sim-seconds at 60Hz
const TRIALS = 5

func _ready():
	var world = Node2D.new()
	add_child(world)

	var map = MapGeneratorScript.new()
	map.map_type = "Tabletop"
	world.add_child(map)

	# Deterministic obstacle wall (x=10, y=5..14), same layout as
	# SolidGridLosCheck.gd/SightAndSearchBatcherCheck.gd.
	map.obstacles = {}
	for y in range(5, 15):
		map.obstacles[Vector2i(10, y)] = "Boulder"
	SolidGridBatcher._ensure_rust()
	if not SolidGridBatcher._rasterizer:
		print("SKIPPED: SolidGridRs not built (DLL missing)")
		get_tree().quit(0)
		return
	SolidGridBatcher._rebuild_grid(map)
	SolidGridBatcher._last_obstacle_count = map.obstacles.size()

	var ts = float(map.tile_size)
	var target = Node2D.new()
	target.global_position = Vector2(2 * ts + ts / 2.0, 9 * ts + ts / 2.0) # left of the wall
	world.add_child(target)

	# Fresh mech set PER TRIAL, torn down after each - the search pattern's
	# own designed behavior migrates mechs outward over time (frontier-point
	# escalation once a pattern exhausts), so reusing one live population
	# across trials drifts mechs out of the near-branch/blocked-LOS test
	# condition as the run progresses. A first attempt at this reused one
	# population across all 5 trials and got a monotonically DECREASING
	# total each trial (31->29->25->16->11ms) - the exact same
	# state-carryover trap packet_tax.rs's first flawed A/B test hit earlier
	# this session, not real signal. Independent fresh mechs per trial (same
	# fix packet_tax's corrected test used) removes the confound.
	var samples: Array = []
	for t in range(TRIALS):
		var mechs = []
		for i in range(ENEMY_COUNT):
			var m = MechScript.new()
			m.is_player = false
			m.target = target
			# Right of the wall, scattered but kept within the ~500-unit
			# range that stays well under the 1400-unit near/far LOD
			# threshold even after adding target's own offset from the wall.
			m.global_position = Vector2(
				(16.0 + randf() * 4.0) * ts,
				(6.0 + randf() * 7.0) * ts
			)
			world.add_child(m)
			mechs.append(m)

		await get_tree().physics_frame
		await get_tree().physics_frame

		# Sanity check before trusting the timing numbers: confirm mechs are
		# actually in the near branch AND actually lack sight (i.e. really
		# exercising _execute_search), not silently in the mosey branch or
		# CHASE. Bails loudly instead of reporting a misleading number.
		var sample_mech = mechs[0]
		var dist = sample_mech.global_position.distance_to(target.global_position)
		if dist > 1400.0:
			push_error("FAIL: test setup broken - mech is %.1f units from target, outside the near-branch threshold (1400). Would silently measure the mosey branch instead." % dist)
			get_tree().quit(1)
			return
		if sample_mech.has_sight_of_player:
			push_error("FAIL: test setup broken - mech has sight of target despite the wall; obstacle occlusion isn't working as expected here.")
			get_tree().quit(1)
			return
		if t == 0:
			print("Sanity check OK: sample mech is %.1f units from target (near branch) and has_sight_of_player=false (search branch active)." % dist)

		MechScript._perf_execute_search_usec = 0
		for i in range(MEASURE_TICKS):
			await get_tree().physics_frame
		samples.append(MechScript._perf_execute_search_usec / 1000.0) # ms total this trial

		for m in mechs:
			if is_instance_valid(m):
				m.queue_free()
		await get_tree().physics_frame

	var steady = samples.slice(1) # discard trial 1 as warmup, same convention as every other benchmark this session
	var mean = 0.0
	for s in steady:
		mean += s
	mean /= steady.size()
	var per_mech_tick_us = (mean * 1000.0) / float(ENEMY_COUNT * MEASURE_TICKS)

	print("--- _execute_search cost, %d mechs, %d ticks/trial, %d trials ---" % [ENEMY_COUNT, MEASURE_TICKS, TRIALS])
	print("    per-trial totals (1 warmup discarded): %s ms" % [samples])
	print("    mean steady-state: %.3f ms total across %d mechs x %d ticks = %.4f us/mech-tick" % [mean, ENEMY_COUNT, MEASURE_TICKS, per_mech_tick_us])
	if per_mech_tick_us > 1.0:
		print("    VERDICT: meaningful cost (%.4f us/mech-tick) - worth investigating a Rust port of the search-pattern state machine." % per_mech_tick_us)
	else:
		print("    VERDICT: sub-microsecond per mech-tick - matches the prediction that this is already cheap GDScript arithmetic with no FFI overhead to save. Not worth a Rust port of the state machine itself; the only real physics cost left in it (_next_leg_target's obstacle-avoidance raycasts) is small/infrequent enough to fold into a future call rather than justifying a dedicated batcher.")
	get_tree().quit(0)
