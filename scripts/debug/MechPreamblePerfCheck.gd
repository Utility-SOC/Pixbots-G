extends Node

# Simulation-LOD investigation (task #34) - measures the REAL cost of
# Mech._physics_process's ALWAYS-RUN preamble (update_status_effects,
# _tick_weapon_charges, cloak/jammer/healer/shield-pulse ability ticks)
# before designing any LOD gate for it. Unlike AI-tactics/move_and_slide
# (which already have a far-branch LOD path), this preamble runs
# unconditionally for every mech every tick regardless of near/far/engaged
# status - an earlier MechPhysicsCostDiagnostic.gd run flagged it as
# unexplored ("the always-run preamble... needs its own bisection round").
#
# 60 real mechs (matches MechPhysicsCostDiagnostic.gd's established
# population), each with a REAL equipped starter torso (exercises
# _tick_weapon_charges' real precalculated_weapons loop, not a bare mech
# with none) - same real-equipped-part precedent as that diagnostic's
# Config W. Parked far from any target so they take the mosey/far branch
# (the actual "distant, disengaged" scenario Simulation LOD would target),
# confirming the preamble cost is real and NOT already covered by the
# existing far-branch LOD gate.

const MechScript = preload("res://scripts/entities/Mech.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")

const ENEMY_COUNT = 60
const MEASURE_TICKS = 180 # 3 sim-seconds
const TRIALS = 5

var world: Node2D

func _ready():
	world = Node2D.new()
	add_child(world)
	var far_target = Node2D.new()
	far_target.global_position = Vector2(50000, 50000)
	world.add_child(far_target)

	var samples_status: Array = []
	var samples_weapons: Array = []
	var samples_abilities: Array = []
	for t in range(TRIALS):
		var mechs = []
		for i in range(ENEMY_COUNT):
			var m = MechScript.new()
			m.is_player = false
			m.target = far_target
			m.global_position = Vector2(randf_range(-500.0, 500.0), randf_range(-500.0, 500.0))
			var torso = ComponentEquipmentScript.create_starter_torso()
			world.add_child(m)
			m.equip_component(torso)
			mechs.append(m)

		await get_tree().physics_frame

		MechScript._perf_status_effects_usec = 0
		MechScript._perf_weapon_charges_usec = 0
		MechScript._perf_ability_systems_usec = 0
		for i in range(MEASURE_TICKS):
			await get_tree().physics_frame
		samples_status.append(MechScript._perf_status_effects_usec / 1000.0) # ms total this trial
		samples_weapons.append(MechScript._perf_weapon_charges_usec / 1000.0)
		samples_abilities.append(MechScript._perf_ability_systems_usec / 1000.0)

		for m in mechs:
			if is_instance_valid(m):
				m.queue_free()
		await get_tree().physics_frame

	_report("update_status_effects", samples_status)
	_report("_tick_weapon_charges", samples_weapons)
	_report("cloak/jammer/healer/shield-pulse ability ticks", samples_abilities)

	var total_mean_ms = _mean(samples_status.slice(1)) + _mean(samples_weapons.slice(1)) + _mean(samples_abilities.slice(1))
	var per_mech_tick_us = (total_mean_ms * 1000.0) / float(ENEMY_COUNT * MEASURE_TICKS)
	print("--- combined preamble: %.4f us/mech-tick ---" % per_mech_tick_us)
	if per_mech_tick_us > 1.0:
		print("    VERDICT: meaningful cost for distant/disengaged mechs that already skip AI-tactics/move_and_slide's real cost - worth designing a Simulation LOD gate for this preamble too.")
	else:
		print("    VERDICT: sub-microsecond per mech-tick - the existing far-branch LOD gate (AI-tactics + move_and_slide) already covers the real cost; this preamble isn't worth its own gate.")
	get_tree().quit(0)

func _mean(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var s = 0.0
	for v in arr:
		s += v
	return s / arr.size()

func _report(label: String, samples: Array):
	var steady = samples.slice(1) # discard trial 1 as warmup, same convention as every other benchmark this session
	var mean = _mean(steady)
	var per_mech_tick_us = (mean * 1000.0) / float(ENEMY_COUNT * MEASURE_TICKS)
	print("%s: %s ms total/trial  (mean %.3f ms = %.4f us/mech-tick)" % [label, samples, mean, per_mech_tick_us])
