extends Node

# STARTED as a rendering-overdraw investigation (perf jam item: "rendering
# overdraw, never investigated" - traced to a real stress-test video, wave
# 12, 495 live shots, 34 enemies, FpsCounter reading "1727 draws" while the
# game visibly dropped to 1-2fps). ENDED somewhere else: rendering is NOT
# the bottleneck.
#
# What actually happened, in order:
# 1. Confirmed draw-call volume DOES scale with live-projectile count (1500
#    real Projectile.gd instances -> ~1800-1900 draws, closely matching the
#    historical "1727 draws" figure once ~34 enemies' own visuals are added).
# 2. First frame-time comparison came back pinned at exactly 60fps in BOTH
#    the empty-baseline and 1500-projectile cases - a vsync ceiling masking
#    any real cost, not evidence of zero cost. Disabled vsync (_init below).
# 3. Uncapped: empty baseline ~2400fps, 1500 dense on-screen projectiles
#    ~30fps - a real, large cost. Rendering looked confirmed... except:
# 4. Spread the SAME 1500 projectiles across a real map-sized area instead
#    of a dense on-screen cluster (mostly off-screen/culled - draws dropped
#    15x, from ~1830 to ~90) and frame time barely moved (~30ms either way).
#    Draw-call count varies 15x between the two scenarios; frame time does
#    NOT. That rules out rendering/overdraw as the driver.
# 5. TIME_PHYSICS_PROCESS stayed ~constant (~30ms) across both draw-call
#    extremes, matching total frame time almost exactly - physics, not
#    rendering. Confirmed directly: same 1500 projectiles with
#    set_physics_process(false) - frame time dropped 8.9x, from ~30ms to
#    ~3.4ms, landing close to the ~2.3ms empty baseline.
#
# CONCLUSION: at high live-projectile counts (1500, plausible in an intense
# multi-mech firefight), the real cost is each Projectile's own per-tick
# _physics_process logic (movement, homing/vortex query timers,
# ProjectileBroadphase.report_movement, off-screen-notifier housekeeping),
# NOT rendering/draw-call volume/overdraw - despite "1727 draws" being the
# only number anyone had actually looked at before this check existed.
# Rendering overdraw is a closed, measured non-issue as of 2026-08-03 - see
# Status.md. This file is kept (not deleted, unlike this session's other
# one-off benchmarks) as the baseline to re-run once real work starts on
# the ACTUAL finding: per-projectile physics-tick cost at scale.
#
# MUST run non-headless: Performance.get_monitor(RENDER_*) reports all
# zeros under --headless (confirmed via HeadlessRenderStatSanityCheck.gd -
# the dummy rendering driver doesn't track these at all, and awaiting
# RenderingServer.frame_post_draw hangs forever under it). This is a real
# windowed run - close any stray Godot window if one is left after a crash.
#
# Spawns real Projectile.gd instances (not the tile-routing plumbing -
# _build_visuals() only depends on .synergies/.damage, already established
# by every other Projectile test this session) with randomized synergy
# compositions matching a realistic "many different builds firing at once"
# mix.

const ProjectileScript = preload("res://scripts/entities/Projectile.gd")

const SHOT_COUNT = 1500

