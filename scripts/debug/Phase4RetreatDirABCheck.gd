extends Node

# Rigorous same-process A/B test for Phase 4 of the AI-tactics Rust-cutover
# plan (see C:\Users\Utility\.claude\plans\effervescent-drifting-kazoo.md) -
# BossBrain._pick_retreat_dir's real-raycast-fan vs. its new Rust-batched
# grid-clearance replacement. A cross-process before/after comparison
# (Phase0AiPerfCheck.gd, run separately before and after the swap) came back
# 5.13-7us/call before vs 8.15us/call after - a possible small regression,
# but cross-process comparisons are exactly the methodology this session
# already learned NOT to trust (JIT/cache warmup noise contaminates results
# launch-to-launch - see packet_tax.rs's first flawed A/B test). This
# instead alternates both configs in ONE process, same boss instance
# (_pick_retreat_dir is a pure per-call function with no persistent state to
# carry over between calls, unlike packet_tax's consolidation buffer), 10
# interleaved trials per config with the first pair discarded as warmup -
# the same rigor that produced packet_tax's trustworthy final verdict.
#
# Config A ("old") reimplements the ORIGINAL real-PhysicsRayQueryParameters2D
# fan inline (BossBrain.gd itself no longer has this code - it was replaced,
# not kept side-by-side) so this is testing against the exact real behavior
# this session shipped before the swap, not a guess.

const MechScript = preload("res://scripts/entities/Mech.gd")
const MapGeneratorScript = preload("res://scripts/core/MapGenerator.gd")

const TRIALS_PER_CONFIG = 10
const CALLS_PER_TRIAL = 500

var boss: Mech
var brain: BossBrain

func _ready():
	var world = Node2D.new()
	add_child(world)

	# No MapGenerator/obstacles in this scenario - deliberately matches
	# Phase0AiPerfCheck.gd's own bare-world boss-retreat scenario exactly,
	# so this is a clean apples-to-apples re-test of the SAME measurement,
	# not a different setup.
	boss = MechScript.new()
	boss.is_player = false
	boss.is_boss = true
	boss.global_position = Vector2.ZERO
	world.add_child(boss)
	brain = BossBrain.new(boss)

	await get_tree().physics_frame

	var a_samples: Array = []
	var b_samples: Array = []
	for t in range(TRIALS_PER_CONFIG):
		# Alternate order each trial (A then B, then B then A) so neither
		# config systematically gets the "warmer cache" slot.
		if t % 2 == 0:
			a_samples.append(_time_config_a())
			b_samples.append(_time_config_b())
		else:
			b_samples.append(_time_config_b())
			a_samples.append(_time_config_a())

	# Discard the first trial of each as warmup, same convention as every
	# other benchmark this session.
	var a_steady = a_samples.slice(1)
	var b_steady = b_samples.slice(1)
	var a_mean = 0.0
	for s in a_steady:
		a_mean += s
	a_mean /= a_steady.size()
	var b_mean = 0.0
	for s in b_steady:
		b_mean += s
	b_mean /= b_steady.size()
	var a_us = (a_mean * 1000.0) / float(CALLS_PER_TRIAL)
	var b_us = (b_mean * 1000.0) / float(CALLS_PER_TRIAL)

	print("--- _pick_retreat_dir A/B: old raycast fan (A) vs new Rust-batched clearance (B) ---")
	print("    A (old raycast fan)   per-trial ms (1 warmup discarded): %s" % [a_samples])
	print("    B (new Rust clearance) per-trial ms (1 warmup discarded): %s" % [b_samples])
	print("    A mean: %.4f us/call   B mean: %.4f us/call" % [a_us, b_us])
	var delta_pct = 100.0 * (b_us - a_us) / a_us
	if b_us < a_us:
		print("    VERDICT: B (Rust-batched) is %.1f%% FASTER than A (old raycast fan). Real win - keep it." % -delta_pct)
	elif delta_pct < 5.0:
		print("    VERDICT: B is within noise of A (%.1f%% delta) - a wash, not a meaningful win either way." % delta_pct)
	else:
		print("    VERDICT: B (Rust-batched) is %.1f%% SLOWER than A (old raycast fan) - matches the packet_tax.rs precedent (batch-of-1 FFI overhead exceeds the saved compute). Recommend reverting to the direct raycast fan." % delta_pct)
	get_tree().quit(0)

func _time_config_a() -> float:
	var t0 = Time.get_ticks_usec()
	for i in range(CALLS_PER_TRIAL):
		_pick_retreat_dir_old_raycast_fan(Vector2.RIGHT)
	return (Time.get_ticks_usec() - t0) / 1000.0 # ms

func _time_config_b() -> float:
	var t0 = Time.get_ticks_usec()
	for i in range(CALLS_PER_TRIAL):
		brain._pick_retreat_dir(Vector2.RIGHT)
	return (Time.get_ticks_usec() - t0) / 1000.0 # ms

# Exact reimplementation of the ORIGINAL BossBrain._pick_retreat_dir body
# (before the Phase 4 swap) - real PhysicsRayQueryParameters2D fan, mask=1
# (Env/boundary layer only, matching what shipped in the codebase up to
# this point in the session).
func _pick_retreat_dir_old_raycast_fan(dir: Vector2) -> Vector2:
	var space_state = boss.get_world_2d().direct_space_state
	var candidate_offsets_deg = [0.0, 25.0, -25.0, 50.0, -50.0]
	var probe_dist = 150.0
	var best_dir = -dir
	var best_clearance = -1.0
	for deg in candidate_offsets_deg:
		var candidate = (-dir).rotated(deg_to_rad(deg))
		var query = PhysicsRayQueryParameters2D.create(boss.global_position, boss.global_position + candidate * probe_dist, 1)
		var result = space_state.intersect_ray(query)
		var clearance = probe_dist if result.is_empty() else boss.global_position.distance_to(result.position)
		if clearance > best_clearance:
			best_clearance = clearance
			best_dir = candidate
	return best_dir
