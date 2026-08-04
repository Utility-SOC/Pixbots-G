extends Node

# Diagnostic, not a pass/fail regression test. Originally measured whether
# Area2D collision detection was the dominant cost of heavy projectile
# combat (it was - that measurement justified the Rust broadphase port, see
# C:\Users\Utility\.claude\plans\effervescent-exploring-pine.md). Projectile
# is no longer an Area2D at all post-cutover, so the old Config A/B
# (toggling monitoring/monitorable/collision shape) no longer applies -
# repurposed per that plan's Day 4 note to instead demonstrate the actual
# win: Rust query_hits vs the pure-GDScript _query_hits_fallback, at the
# same population this file has used all along.
#
# Method: build the SAME population (enemy Mechs + live projectiles) twice.
# Config A forces ProjectileBroadphase onto its GDScript fallback path
# (_rasterizer set to null, mirroring how it behaves if the DLL isn't
# loaded). Config B restores the real Rust rasterizer. The wall-clock delta
# between A and B isolates what the Rust port actually saves over the
# fallback it replaces. A baseline C (no projectiles at all) shows the
# enemy-only floor for context.

const MechScript = preload("res://scripts/entities/Mech.gd")
const ProjectileScript = preload("res://scripts/entities/Projectile.gd")

const ENEMY_COUNT = 60
const PROJECTILE_COUNT = 300
const MEASURE_FRAMES = 90
const FIELD_SIZE = 3000.0

var world: Node2D

func _spawn_enemies() -> Array:
	var mechs = []
	for i in range(ENEMY_COUNT):
		var m = MechScript.new()
		m.is_player = false
		world.add_child(m)
		m.set_physics_process(false) # isolate projectile cost, not AI cost
		m.global_position = Vector2(randf_range(-FIELD_SIZE, FIELD_SIZE), randf_range(-FIELD_SIZE, FIELD_SIZE))
		mechs.append(m)
	return mechs

func _spawn_projectiles() -> Array:
	var projs = []
	for i in range(PROJECTILE_COUNT):
		var p = ProjectileScript.new()
		p.fired_by_player = true
		p.source_mech = null
		p.source_label = "profile"
		p.damage = 10.0
		p.synergies = {EnergyPacket.SynergyType.RAW: 50.0}
		p.global_position = Vector2(randf_range(-FIELD_SIZE, FIELD_SIZE), randf_range(-FIELD_SIZE, FIELD_SIZE))
		var dir = Vector2.RIGHT.rotated(randf_range(0.0, TAU))
		p.direction = dir
		p.target_direction = dir
		world.add_child(p) # _ready() registers it with ProjectileBroadphase unconditionally
		projs.append(p)
	return projs

func _measure() -> float:
	# Wall-clock deltas across awaited physics_frame signals measure the
	# ENGINE'S real-time frame pacing (physics_ticks_per_second), not actual
	# compute cost - confirmed by a first pass of this script where a truly
	# empty world (zero entities) came back with the exact same ~15ms/tick
	# as every populated config. Performance.TIME_PHYSICS_PROCESS reports
	# the actual seconds Godot spent running physics-process scripts last
	# frame, independent of real-time pacing, so THIS is what isolates
	# actual per-config compute cost.
	await get_tree().physics_frame # let one frame settle first
	var total_sec = 0.0
	for i in range(MEASURE_FRAMES):
		await get_tree().physics_frame
		total_sec += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	print("    [diag] active_objects=%d  collision_pairs=%d  islands=%d  node_count=%d  orphan_nodes=%d  TIME_PROCESS(non-physics)=%.3fms" % [
		Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS),
		Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS),
		Performance.get_monitor(Performance.PHYSICS_2D_ISLAND_COUNT),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
	])
	return total_sec * 1000.0 / MEASURE_FRAMES # ms/tick, actual compute time

func _teardown(nodes: Array):
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame

