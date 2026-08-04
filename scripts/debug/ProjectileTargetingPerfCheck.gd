extends Node

# Task #33 ("batch homing-target search + vortex pull queries into Rust")
# instrumentation - measures the REAL current cost of Projectile.gd's two
# throttled PhysicsShapeQueryParameters2D.intersect_shape() calls
# (_find_homing_target/_pull_nearby_items) before committing to a Rust port,
# same "gate on the real number" discipline the AI-tactics-cutover plan used
# throughout (see C:\Users\Utility\.claude\plans\effervescent-drifting-kazoo.md).
#
# 60 real enemy mechs as targets (matches MechPhysicsCostDiagnostic.gd's
# established population), 100 real projectiles with both Vampiric AND
# Vortex ratios (exercises both throttled query paths at once, matching a
# real heavy-Vampiric/Vortex build) - "100+ live projectiles" is the exact
# scenario the code's own existing comment cites as the original motivation
# for throttling these in the first place. Fresh projectile set per trial
# (same fix the AI-tactics investigation needed for the search-pattern
# measurement - projectiles despawn/replace themselves in real combat, a
# single population living across trials wouldn't match real turnover).

const ProjectileScript = preload("res://scripts/entities/Projectile.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")

const TARGET_COUNT = 60
const PROJECTILE_COUNT = 100
const MEASURE_TICKS = 180 # 3 sim-seconds - homing fires every 0.1s, vortex every 0.05s, so this exercises many real query cycles per trial
const TRIALS = 5

var world: Node2D

func _ready():
	world = Node2D.new()
	add_child(world)

	var targets = []
	for i in range(TARGET_COUNT):
		var m = MechScript.new()
		m.is_player = false
		m.global_position = Vector2(randf_range(-500.0, 500.0), randf_range(-500.0, 500.0))
		world.add_child(m)
		# Real projectiles at real damage WILL physically overlap these
		# targets over a multi-trial run (ProjectileBroadphase's hit
		# detection is untouched by this diagnostic) - without this, some
		# targets die and drop real loot mid-run, which both destabilizes
		# the candidate population trial-to-trial (the exact
		# state-carryover confound this session's methodology already
		# learned to avoid) and pulls unrelated LootPickup/loot-pull cost
		# into what's supposed to be an isolated targeting-query
		# measurement. Kept alive so the target population is identical
		# across every trial.
		m.max_hp = 1e9
		m.hp = 1e9
		targets.append(m)

	await get_tree().physics_frame

	var homing_samples: Array = []
	var vortex_samples: Array = []
	for t in range(TRIALS):
		var projectiles = []
		for i in range(PROJECTILE_COUNT):
			var p = ProjectileScript.new()
			p.synergies = {EnergyPacket.SynergyType.VAMPIRIC: 5.0, EnergyPacket.SynergyType.VORTEX: 5.0}
			p.damage = 10.0
			p.fired_by_player = true
			p.collision_mask = 4 # targets Enemy layer, matches real player-fired shots
			p.global_position = Vector2(randf_range(-500.0, 500.0), randf_range(-500.0, 500.0))
			world.add_child(p) # _ready() computes ratios
			projectiles.append(p)

		await get_tree().physics_frame

		ProjectileScript._perf_homing_query_usec = 0
		ProjectileScript._perf_vortex_query_usec = 0
		for i in range(MEASURE_TICKS):
			await get_tree().physics_frame
		homing_samples.append(ProjectileScript._perf_homing_query_usec / 1000.0) # ms total this trial
		vortex_samples.append(ProjectileScript._perf_vortex_query_usec / 1000.0)

		for p in projectiles:
			if is_instance_valid(p):
				p.queue_free()
		await get_tree().physics_frame

	var homing_steady = homing_samples.slice(1) # discard trial 1 as warmup, same convention as every other benchmark this session
	var vortex_steady = vortex_samples.slice(1)
	var homing_mean = 0.0
	for s in homing_steady:
		homing_mean += s
	homing_mean /= homing_steady.size()
	var vortex_mean = 0.0
	for s in vortex_steady:
		vortex_mean += s
	vortex_mean /= vortex_steady.size()

	# Expected query COUNT per trial (not per tick - both are throttled):
	# each of PROJECTILE_COUNT projectiles fires roughly
	# MEASURE_TICKS*physics_dt/INTERVAL times over the trial window.
	var physics_dt = 1.0 / 60.0
	var expected_homing_calls = float(PROJECTILE_COUNT) * (MEASURE_TICKS * physics_dt) / ProjectileScript.HOMING_QUERY_INTERVAL
	var expected_vortex_calls = float(PROJECTILE_COUNT) * (MEASURE_TICKS * physics_dt) / ProjectileScript.VORTEX_QUERY_INTERVAL

	print("--- Projectile targeting-query cost, %d targets, %d projectiles, %d trials ---" % [TARGET_COUNT, PROJECTILE_COUNT, TRIALS])
	print("    homing (_find_homing_target) per-trial totals (1 warmup discarded): %s ms" % [homing_samples])
	print("    vortex (_pull_nearby_items)  per-trial totals (1 warmup discarded): %s ms" % [vortex_samples])
	print("    homing mean: %.3f ms/trial  (~%.0f real calls/trial => %.2f us/call)" % [homing_mean, expected_homing_calls, (homing_mean * 1000.0) / expected_homing_calls])
	print("    vortex mean: %.3f ms/trial  (~%.0f real calls/trial => %.2f us/call)" % [vortex_mean, expected_vortex_calls, (vortex_mean * 1000.0) / expected_vortex_calls])
	var total_per_sec = (homing_mean + vortex_mean) / (MEASURE_TICKS * physics_dt) * 1000.0
	print("    combined: %.3f ms/sec of real physics-server query cost at this population" % total_per_sec)
	if total_per_sec > 2.0:
		print("    VERDICT: meaningful aggregate cost - worth investigating a Rust-batched replacement.")
	else:
		print("    VERDICT: sub-2ms/sec aggregate at this population - marginal, weigh against implementation risk before committing.")
	get_tree().quit(0)
