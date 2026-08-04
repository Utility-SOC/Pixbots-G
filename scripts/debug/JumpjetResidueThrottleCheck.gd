extends Node

# Perf audit (2026-08-01) item 6: JumpjetResidue's damage/overlap check was
# unthrottled at 60Hz (a real physics-server get_overlapping_bodies() call
# per zone per tick). Throttled to 10Hz via an elapsed-accumulator, same
# pattern as the Simulation LOD status-effect throttling. This check
# confirms total damage dealt to a body sitting in the zone for its whole
# life matches damage_per_sec * lifetime, within the coarser-tick tolerance
# throttling introduces (not exact 60Hz-tick precision, but no leak/drift).

const JumpjetResidueScript = preload("res://scripts/attacks/JumpjetResidue.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")

func _ready():
	var failures = 0
	var world = Node2D.new()
	add_child(world)

	var target = MechScript.new()
	target.is_player = false
	target.max_hp = 1000000.0
	target.hp = 1000000.0
	target.global_position = Vector2.ZERO
	target.collision_layer = 4
	world.add_child(target)

	var residue = JumpjetResidueScript.new()
	residue.damage_per_sec = 10.0
	residue.lifetime = 3.0
	# KINETIC deliberately, not FIRE/ICE - those trigger apply_status()'s own
	# independent "burning"/"frozen" DoT ticks on the target, which would
	# add damage on top of the residue's own direct apply_damage() and
	# throw off this check's total (a test-design gotcha, not a bug in the
	# throttle fix itself - the old unthrottled code had the same status
	# re-trigger behavior, just 60x/sec instead of 10x/sec).
	residue.synergies = {EnergyPacket.SynergyType.KINETIC: 5.0}
	residue.global_position = Vector2.ZERO
	world.add_child(residue)

	# Let the ENGINE drive _physics_process automatically (it's already in
	# the tree) - don't also call it manually, that would double-tick.
	var total_ticks = int(4.0 / (1.0 / 60.0)) # run past the 3s lifetime + fade-out
	for i in total_ticks:
		if not is_instance_valid(residue):
			break
		await get_tree().physics_frame

	var expected = 10.0 * 3.0 # damage_per_sec * lifetime
	var actual = 1000000.0 - target.hp
	var tol = 10.0 * (JumpjetResidueScript.DAMAGE_TICK_INTERVAL + (1.0 / 60.0)) # one throttle interval's slop, either direction

	print("expected ~%.2f damage, got %.2f (tolerance +/- %.2f)" % [expected, actual, tol])
	if abs(actual - expected) > tol:
		push_error("FAIL: throttled JumpjetResidue damage drifted from the unthrottled total (expected ~%.2f, got %.2f)" % [expected, actual])
		failures += 1
	else:
		print("PASS: throttled damage total tracks damage_per_sec * lifetime within one throttle interval's tolerance")

	if failures == 0:
		print("PASS: JumpjetResidueThrottleCheck - 10Hz-throttled damage matches the real damage_per_sec rate over the zone's lifetime")
	get_tree().quit(0 if failures == 0 else 1)
