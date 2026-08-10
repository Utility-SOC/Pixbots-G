extends Node

# Regression harness for ProjectileBatchPool V1 - the experimental
# no-Node-tree parallel projectile system ("the tree seems to be fucking
# us"). Covers spawn/step/hit/despawn/recycle mechanics in isolation,
# without needing a real render pass. This is NOT wired into live combat -
# see GarageTestRange.gd's opt-in toggle for the only integration point.

const ProjectileBatchPoolScript = preload("res://scripts/entities/ProjectileBatchPool.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var world = Node2D.new()
	add_child(world)

	var pool = ProjectileBatchPoolScript.new(8) # small capacity to exercise the cap easily
	world.add_child(pool)
	await get_tree().process_frame

	# --- Spawn + capacity cap ---
	var i0 = pool.spawn(Vector2.ZERO, Vector2.RIGHT, 100.0, 25.0, 8.0, 5.0, Color.RED, 1.0, true, null)
	_check("spawn() returns a valid slot index", i0 >= 0)
	_check("live_count() reflects the one spawned shot", pool.live_count() == 1)

	var spawned = [i0]
	for n in range(7):
		var idx = pool.spawn(Vector2.ZERO, Vector2.RIGHT, 100.0, 25.0, 8.0, 5.0, Color.RED, 1.0, true, null)
		spawned.append(idx)
	_check("pool fills to its capacity (8) after spawning 8 total", pool.live_count() == 8)
	var overflow = pool.spawn(Vector2.ZERO, Vector2.RIGHT, 100.0, 25.0, 8.0, 5.0, Color.RED, 1.0, true, null)
	_check("spawning past capacity returns -1 instead of growing unbounded", overflow == -1)

	# --- Simulate: straight-line movement ---
	pool._step_simulate(1.0) # 1 second at speed 100 -> +100 on X
	_check("straight-line movement advances position by direction * speed * delta",
		pool._position[i0].distance_to(Vector2(100, 0)) < 0.01)

	# --- Despawn + slot recycling ---
	pool.despawn(i0)
	_check("despawn() marks the slot dead", pool.live_count() == 7)
	var recycled = pool.spawn(Vector2(9, 9), Vector2.UP, 50.0, 10.0, 4.0, 2.0, Color.BLUE, 0.5, false, null)
	_check("a despawned slot gets reused by the next spawn (real recycling, not unbounded growth)", recycled == i0)
	_check("the recycled slot's state is fully overwritten by the new spawn (no stale data)",
		pool._position[i0] == Vector2(9, 9) and pool._speed[i0] == 50.0)

	# --- Lifetime expiry ---
	var before_count = pool.live_count()
	pool._step_simulate(3.0) # recycled slot's lifetime is 2.0s, should expire
	_check("a shot past its lifetime auto-despawns during _step_simulate",
		pool.live_count() == before_count - 1)

	# --- Hit detection against a registered target ---
	var target = MechScript.new()
	target.is_player = false
	target.max_hp = 1000.0
	target.hp = 1000.0
	target.global_position = Vector2(300, 0)
	world.add_child(target)
	pool.register_target(target)

	var shooter = MechScript.new()
	shooter.is_player = true
	world.add_child(shooter)

	var hit_idx = pool.spawn(Vector2(295, 0), Vector2.RIGHT, 10.0, 42.0, 20.0, 5.0, Color.GREEN, 1.0, true, shooter)
	var hp_before = target.hp
	pool._step_hit_test()
	_check("a shot within range+radius of a registered target applies damage",
		target.hp < hp_before)
	_check("a shot that hits despawns immediately (no double-hit)",
		pool._alive[hit_idx] == 0)

	# --- unregister_target actually stops future hit-tests ---
	pool.unregister_target(target)
	var miss_idx = pool.spawn(Vector2(295, 0), Vector2.RIGHT, 10.0, 42.0, 20.0, 5.0, Color.GREEN, 1.0, true, shooter)
	var hp_before2 = target.hp
	pool._step_hit_test()
	_check("unregister_target() stops that target from being hit-tested",
		target.hp == hp_before2 and pool._alive[miss_idx] == 1)

	# --- B3: ghost-trail render layer ---
	# _compute_trail_render is a pure static function (no MultiMesh/
	# RenderingServer involved) precisely so it's testable directly -
	# get_instance_transform_2d/get_instance_color don't reliably reflect a
	# same-frame set_instance_* write under --headless with no real render
	# sync ever occurring (confirmed via an isolated bare-MultiMesh probe),
	# so this checks the computation ProjectileBatchPool._step_render()
	# feeds into the MultiMesh, not a round-trip through it.
	var render_pos = Vector2(50, 50)
	var main_color = Color(1.0, 0.2, 0.1, 1.0)
	var trail = ProjectileBatchPoolScript._compute_trail_render(render_pos, Vector2.RIGHT, main_color)
	_check("the ghost trail sits TRAIL_OFFSET_PX behind the main body along -direction",
		trail["position"].distance_to(render_pos - Vector2(ProjectileBatchPoolScript.TRAIL_OFFSET_PX, 0)) < 0.01)
	_check("the ghost trail is dimmer than the main body by TRAIL_ALPHA_MULT",
		abs(trail["color"].a - main_color.a * ProjectileBatchPoolScript.TRAIL_ALPHA_MULT) < 0.001)
	_check("the ghost trail keeps the main body's hue, only alpha changes",
		trail["color"].r == main_color.r and trail["color"].g == main_color.g and trail["color"].b == main_color.b)

	# despawn() must clear BOTH the main and trail MultiMesh layers so a
	# freed slot doesn't leave an orphaned ghost quad on screen - the arrays
	# being correctly parallel-sized is what makes that possible.
	_check("_trail_multimeshes/_trail_instances are parallel-sized to _synergy_multimeshes (one trail layer per synergy)",
		pool._trail_multimeshes.size() == pool._synergy_multimeshes.size() and pool._trail_instances.size() == pool._synergy_instances.size())

	if failures == 0:
		print("PASS: ProjectileBatchPool V1 - spawn/cap/simulate/despawn/recycle/hit-test all correct, no per-shot Nodes involved")
	get_tree().quit(0 if failures == 0 else 1)