func _ready():
	world = Node2D.new()
	add_child(world)

	print("--- Config D: truly empty world, zero entities ---")
	var ms_d = await _measure()
	print("D: %.3f ms/physics-tick" % ms_d)

	print("--- Config E: %d enemy mechs, process AND physics_process both disabled ---" % ENEMY_COUNT)
	var enemies_e = _spawn_enemies()
	for m in enemies_e:
		m.set_process(false)
	var ms_e = await _measure()
	print("E: %.3f ms/physics-tick" % ms_e)
	await _teardown(enemies_e)

	print("--- Config F: 10 enemy mechs (physics_process off, process on) ---")
	var saved_count = ENEMY_COUNT
	var enemies_f = []
	for i in range(10):
		var m = MechScript.new()
		m.is_player = false
		world.add_child(m)
		m.set_physics_process(false)
		m.global_position = Vector2(randf_range(-FIELD_SIZE, FIELD_SIZE), randf_range(-FIELD_SIZE, FIELD_SIZE))
		enemies_f.append(m)
	var ms_f = await _measure()
	print("F: %.3f ms/physics-tick" % ms_f)
	await _teardown(enemies_f)

	print("--- Config C: baseline, %d enemy mechs, no projectiles ---" % ENEMY_COUNT)
	var enemies_c = _spawn_enemies()
	var ms_c = await _measure()
	print("C: %.3f ms/physics-tick" % ms_c)
	await _teardown(enemies_c)

	# Force ProjectileBroadphase's Rust check to have already run once (so
	# _ensure_rust() below never fires again mid-measurement) and capture the
	# real rasterizer instance so Config A can null it out and Config B can
	# restore it - same DLL-presence fallback contract every Rust port in
	# this codebase keeps (see ProjectileManager._ensure_flight_rust).
	ProjectileBroadphase._ensure_rust()
	var real_rasterizer = ProjectileBroadphase._rasterizer
	if real_rasterizer == null:
		print("SKIP: rust_ext DLL doesn't expose ProjectileBroadphaseRs (not built, or debug DLL locked while the editor is open) - can't compare Rust vs fallback.")
		get_tree().quit(0)
		return

	print("--- Config A: %d enemy mechs + %d projectiles, GDScript fallback broadphase ---" % [ENEMY_COUNT, PROJECTILE_COUNT])
	ProjectileBroadphase._rasterizer = null
	var enemies_a = _spawn_enemies()
	var projs_a = _spawn_projectiles()
	var ms_a = await _measure()
	print("A: %.3f ms/physics-tick" % ms_a)
	await _teardown(enemies_a + projs_a)

	print("--- Config B: %d enemy mechs + %d projectiles, Rust broadphase ---" % [ENEMY_COUNT, PROJECTILE_COUNT])
	ProjectileBroadphase._rasterizer = real_rasterizer
	var enemies_b = _spawn_enemies()
	var projs_b = _spawn_projectiles()
	var ms_b = await _measure()
	print("B: %.3f ms/physics-tick" % ms_b)
	await _teardown(enemies_b + projs_b)

	var broadphase_savings = ms_a - ms_b
	var projectile_script_cost = ms_b - ms_c
	print("")
	print("=== RESULT ===")
	print("D  empty world, 0 entities:                  %.3f ms/tick" % ms_d)
	print("E  %d mechs, process+physics_process OFF:    %.3f ms/tick" % [ENEMY_COUNT, ms_e])
	print("F  10 mechs, physics_process off only:       %.3f ms/tick" % ms_f)
	print("C  %d mechs, physics_process off only:       %.3f ms/tick" % [ENEMY_COUNT, ms_c])
	print("A  C + %d projectiles, GDScript fallback:    %.3f ms/tick  (delta over C: %+.3f)" % [PROJECTILE_COUNT, ms_a, ms_a - ms_c])
	print("B  C + %d projectiles, Rust broadphase:      %.3f ms/tick  (delta over C: %+.3f)" % [PROJECTILE_COUNT, ms_b, projectile_script_cost])
	print("")
	if ms_a > 0.001:
		print("Rust broadphase saves %.1f%% of the fallback's added cost over baseline C." % (100.0 * broadphase_savings / max(0.001, ms_a - ms_c)))
	print("Rust: %.3fms/tick vs GDScript fallback: %.3fms/tick at %d projectiles x ~%d part-hitbox targets." % [ms_b, ms_a, PROJECTILE_COUNT, ENEMY_COUNT * 6])

	get_tree().quit(0)
