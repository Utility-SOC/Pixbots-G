extends Node

# Follow-up to MechPhysicsCostDiagnostic.gd's own header comment: a prior
# session found 60 enemy Mechs cost ~349ms/tick with physics_process
# DISABLED on every one of them (implying the bare CharacterBody2D +
# CollisionShape2D existing as a registered PhysicsServer2D body costs real
# per-tick time regardless of script activity) - but a 2026-07-27 re-run of
# that same file's P/Q/V/W comparison came back with the SAME symptom this
# diagnostic exists to rule out: the "mean of 3 trials" is dominated by a
# huge first-trial JIT/shader-compile/physics-registration warmup spike
# (e.g. one config's raw trials were [194.9, 2.23, 2.04]ms - the "mean"
# is almost entirely that one outlier), while P/Q/V/W's own verdict logic
# uses that noisy mean, not a steady-state average. This file fixes that
# specifically: a real WARMUP phase (many discarded physics frames after
# spawn, before measurement starts) so one-time costs fully drain before
# the timed window begins, at three different mech counts to also check
# whether any real cost scales linearly with population (evidence for
# genuine per-body registration cost) or stays flat (evidence for a fixed
# one-time cost that warmup already explains).

const MechScript = preload("res://scripts/entities/Mech.gd")

const MECH_COUNTS = [20, 40, 60]
const WARMUP_FRAMES = 20
const MEASURE_FRAMES = 90

var world: Node2D

func _spawn_bare_mechs(count: int) -> Array:
	var mechs = []
	for i in range(count):
		var m = MechScript.new()
		m.is_player = false
		world.add_child(m)
		m.global_position = Vector2(randf_range(-3000, 3000), randf_range(-3000, 3000))
		m.set_process(false)
		m.set_physics_process(false)
		mechs.append(m)
	return mechs

func _measure() -> float:
	for i in range(WARMUP_FRAMES):
		await get_tree().physics_frame
	var total_sec = 0.0
	for i in range(MEASURE_FRAMES):
		await get_tree().physics_frame
		total_sec += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	return total_sec * 1000.0 / MEASURE_FRAMES

func _teardown(nodes: Array):
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	for i in range(5):
		await get_tree().physics_frame

func _ready():
	world = Node2D.new()
	add_child(world)

	print("--- Baseline: empty world (warmed up %d frames, measured over %d) ---" % [WARMUP_FRAMES, MEASURE_FRAMES])
	var ms_baseline = await _measure()
	print("Baseline: %.4f ms/tick" % ms_baseline)

	var results = []
	for count in MECH_COUNTS:
		print("--- %d frozen Mechs (process+physics_process OFF, real CollisionShape2D present) ---" % count)
		var mechs = _spawn_bare_mechs(count)
		var ms = await _measure()
		print("%d mechs: %.4f ms/tick  (delta over baseline: %+.4f, %.4f us/mech)" % [count, ms, ms - ms_baseline, (ms - ms_baseline) * 1000.0 / count])
		results.append(ms - ms_baseline)
		await _teardown(mechs)

	print("")
	print("=== RESULT ===")
	print("Baseline (0 mechs):     %.4f ms/tick" % ms_baseline)
	for i in range(MECH_COUNTS.size()):
		print("%d mechs, delta:        %+.4f ms/tick" % [MECH_COUNTS[i], results[i]])
	print("")

	# Linearity check: does cost-per-mech stay roughly constant across the
	# three population sizes (real per-body cost) or does the delta stay
	# roughly flat regardless of count (a fixed cost warmup should have
	# already absorbed, meaning the ORIGINAL claim was warmup noise, not a
	# real per-body registration cost)?
	var per_mech = []
	for i in range(MECH_COUNTS.size()):
		per_mech.append(results[i] / MECH_COUNTS[i])
	print("Per-mech cost at each population: %s us/mech" % [per_mech.map(func(x): return "%.4f" % (x * 1000.0))])

	var max_pm = per_mech.max()
	var min_pm = per_mech.min()
	if results[results.size() - 1] > 2.0 and (max_pm - min_pm) < max_pm * 0.4:
		print("VERDICT: real, meaningful, roughly-linear per-mech cost confirmed even after proper warmup - bare CharacterBody2D+CollisionShape2D registration IS a genuine per-tick cost at scale. Worth pursuing (e.g. LOD-gating physics bodies for distant/off-screen mechs).")
	elif results[results.size() - 1] < 1.0:
		print("VERDICT: no meaningful cost survives proper warmup - the prior session's finding was JIT/shader-compile warmup noise, not a real per-tick cost. Bare CharacterBody2D existence is NOT a priority.")
	else:
		print("VERDICT: a small effect survives warmup but doesn't scale cleanly with count - inconclusive, worth another round with more trials before committing effort here.")

	get_tree().quit(0)
