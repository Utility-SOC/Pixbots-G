extends Node

# Regression harness for ProjectileBroadphase's static-obstacle target
# cache (live playtest: "broadphase" was the single dominant per-second
# cost on the overlay - 424-467ms/sec - and stayed roughly CONSTANT
# whether 1 or 76 shots were live, proving the cost scaled with something
# OTHER than projectile count. Root cause: the obstacle half of the target
# list (trees/ruins/destructibles/corpses - none of which ever move once
# placed) was rebuilt from scratch every single physics tick regardless.
# Fix: cache it, only rebuild when the "obstacle" group's membership
# actually changes.

const CorpseHuskScript = preload("res://scripts/entities/CorpseHusk.gd")

# Reuses the real CorpseHusk class as the stub - it already declares
# broadphase_radius and self-registers into the "obstacle" group in its own
# _ready() (CorpseHusk.gd:18-21), which is exactly the real membership
# mechanism this fix depends on. A CollisionShape2D child isn't needed for
# this test (broadphase_radius just stays its 0.0 default, which is fine -
# this check only cares about caching/invalidation, not hit geometry).
func _make_obstacle_stub(pos: Vector2) -> Node2D:
	var o = CorpseHuskScript.new()
	o.global_position = pos
	return o

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

	var o1 = _make_obstacle_stub(Vector2(0, 0))
	var o2 = _make_obstacle_stub(Vector2(100, 0))
	world.add_child(o1)
	world.add_child(o2)
	await get_tree().process_frame

	ProjectileBroadphase._cached_obstacle_targets = []
	ProjectileBroadphase._cached_obstacle_count = -1
	ProjectileBroadphase._obstacle_rebuild_count = 0

	var first = ProjectileBroadphase._get_obstacle_targets()
	_check("first call builds the real obstacle list (2 stubs)", first.size() == 2)
	_check("first call counts as exactly one rebuild", ProjectileBroadphase._obstacle_rebuild_count == 1)

	for i in range(20):
		ProjectileBroadphase._get_obstacle_targets()
	_check("20 more calls with no membership change trigger ZERO additional rebuilds (the actual perf fix)",
		ProjectileBroadphase._obstacle_rebuild_count == 1)

	var o3 = _make_obstacle_stub(Vector2(200, 0))
	world.add_child(o3)
	await get_tree().process_frame
	var after_add = ProjectileBroadphase._get_obstacle_targets()
	_check("adding a new obstacle triggers a rebuild (real membership change detected)",
		ProjectileBroadphase._obstacle_rebuild_count == 2)
	_check("rebuilt list reflects the new obstacle (3 targets now)", after_add.size() == 3)

	o1.queue_free()
	await get_tree().process_frame
	ProjectileBroadphase._get_obstacle_targets()
	_check("removing an obstacle also triggers a rebuild",
		ProjectileBroadphase._obstacle_rebuild_count == 3)

	if failures == 0:
		print("PASS: ProjectileBroadphase's static obstacle target list is cached correctly - reused across unchanged ticks, rebuilt only on real membership changes")
	get_tree().quit(0 if failures == 0 else 1)
