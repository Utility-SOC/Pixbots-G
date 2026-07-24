extends Node

# Follow-up to ProjectileBroadphaseProfileDiagnostic.gd: that diagnostic
# already ruled out projectile Area2D collision as the dominant cost behind
# a real 2 FPS playtest (0.8% of the with-projectiles frame delta) and
# surfaced a much bigger, unexplained signal instead - 60 enemy Mechs alone
# cost ~349ms/tick with physics_process DISABLED on every one of them, and
# still ~262ms/tick with BOTH process and physics_process disabled. Since
# disabling physics_process means move_and_slide() (which lives inside
# _physics_process) never runs at all in that config, the cost can't be
# coming from CALLING move_and_slide - it has to be the underlying
# CharacterBody2D + CollisionShape2D simply existing as a registered body in
# PhysicsServer2D, which the engine steps every physics tick regardless of
# whether any script ever touches it.
#
# First bisection round (move_and_slide / collision shape / _ai_state_label,
# each isolated individually) came back NOISY and inconclusive across two
# separate process launches - single-shot A/B deltas of 5-40ms rode on top
# of a ~300-360ms baseline that itself varied by ~35ms between launches
# (JIT/cache/OS-scheduling noise between process runs, not real signal). Two
# of the three even flipped sign between runs. That's not a real result -
# it's noise the size of the effect being measured.
#
# This round fixes the methodology two ways: (1) every config is measured
# MULTIPLE times back-to-back inside this SAME process (not across separate
# launches), averaged, so cross-launch noise can't masquerade as signal; (2)
# instead of guessing at individual lines again, it does a genuine coarse
# binary split first - skip the ENTIRE "far" (mosey) branch body at once
# (Mech._diag_skip_far_branch_body) - to prove or disprove the cost lives
# somewhere in that branch at all before trying to localize further within
# it.

const MechScript = preload("res://scripts/entities/Mech.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")

const ENEMY_COUNT = 60
const MEASURE_FRAMES = 90
const TRIALS_PER_CONFIG = 3
const FIELD_SIZE = 3000.0
# Mosey's "far" threshold is 1400px (Mech.gd ~L795) - park the dummy target
# well outside that so every spawned mech takes the mosey branch.
const FAR_TARGET_OFFSET = 5000.0

var world: Node2D
var _dummy_target: Node2D

func _spawn_mechs(skip_far_branch_body: bool, equip_real_torso: bool = false, near_target: Node2D = null, skip_separation: bool = false, skip_shoot: bool = false, disable_shape: bool = false, null_ai_state_label: bool = false) -> Array:
	var mechs = []
	for i in range(ENEMY_COUNT):
		var m = MechScript.new()
		m.is_player = false
		m._diag_skip_separation = skip_separation
		m._diag_skip_shoot = skip_shoot
		if equip_real_torso:
			# A bare Mech.new() has an EMPTY components dict, so MechRenderer.
			# _rebuild_visuals()'s "for slot in components.keys()" loop never
			# runs at all for it - meaning the earlier bare-mech configs
			# couldn't have caught any real per-mech render/pixel-bake cost
			# even if one exists. Real enemy mechs always spawn with a full
			# equipped build, so this config uses a real starter torso
			# (ComponentEquipment.create_starter_torso - same helper
			# AutoEquipSolverTorsoCheck.gd already uses) to actually exercise
			# that path.
			var torso = ComponentEquipmentScript.create_starter_torso()
			m.equip_component(torso)
		world.add_child(m)
		if near_target:
			# Clustered close around the target (well inside the 1400px
			# mosey threshold) so every mech genuinely takes the near/engaged
			# branch, not scattered across the whole field like the far
			# configs - matches a real skirmish, not a spread-out map.
			var offset = Vector2(randf_range(-300.0, 300.0), randf_range(-300.0, 300.0))
			m.global_position = near_target.global_position + offset
			m.target = near_target
		else:
			m.global_position = Vector2(randf_range(-FIELD_SIZE, FIELD_SIZE), randf_range(-FIELD_SIZE, FIELD_SIZE))
			m.target = _dummy_target
		m._diag_skip_far_branch_body = skip_far_branch_body
		if disable_shape:
			for c in m.get_children():
				if c is CollisionShape2D:
					c.set_deferred("disabled", true)
		if null_ai_state_label:
			# _ai_state_label.text is set UNCONDITIONALLY every tick in the
			# CHASE branch ("CHASE"/"SEARCH", line ~2335) - unlike Mosey's
			# equivalent write, which is throttled to once per 0.5s inside
			# _mosey_toward_target. An earlier round tested nulling this
			# label but only in the far/mosey scenario, where it's already
			# cheap - never in CHASE mode specifically, where it's written
			# ~30x more often. Every read/write site already guards with
			# `if _ai_state_label:`, so nulling it here is safe.
			if is_instance_valid(m._ai_state_label):
				m._ai_state_label.queue_free()
			m._ai_state_label = null
		mechs.append(m)
	return mechs