func _init():
	# Both readings came back pinned at exactly 60fps/16.67ms in the first
	# pass - a vsync ceiling, not evidence the GPU cost is actually zero.
	# Disable it so frame time reflects real uncapped render cost.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

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

	for i in 10:
		await get_tree().process_frame
	var base_draw = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var base_obj = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var base_prim = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var base_proc_ms = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0

	# Real wall-clock frame time (not TIME_PROCESS - that's just script/logic
	# CPU time and doesn't reflect GPU render cost at all). Averaged over 60
	# real frames so it reflects actual sustained framerate, not one sample.
	var t0 = Time.get_ticks_usec()
	for i in 60:
		await get_tree().process_frame
	var base_frame_ms = (Time.get_ticks_usec() - t0) / 1000.0 / 60.0
	print("BASELINE (empty scene): draws=%d objs=%d prims=%d proc_ms=%.3f avg_frame_ms=%.3f (%.0f fps)" % [
		base_draw, base_obj, base_prim, base_proc_ms, base_frame_ms, 1000.0 / base_frame_ms
	])

	for i in SHOT_COUNT:
		var proj = ProjectileScript.new()
		proj.synergies = _random_synergies()
		proj.damage = 20.0
		proj.fired_by_player = (i % 2 == 0)
		proj.direction = Vector2.RIGHT.rotated(randf() * TAU)
		proj.global_position = Vector2(randf_range(-500, 500), randf_range(-300, 300))
		world.add_child(proj)

	for i in 15:
		await get_tree().process_frame
	var draw = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var obj = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var prim = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var proc_ms = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var node_count = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)

	var t1 = Time.get_ticks_usec()
	for i in 60:
		await get_tree().process_frame
	var loaded_frame_ms = (Time.get_ticks_usec() - t1) / 1000.0 / 60.0

	print("WITH %d LIVE PROJECTILES: draws=%d objs=%d prims=%d proc_ms=%.3f phys_ms=%.3f node_count=%d avg_frame_ms=%.3f (%.0f fps)" % [
		SHOT_COUNT, draw, obj, prim, proc_ms, phys_ms, node_count, loaded_frame_ms, 1000.0 / loaded_frame_ms
	])
	print("DELTA: +%d draws (+%.1fx), +%d objs, +%d prims, frame time %.3fms -> %.3fms (+%.3fms, %.1fx)" % [
		draw - base_draw, float(draw) / max(1, base_draw),
		obj - base_obj, prim - base_prim,
		base_frame_ms, loaded_frame_ms, loaded_frame_ms - base_frame_ms, loaded_frame_ms / base_frame_ms
	])
	print("Per-shot: %.2f draws/shot, %.1f objs/shot, %.1f prims/shot" % [
		float(draw - base_draw) / SHOT_COUNT, float(obj - base_obj) / SHOT_COUNT, float(prim - base_prim) / SHOT_COUNT
	])

	# --- Second scenario: same shot count, but spread across a real map-sized
	# area (12800x8000, matching a 400x250-tile map at ~32px/tile) instead of
	# crammed into a small on-screen cluster. Most will be off-screen/not
	# overlapping - isolates whether the cost above is genuine on-screen
	# overdraw (many overlapping semi-transparent layers over the same
	# pixels) vs just raw existence-count regardless of density.
	for proj in world.get_children():
		if proj is Node2D and proj != camera:
			proj.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

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
	var draw2 = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var obj2 = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var prim2 = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var proc_ms2 = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms2 = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0

	var t2 = Time.get_ticks_usec()
	for i in 60:
		await get_tree().process_frame
	var spread_frame_ms = (Time.get_ticks_usec() - t2) / 1000.0 / 60.0

	print("WITH %d SPREAD-OUT PROJECTILES (mostly off-screen, matches real map scale): draws=%d objs=%d prims=%d proc_ms=%.3f phys_ms=%.3f avg_frame_ms=%.3f (%.0f fps)" % [
		SHOT_COUNT, draw2, obj2, prim2, proc_ms2, phys_ms2, spread_frame_ms, 1000.0 / spread_frame_ms
	])
	print("COMPARISON: dense on-screen cluster = %.3fms/frame, spread-out (mostly culled) = %.3fms/frame (%.1fx difference)" % [
		loaded_frame_ms, spread_frame_ms, loaded_frame_ms / spread_frame_ms
	])

	# --- Third scenario: phys_ms stayed ~constant across both draw-call
	# extremes above, strongly pointing at per-projectile _physics_process
	# cost rather than rendering. Confirm directly: same 1500 spread-out
	# projectiles, but with physics processing turned OFF on all of them -
	# if frame time drops back near baseline, that proves it.
	for proj in world.get_children():
		if proj is Node2D and proj != camera:
			proj.set_physics_process(false)
	await get_tree().process_frame
	await get_tree().process_frame

	var proc_ms3 = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms3 = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var t3 = Time.get_ticks_usec()
	for i in 60:
		await get_tree().process_frame
	var nophys_frame_ms = (Time.get_ticks_usec() - t3) / 1000.0 / 60.0

	print("SAME 1500 PROJECTILES, physics_process DISABLED: proc_ms=%.3f phys_ms=%.3f avg_frame_ms=%.3f (%.0f fps)" % [
		proc_ms3, phys_ms3, nophys_frame_ms, 1000.0 / nophys_frame_ms
	])
	print("FINAL COMPARISON: with physics=%.3fms/frame, without physics=%.3fms/frame (%.1fx), baseline=%.3fms/frame" % [
		spread_frame_ms, nophys_frame_ms, spread_frame_ms / nophys_frame_ms, base_frame_ms
	])

	get_tree().quit(0)
