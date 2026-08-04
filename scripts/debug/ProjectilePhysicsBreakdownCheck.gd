extends Node

# Follow-up to ProjectilePhysicsAtScaleCheck.gd: that check proved the real
# cost at high live-projectile counts is _physics_process, not rendering.
# This one breaks down WHERE inside the physics tick the cost actually is,
# at N=500 (matching the real stress-test video's 495 live shots exactly,
# not the earlier check's exaggerated 1500) - reads the ALREADY-EXISTING
# Projectile._perf_physics_usec counter (accumulates real
# _physics_process_body cost, already read/reset once a second by
# FpsCounter.gd in live gameplay - no new instrumentation needed) plus
# checks whether the Rust flight-batch path (ProjectileManager) is actually
# engaged, since a silent fallback to the slow per-instance path would
# itself explain a lot.
#
# MUST run non-headless (see ProjectilePhysicsAtScaleCheck.gd's header for
# why - Performance.get_monitor(RENDER_*) and real frame timing both need
# a real window, though this check itself only reads TIME_PHYSICS_PROCESS
# and the Projectile-side counter, not RENDER_* specifically).

const ProjectileScript = preload("res://scripts/entities/Projectile.gd")

const SHOT_COUNT = 500

func _random_synergies() -> Dictionary:
	var syn := {}
	var n_types = randi_range(1, 3)
	var all_types = [
		EnergyPacket.SynergyType.RAW, EnergyPacket.SynergyType.FIRE, EnergyPacket.SynergyType.ICE,
		EnergyPacket.SynergyType.LIGHTNING, EnergyPacket.SynergyType.VORTEX, EnergyPacket.SynergyType.POISON,
		EnergyPacket.SynergyType.EXPLOSION, EnergyPacket.SynergyType.KINETIC, EnergyPacket.SynergyType.PIERCE,
		EnergyPacket.SynergyType.VAMPIRIC
	]
	all_types.shuffle()
	for i in n_types:
		syn[all_types[i]] = randf_range(50.0, 400.0)
	return syn

func _ready():
	var world = Node2D.new()
	add_child(world)
	var camera = Camera2D.new()
	camera.enabled = true
	camera.make_current()
	world.add_child(camera)

	for i in 5:
		await get_tree().process_frame

	# Baseline: TIME_PHYSICS_PROCESS with ZERO projectiles, to isolate
	# whether other autoloads (SeparationBatcher, SightAndSearchBatcher,
	# SolidGridBatcher, etc. - all real project.godot autoloads, active
	# regardless of this bare test scene having no real Mechs/map) are
	# contributing noise unrelated to projectiles at all.
	for i in 10:
		await get_tree().process_frame
	var base_phys_ms = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	print("BASELINE (zero projectiles) TIME_PHYSICS_PROCESS: %.3f ms" % base_phys_ms)

	print("Rust flight extension available: %s" % ProjectileManager.is_rust_available())

	for i in SHOT_COUNT:
		var proj = ProjectileScript.new()
		proj.synergies = _random_synergies()
		proj.damage = 20.0
		proj.fired_by_player = (i % 2 == 0)
		proj.direction = Vector2.RIGHT.rotated(randf() * TAU)
		proj.global_position = Vector2(randf_range(-6400, 6400), randf_range(-4000, 4000))
		world.add_child(proj)

	for i in 15:
		await get_tree().process_frame

	print("ProjectileManager.live_count() = %d (should be %d)" % [ProjectileManager.live_count(), SHOT_COUNT])

	# Reset the aggregate counter, run a known number of real physics ticks,
	# then read it back - gives real us/tick for _physics_process_body alone.
	ProjectileScript._perf_physics_usec = 0
	ProjectileManager._perf_collect_usec = 0
	ProjectileManager._perf_rust_call_usec = 0
	var t0 = Time.get_ticks_usec()
	const TICKS = 60
	var frame_count_before = Engine.get_physics_frames()
	while Engine.get_physics_frames() - frame_count_before < TICKS:
		await get_tree().process_frame
	var wall_ms = (Time.get_ticks_usec() - t0) / 1000.0
	var actual_ticks = Engine.get_physics_frames() - frame_count_before

	var physics_body_usec = ProjectileScript._perf_physics_usec
	var phys_ms_total = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0

	print("Over %d real physics ticks (%.1fms wall time, %.3fms/tick avg):" % [actual_ticks, wall_ms, wall_ms / actual_ticks])
	print("  Projectile._physics_process_body aggregate: %d us total = %.3f us/tick-total, %.4f us/projectile/tick" % [
		physics_body_usec, float(physics_body_usec) / actual_ticks, float(physics_body_usec) / actual_ticks / SHOT_COUNT
	])
	print("  Engine TIME_PHYSICS_PROCESS (last tick, all physics nodes combined): %.3f ms" % phys_ms_total)
	print("  _physics_process_body's share of one tick's wall time: %.1f%%" % (
		(float(physics_body_usec) / actual_ticks / 1000.0) / (wall_ms / actual_ticks) * 100.0
	))
	print("  UNACCOUNTED (TIME_PHYSICS_PROCESS minus _physics_process_body's own share, minus the %.3fms zero-projectile baseline): ~%.3f ms - must be ProjectileManager/ProjectileBroadphase/ProjectileTargetingBatcher's own per-tick work" % [
		base_phys_ms, phys_ms_total - (float(physics_body_usec) / actual_ticks / 1000.0) - base_phys_ms
	])
	print("  ProjectileManager collection loop (_prepare_flight_request x %d/tick): %d us total = %.3f ms/tick avg" % [
		SHOT_COUNT, ProjectileManager._perf_collect_usec, float(ProjectileManager._perf_collect_usec) / actual_ticks / 1000.0
	])
	print("  ProjectileManager Rust batch call (compute_batch, one FFI call/tick): %d us total = %.3f ms/tick avg" % [
		ProjectileManager._perf_rust_call_usec, float(ProjectileManager._perf_rust_call_usec) / actual_ticks / 1000.0
	])

	# Isolate which autoload owns the unaccounted cost - toggle each off
	# individually (autoloads are just named nodes in the tree) and
	# re-measure. ProjectileManager can't be safely disabled here (every
	# projectile's own _physics_process would fall back to the slow
	# per-instance Rust call, contaminating the comparison), so only
	# Broadphase and the targeting batcher are tested.
	for autoload_name in ["ProjectileBroadphase", "ProjectileTargetingBatcher"]:
		var node = get_node("/root/" + autoload_name)
		node.set_physics_process(false)
		for i in 10:
			await get_tree().process_frame
		var phys_ms_without = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		print("  WITH %s DISABLED: TIME_PHYSICS_PROCESS = %.3f ms (was %.3f ms, delta %.3f ms)" % [
			autoload_name, phys_ms_without, phys_ms_total, phys_ms_total - phys_ms_without
		])
		node.set_physics_process(true)
		for i in 5:
			await get_tree().process_frame

	get_tree().quit(0)