func _measure_once() -> float:
	await get_tree().physics_frame
	var total_sec = 0.0
	for i in range(MEASURE_FRAMES):
		await get_tree().physics_frame
		total_sec += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	return total_sec * 1000.0 / MEASURE_FRAMES # ms/tick, actual compute time

# Runs _measure_once() TRIALS_PER_CONFIG times back-to-back against the SAME
# live population (no teardown/respawn between trials - steady-state cost is
# what matters here, not spawn cost) and reports mean + spread so noise is
# visible instead of hidden in a single sample.
func _measure_stable(label: String) -> float:
	var samples: Array = []
	for t in range(TRIALS_PER_CONFIG):
		samples.append(await _measure_once())
	var mean = 0.0
	for s in samples:
		mean += s
	mean /= samples.size()
	var lo = samples[0]
	var hi = samples[0]
	for s in samples:
		lo = min(lo, s)
		hi = max(hi, s)
	print("    [%s] trials=%s  mean=%.3f  spread=[%.3f, %.3f]" % [label, samples, mean, lo, hi])
	return mean

func _teardown(nodes: Array):
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame

func _ready():
	world = Node2D.new()
	add_child(world)
	_dummy_target = Node2D.new()
	_dummy_target.global_position = Vector2(FAR_TARGET_OFFSET, FAR_TARGET_OFFSET)
	world.add_child(_dummy_target)

	print("--- Config P: frozen reference (physics_process OFF) ---")
	var mechs_p = _spawn_mechs(false)
	for m in mechs_p:
		m.set_physics_process(false)
	var ms_p = await _measure_stable("P")
	print("P mean: %.3f ms/physics-tick" % ms_p)
	await _teardown(mechs_p)

	print("--- Config Q: realistic (physics_process ON, full far-branch body runs) ---")
	var mechs_q = _spawn_mechs(false)
	var ms_q = await _measure_stable("Q")
	print("Q mean: %.3f ms/physics-tick" % ms_q)
	await _teardown(mechs_q)

	print("--- Config V: realistic, but the ENTIRE far-branch body skipped (flee/mosey/water-avoid/move_and_slide all no-op'd at once) ---")
	var mechs_v = _spawn_mechs(true)
	var ms_v = await _measure_stable("V")
	print("V mean: %.3f ms/physics-tick" % ms_v)
	await _teardown(mechs_v)

	print("--- Config W: bulk spawn, REAL equipped starter torso per mech (exercises MechRenderer._rebuild_visuals' actual part-drawing path, unlike P/Q/V's bare mechs) ---")
	var mechs_w = _spawn_mechs(false, true)
	for m in mechs_w:
		m.set_physics_process(false) # isolate spawn/render cost specifically, same as P
	var ms_w = await _measure_stable("W")
	print("W mean: %.3f ms/physics-tick" % ms_w)
	await _teardown(mechs_w)

	# --- Config X: NEAR/ENGAGED combat - the actual real-playtest scenario ---
	# (17 enemies, 2 collision pairs, 4 fps, per a real screenshot) that
	# nothing measured so far has exercised at all. P/Q/V/W all used mechs
	# parked 5000px from any target (forcing the Mosey/far branch,
	# deliberately cheap-by-design) or physics disabled entirely. This
	# clusters bare mechs within engagement range of a real (non-shooting)
	# target so _execute_ai_tactics runs its full near-branch: sight check,
	# shared-flow-field movement, throttled separation query, and an
	# engagement-range _shoot() attempt (a no-op for a bare mech with no
	# weapon mounts - this isolates ENEMY-side AI/movement cost specifically,
	# not anything about a real player build's own energy simulation).
	var near_target = Node2D.new()
	near_target.global_position = Vector2.ZERO
	world.add_child(near_target)

	# Config-delta comparisons (X vs Y vs Z below) came back noisy/
	# contradictory at the ~10-20ms scale involved - inference-by-
	# subtraction across separately-spawned populations isn't precise
	# enough here. Direct instrumentation instead: reset Mech's own real
	# per-region usec counters (same pattern already used for ai_tactics/
	# shoot/move, now extended - see Mech.gd's _perf_sight_usec/
	# _perf_flow_field_usec/_perf_orbit_raycast_usec/_perf_separation_usec),
	# run ONE long, real, steady-state combat scenario, and read out exactly
	# where the wall-clock time actually went - a measurement, not an
	# inference.
	const NEAR_COMBAT_TRIALS = 12 # per the user: "keep running trials" - well past the 3-trial noise floor
	print("--- Config X: near/engaged combat AI, %d trials with direct per-region instrumentation ---" % NEAR_COMBAT_TRIALS)
	var mechs_x = _spawn_mechs(false, false, near_target)
	# NOTE: _perf_ai_tactics_usec/_perf_shoot_usec/_perf_move_usec are reset
	# once/sec by FpsCounter.gd's own HUD readout (a real autoload, active
	# even headless) - unreliable for a multi-second measurement window.
	# _perf_diag_ai_tactics_usec/_perf_diag_shoot_usec wrap the identical
	# call sites under names FpsCounter doesn't know about, so THOSE are the
	# trustworthy totals here.
	MechScript._perf_diag_ai_tactics_usec = 0
	MechScript._perf_diag_shoot_usec = 0
	MechScript._perf_flee_check_usec = 0
	MechScript._perf_sight_usec = 0
	MechScript._perf_flow_field_usec = 0
	MechScript._perf_orbit_raycast_usec = 0
	MechScript._perf_separation_usec = 0
	var x_samples: Array = []
	for t in range(NEAR_COMBAT_TRIALS):
		x_samples.append(await _measure_once())
	var ms_x = 0.0
	for s in x_samples:
		ms_x += s
	ms_x /= x_samples.size()
	print("    [X] %d trials, mean=%.3f  samples=%s" % [NEAR_COMBAT_TRIALS, ms_x, x_samples])
	# Total ticks actually measured across all trials, for turning the raw
	# accumulated usec counters into a real per-mech-per-tick average.
	var total_ticks = NEAR_COMBAT_TRIALS * MEASURE_FRAMES
	var per_tick_divisor = float(total_ticks * ENEMY_COUNT)
	var total_ai = MechScript._perf_diag_ai_tactics_usec
	print("    ai_tactics (reliable total): %8.3f us/mech-tick  (%.1f ms total across %d mechs x %d ticks)" % [total_ai / per_tick_divisor, total_ai / 1000.0, ENEMY_COUNT, total_ticks])
	print("    flee-check:    %8.3f us/mech-tick  (%.1f%% of total)" % [MechScript._perf_flee_check_usec / per_tick_divisor, 100.0 * MechScript._perf_flee_check_usec / max(1, total_ai)])
	print("    sight check:   %8.3f us/mech-tick  (%.1f%% of total)" % [MechScript._perf_sight_usec / per_tick_divisor, 100.0 * MechScript._perf_sight_usec / max(1, total_ai)])
	print("    flow field:    %8.3f us/mech-tick  (%.1f%% of total)" % [MechScript._perf_flow_field_usec / per_tick_divisor, 100.0 * MechScript._perf_flow_field_usec / max(1, total_ai)])
	print("    orbit raycast: %8.3f us/mech-tick  (%.1f%% of total)" % [MechScript._perf_orbit_raycast_usec / per_tick_divisor, 100.0 * MechScript._perf_orbit_raycast_usec / max(1, total_ai)])
	print("    separation:    %8.3f us/mech-tick  (%.1f%% of total)" % [MechScript._perf_separation_usec / per_tick_divisor, 100.0 * MechScript._perf_separation_usec / max(1, total_ai)])
	print("    shoot:         %8.3f us/mech-tick  (%.1f%% of total)" % [MechScript._perf_diag_shoot_usec / per_tick_divisor, 100.0 * MechScript._perf_diag_shoot_usec / max(1, total_ai)])
	var accounted = MechScript._perf_flee_check_usec + MechScript._perf_sight_usec + MechScript._perf_flow_field_usec + MechScript._perf_orbit_raycast_usec + MechScript._perf_separation_usec + MechScript._perf_diag_shoot_usec
	print("    UNACCOUNTED:   %8.3f us/mech-tick  (%.1f%% of total - distance/dir math, boss checks, function-call overhead)" % [(total_ai - accounted) / per_tick_divisor, 100.0 * (total_ai - accounted) / max(1, total_ai)])
	print("")
	print("    Cross-check: total_ai (%.1f ms) vs the raw measured per-tick cost x total_ticks (%.1f ms) - these SHOULD be in the same ballpark if ai_tactics really is most of what's expensive here." % [total_ai / 1000.0, ms_x * (total_ticks)])
	await _teardown(mechs_x)

	# _execute_ai_tactics itself only accounts for ~1ms/tick (60 mechs) per
	# the direct instrumentation above - nowhere near the observed 12-27ms/
	# tick steady-state. The one structural difference between this config
	# and every far/mosey config (which measured only ~2ms/tick): near/
	# engaged mechs are clustered within a tight 300px radius to force
	# engagement, while every far config scattered mechs across a 6000x6000
	# field. Dense clustering means real, overlapping CollisionShape2D
	# bodies - genuine PhysicsServer2D collision-pair resolution, entirely
	# independent of any GDScript AI logic. This isolates that specifically:
	# same tight cluster, same CHASE-branch AI, but no collision shape.
	print("--- Config X2: same tight cluster + CHASE AI, but CollisionShape2D disabled (isolates clustering/collision-pair cost from AI logic) ---")
	var mechs_x2 = _spawn_mechs(false, false, near_target, false, false, true)
	var x2_samples: Array = []
	for t in range(NEAR_COMBAT_TRIALS):
		x2_samples.append(await _measure_once())
	var ms_x2 = 0.0
	for s in x2_samples:
		ms_x2 += s
	ms_x2 /= x2_samples.size()
	print("    [X2] %d trials, mean=%.3f  samples=%s" % [NEAR_COMBAT_TRIALS, ms_x2, x2_samples])
	await _teardown(mechs_x2)

	# Steady-state comparison (skip trial 1, which every config's spawn
	# spike dominates regardless of what's being isolated).
	var x_steady = 0.0
	for i in range(1, x_samples.size()):
		x_steady += x_samples[i]
	x_steady /= (x_samples.size() - 1)
	var x2_steady = 0.0
	for i in range(1, x2_samples.size()):
		x2_steady += x2_samples[i]
	x2_steady /= (x2_samples.size() - 1)
	print("")
	print("X  steady-state (clustered, shape ON):  %.3f ms/tick" % x_steady)
	print("X2 steady-state (clustered, shape OFF): %.3f ms/tick  (delta: %+.3f)" % [x2_steady, x2_steady - x_steady])
	if x_steady - x2_steady > x_steady * 0.5:
		print("VERDICT (X2): dense-clustering collision-pair resolution (real CollisionShape2D overlap, NOT AI logic) explains most of the near-combat cost gap.")
	else:
		print("VERDICT (X2): disabling the collision shape did NOT meaningfully close the gap either - the cost is neither AI logic nor collision-pair resolution.")

	# Config X3: _ai_state_label nulled. Written UNCONDITIONALLY every tick
	# in CHASE (unlike Mosey's throttled 0.5s-interval equivalent write) -
	# a Label.text/.modulate assignment can trigger TextServer shaping/
	# minimum-size recompute, and CHASE does this ~30x more often than
	# Mosey ever did. An earlier round tested nulling this label but only
	# in the already-throttled far/mosey scenario - never here.
	print("--- Config X3: same tight cluster + CHASE AI, but _ai_state_label nulled (unthrottled per-tick Label writes removed) ---")
	var mechs_x3 = _spawn_mechs(false, false, near_target, false, false, false, true)
	var x3_samples: Array = []
	for t in range(NEAR_COMBAT_TRIALS):
		x3_samples.append(await _measure_once())
	var ms_x3 = 0.0
	for s in x3_samples:
		ms_x3 += s
	ms_x3 /= x3_samples.size()
	print("    [X3] %d trials, mean=%.3f  samples=%s" % [NEAR_COMBAT_TRIALS, ms_x3, x3_samples])
	await _teardown(mechs_x3)
	near_target.queue_free()

	var x3_steady = 0.0
	for i in range(1, x3_samples.size()):
		x3_steady += x3_samples[i]
	x3_steady /= (x3_samples.size() - 1)
	print("")
	print("X3 steady-state (clustered, ai_state_label nulled): %.3f ms/tick  (delta vs X: %+.3f)" % [x3_steady, x3_steady - x_steady])
	if x_steady - x3_steady > x_steady * 0.5:
		print("VERDICT (X3): the unthrottled per-tick _ai_state_label.text/.modulate write in CHASE mode explains most of the near-combat cost gap.")
	else:
		print("VERDICT (X3): nulling the debug label did NOT meaningfully close the gap either.")

	var branch_body_cost = ms_q - ms_v
	var unexplained_gap = ms_v - ms_p
	var real_render_cost = ms_w - ms_p
	var near_combat_cost = ms_x - ms_q

	print("")
	print("=== RESULT (each mean of %d trials x %d mechs x %d frames) ===" % [TRIALS_PER_CONFIG, ENEMY_COUNT, MEASURE_FRAMES])
	print("P  frozen (physics_process off):                          %.3f ms/tick" % ms_p)
	print("Q  realistic, full far-branch body:                       %.3f ms/tick" % ms_q)
	print("V  realistic, far-branch body entirely skipped:           %.3f ms/tick  (delta over Q: %+.3f)" % [ms_v, -branch_body_cost])
	print("")
	print("The far-branch body (flee-check + mosey + water-avoid + move_and_slide combined) accounts for %.3f ms/tick (%.1f%% of Q's %.3f ms)." % [branch_body_cost, 100.0 * branch_body_cost / max(0.001, ms_q), ms_q])
	print("Even with that whole branch skipped, V is still %.3f ms/tick above the frozen floor P - %s." % [unexplained_gap, "that gap lives OUTSIDE the far-branch body, in the always-run preamble" if unexplained_gap > branch_body_cost else "most of the real cost IS inside the far-branch body"])
	print("W  bulk spawn, real equipped torso (render exercised):   %.3f ms/tick  (delta over bare-mech P: %+.3f)" % [ms_w, real_render_cost])
	print("X  near/engaged combat AI (full _execute_ai_tactics):    %.3f ms/tick  (delta over far/mosey Q: %+.3f)" % [ms_x, near_combat_cost])
	print("")
	if near_combat_cost > 5.0 and near_combat_cost > branch_body_cost:
		print("VERDICT: near/engaged combat AI (_execute_ai_tactics' near-branch - sight/flow-field/separation/shoot-attempt) costs meaningfully MORE than the far/mosey branch ever did - this is the real, previously-untested cost path a real skirmish actually pays, and where the next fix should target.")
	elif branch_body_cost > unexplained_gap and branch_body_cost > 5.0:
		print("VERDICT: the far-branch body (mosey/move_and_slide/flee-check) is where most of the per-mech cost actually lives - safe to keep narrowing INSIDE it in a follow-up round.")
	elif unexplained_gap > 5.0:
		print("VERDICT: most of the per-mech cost is OUTSIDE the far-branch body entirely - the earlier single-function hypotheses (move_and_slide, collision shape, ai_state_label) were the wrong place to look; the always-run preamble (update_status_effects/status_runner.tick, _tick_weapon_charges, ability-system .tick() calls, _refresh_water_state/_update_obstacle_phasing) needs its own bisection round instead.")
	else:
		print("VERDICT: no config here shows a clean signal above the trial-to-trial spread - the cost may be diffuse (many small calls each contributing a little) rather than one isolable line; consider whether TIME_PHYSICS_PROCESS/this measurement approach is even the right tool before spending more rounds on finer bisection.")

	get_tree().quit(0)
