extends Node

# Rigorous same-process A/B test for task #33 ("batch homing-target search
# + vortex pull queries into Rust") - the real per-projectile physics
# queries (_find_homing_target/_pull_nearby_items, still intact for this
# exact purpose) vs. the new Rust-batched ProjectileTargetingBatcher path.
# A cross-process before/after comparison (ProjectileTargetingPerfCheck.gd,
# run separately before and after the swap) showed homing ~2.1x faster and
# vortex ~1.5x faster, but cross-process comparisons are exactly the
# methodology this session already learned not to fully trust on their own
# (JIT/cache warmup noise). This alternates both configs in ONE process,
# same stable (undying) target population, 10 interleaved trials per
# config with the first pair discarded as warmup - the same rigor that
# produced packet_tax.rs's and Phase 4's trustworthy verdicts.

const MechScript = preload("res://scripts/entities/Mech.gd")
const ProjectileScript = preload("res://scripts/entities/Projectile.gd")

const TARGET_COUNT = 60
const PROJECTILE_COUNT = 100
const TRIALS_PER_CONFIG = 10

var world: Node2D
var targets: Array = []
var projectiles: Array = []

func _ready():
	world = Node2D.new()
	add_child(world)

	for i in range(TARGET_COUNT):
		var m = MechScript.new()
		m.is_player = false
		m.global_position = Vector2(randf_range(-500.0, 500.0), randf_range(-500.0, 500.0))
		m.max_hp = 1e9 # never dies - keeps the candidate population stable across every trial, no loot-drop noise
		m.hp = 1e9
		world.add_child(m)
		targets.append(m)

	for i in range(PROJECTILE_COUNT):
		var p = ProjectileScript.new()
		p.synergies = {EnergyPacket.SynergyType.VAMPIRIC: 5.0, EnergyPacket.SynergyType.VORTEX: 5.0}
		p.damage = 10.0
		p.fired_by_player = true
		p.collision_mask = 4
		p.global_position = Vector2(randf_range(-500.0, 500.0), randf_range(-500.0, 500.0))
		p.set_physics_process(false) # drive the queries manually below, isolate query cost from flight/movement cost
		world.add_child(p) # _ready() computes ratios
		p._flight_r_kin = 0.0
		p._flight_r_vamp = 0.5
		p._flight_r_ltg = 0.0
		projectiles.append(p)

	await get_tree().physics_frame

	var homing_a: Array = []
	var homing_b: Array = []
	var vortex_a: Array = []
	var vortex_b: Array = []
	for t in range(TRIALS_PER_CONFIG):
		if t % 2 == 0:
			homing_a.append(_time_homing_old())
			homing_b.append(_time_homing_new())
			vortex_a.append(_time_vortex_old())
			vortex_b.append(_time_vortex_new())
		else:
			homing_b.append(_time_homing_new())
			homing_a.append(_time_homing_old())
			vortex_b.append(_time_vortex_new())
			vortex_a.append(_time_vortex_old())

	_report("homing", homing_a, homing_b)
	_report("vortex", vortex_a, vortex_b)
	get_tree().quit(0)

func _report(label: String, a_samples: Array, b_samples: Array):
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
	var a_us = (a_mean * 1000.0) / float(PROJECTILE_COUNT)
	var b_us = (b_mean * 1000.0) / float(PROJECTILE_COUNT)

	print("--- %s A/B: old direct queries (A) vs new Rust-batched (B) ---" % label)
	print("    A per-trial ms (1 warmup discarded): %s" % [a_samples])
	print("    B per-trial ms (1 warmup discarded): %s" % [b_samples])
	print("    A mean: %.4f us/call   B mean: %.4f us/call" % [a_us, b_us])
	var delta_pct = 100.0 * (b_us - a_us) / a_us
	if b_us < a_us:
		print("    VERDICT: B (Rust-batched) is %.1f%% FASTER than A (old direct queries). Real win - keep it." % -delta_pct)
	elif delta_pct < 5.0:
		print("    VERDICT: B is within noise of A (%.1f%% delta) - a wash." % delta_pct)
	else:
		print("    VERDICT: B (Rust-batched) is %.1f%% SLOWER than A - matches the packet_tax.rs/Phase 4 precedent. Recommend reverting." % delta_pct)
	print("")

func _time_homing_old() -> float:
	var space_state = world.get_world_2d().direct_space_state
	var t0 = Time.get_ticks_usec()
	for p in projectiles:
		p._find_homing_target(space_state, p._flight_r_kin, p._flight_r_vamp, p._flight_r_ltg)
	return (Time.get_ticks_usec() - t0) / 1000.0 # ms

func _time_homing_new() -> float:
	var t0 = Time.get_ticks_usec()
	for p in projectiles:
		p._request_homing_target()
	ProjectileTargetingBatcher._resolve_homing()
	ProjectileTargetingBatcher._homing_requests.clear()
	return (Time.get_ticks_usec() - t0) / 1000.0 # ms

func _time_vortex_old() -> float:
	var t0 = Time.get_ticks_usec()
	for p in projectiles:
		p._pull_nearby_items(0.05)
	return (Time.get_ticks_usec() - t0) / 1000.0 # ms

func _time_vortex_new() -> float:
	var t0 = Time.get_ticks_usec()
	for p in projectiles:
		var radius = (150.0 + 100.0 * p.ratios.get(EnergyPacket.SynergyType.VORTEX, 0.0)) * p._get_vortex_magnitude_pull_mult()
		ProjectileTargetingBatcher.request_vortex_pull(p, radius, 0.05)
	ProjectileTargetingBatcher._resolve_vortex()
	ProjectileTargetingBatcher._vortex_requests.clear()
	return (Time.get_ticks_usec() - t0) / 1000.0 # ms
