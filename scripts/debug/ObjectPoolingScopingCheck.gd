extends Node

# Scoping investigation for task #35 ("object pooling for Mech/Projectile") -
# NOT an implementation, per that task's own "scope, don't build yet"
# framing. Measures the real spawn+despawn CYCLE cost (allocation + node
# setup + queue_free teardown) at realistic volume, to see whether pooling
# (reusing instances instead of allocating/freeing) would plausibly pay off
# - distinct from the CONSTRUCTION CONTENT cost already measured earlier
# this session (ProjectileConstructCostDiagnostic.gd found _build_visuals/
# packet math dominate _ready() itself; this asks a different question -
# how much does the raw new()/add_child()/queue_free() cycle cost on top of
# that, which is the part pooling could actually eliminate).

const ProjectileScript = preload("res://scripts/entities/Projectile.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")

const COUNT = 200
const TRIALS = 5

var world: Node2D

func _ready():
	world = Node2D.new()
	add_child(world)

	await _measure_projectile_cycle()
	await _measure_mech_cycle()
	get_tree().quit(0)

func _measure_projectile_cycle():
	print("--- Projectile spawn+despawn cycle cost (%d projectiles/trial) ---" % COUNT)
	var samples: Array = []
	for t in range(TRIALS):
		var t0 = Time.get_ticks_usec()
		var projs = []
		for i in range(COUNT):
			var p = ProjectileScript.new()
			p.synergies = {EnergyPacket.SynergyType.RAW: 5.0}
			p.damage = 10.0
			p.fired_by_player = true
			p.global_position = Vector2(randf_range(-500.0, 500.0), randf_range(-500.0, 500.0))
			world.add_child(p)
			projs.append(p)
		var t1 = Time.get_ticks_usec()
		for p in projs:
			p.queue_free()
		await get_tree().physics_frame # let queue_free's actual deletion happen
		var t2 = Time.get_ticks_usec()
		samples.append({"spawn_ms": (t1 - t0) / 1000.0, "free_ms": (t2 - t1) / 1000.0})

	_report("Projectile", samples)

func _measure_mech_cycle():
	print("--- Mech spawn+despawn cycle cost (%d mechs/trial, real starter torso each) ---" % (COUNT / 4))
	var samples: Array = []
	var n = COUNT / 4 # mechs are much heavier per-instance than projectiles - smaller count, still a real signal
	for t in range(TRIALS):
		var t0 = Time.get_ticks_usec()
		var mechs = []
		for i in range(n):
			var m = MechScript.new()
			m.is_player = false
			m.global_position = Vector2(randf_range(-500.0, 500.0), randf_range(-500.0, 500.0))
			world.add_child(m)
			m.equip_component(ComponentEquipmentScript.create_starter_torso())
			mechs.append(m)
		var t1 = Time.get_ticks_usec()
		for m in mechs:
			m.queue_free()
		await get_tree().physics_frame
		var t2 = Time.get_ticks_usec()
		samples.append({"spawn_ms": (t1 - t0) / 1000.0, "free_ms": (t2 - t1) / 1000.0})

	_report("Mech", samples, n)

func _report(label: String, samples: Array, count: int = COUNT):
	var spawn_samples = []
	var free_samples = []
	for s in samples:
		spawn_samples.append(s.spawn_ms)
		free_samples.append(s.free_ms)
	var spawn_steady = spawn_samples.slice(1)
	var free_steady = free_samples.slice(1)
	var spawn_mean = _mean(spawn_steady)
	var free_mean = _mean(free_steady)
	print("    spawn: %s ms  (mean steady-state: %.3f ms = %.2f us/%s)" % [spawn_samples, spawn_mean, (spawn_mean * 1000.0) / count, label])
	print("    free:  %s ms  (mean steady-state: %.3f ms = %.2f us/%s)" % [free_samples, free_mean, (free_mean * 1000.0) / count, label])
	print("    combined cycle: %.2f us/%s" % [((spawn_mean + free_mean) * 1000.0) / count, label])
	print("")

func _mean(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var s = 0.0
	for v in arr:
		s += v
	return s / arr.size()
