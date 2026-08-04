extends Node

# Integration check for task #33 ("batch homing-target search + vortex pull
# queries into Rust") - confirms the real wiring end to end: a real
# projectile with Vampiric ratio acquires a nearby real enemy mech as its
# homing target via ProjectileTargetingBatcher, and a real projectile with
# Vortex ratio actually applies a pull force (external_force) to a nearby
# real enemy mech. ProximityQueryParityCheck.gd already covers the Rust
# primitive's correctness in isolation - this is the wiring-correctness
# check (matches BossBrainRetreatCheck.gd's role for Phase 4's retreat-dir
# swap before it was reverted).

const MechScript = preload("res://scripts/entities/Mech.gd")
const ProjectileScript = preload("res://scripts/entities/Projectile.gd")

func _ready():
	var failures = 0
	var world = Node2D.new()
	add_child(world)

	# --- Homing target acquisition ---
	var near_enemy = MechScript.new()
	near_enemy.is_player = false
	near_enemy.global_position = Vector2(300.0, 0.0)
	world.add_child(near_enemy)

	var far_enemy = MechScript.new()
	far_enemy.is_player = false
	far_enemy.global_position = Vector2(5000.0, 0.0) # well outside any real min_dist
	world.add_child(far_enemy)

	var homing_proj = ProjectileScript.new()
	homing_proj.synergies = {EnergyPacket.SynergyType.VAMPIRIC: 5.0}
	homing_proj.damage = 10.0
	homing_proj.fired_by_player = true
	homing_proj.collision_mask = 4
	homing_proj.global_position = Vector2.ZERO
	world.add_child(homing_proj)

	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	if not is_instance_valid(homing_proj._cached_homing_target):
		push_error("FAIL: Vampiric projectile never acquired a homing target")
		failures += 1
	elif homing_proj._cached_homing_target != near_enemy:
		push_error("FAIL: Vampiric projectile acquired the wrong target (%s), expected the near enemy" % homing_proj._cached_homing_target)
		failures += 1
	else:
		print("PASS: Vampiric projectile correctly acquired the near enemy as its homing target (not the far one)")

	homing_proj.queue_free()
	near_enemy.queue_free()
	far_enemy.queue_free()
	await get_tree().physics_frame

	# --- Vortex pull application ---
	var pull_target = MechScript.new()
	pull_target.is_player = false
	pull_target.global_position = Vector2(150.0, 0.0)
	world.add_child(pull_target)

	var vortex_proj = ProjectileScript.new()
	vortex_proj.synergies = {EnergyPacket.SynergyType.VORTEX: 8.0}
	vortex_proj.damage = 10.0
	vortex_proj.fired_by_player = true
	vortex_proj.collision_mask = 4
	vortex_proj.global_position = Vector2.ZERO
	world.add_child(vortex_proj)

	var force_before = pull_target.external_force
	# _vortex_query_timer starts at a randomized [0, VORTEX_QUERY_INTERVAL)
	# offset (thundering-herd avoidance) and counts UP via += delta, so the
	# first real trigger can take up to a full VORTEX_QUERY_INTERVAL
	# (0.05s, ~3 ticks at 60Hz) - wait comfortably past that worst case.
	for i in range(8):
		await get_tree().physics_frame

	if pull_target.external_force == force_before:
		push_error("FAIL: nearby enemy mech's external_force never changed - vortex pull wasn't applied")
		failures += 1
	else:
		print("PASS: vortex projectile applied a real pull force to the nearby enemy (external_force: %s -> %s)" % [force_before, pull_target.external_force])

	if failures == 0:
		print("PASS: ProjectileTargetingBatcherCheck - homing acquisition and vortex pull both wired correctly")
	get_tree().quit(0 if failures == 0 else 1)
