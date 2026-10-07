extends Node

# ProjectileBatchPool hit-test grid: the candidate set must be a SUPERSET of every target the old brute-force
# scan could hit (distance(target centre, swept segment) <= shot radius + target radius), in ascending order.

const PoolScript = preload("res://scripts/entities/ProjectileBatchPool.gd")

class FakeTarget extends Node2D:
	var is_player := false
	var is_dead := false
	var broadphase_radius := 20.0

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	seed(7)
	var pool = PoolScript.new(1024)
	add_child(pool)
	var targets: Array = []
	for k in range(150):
		var t = FakeTarget.new()
		t.global_position = Vector2(randf_range(-2000, 2000), randf_range(-2000, 2000))
		t.broadphase_radius = randf_range(8.0, 70.0)
		t.is_player = (k == 0)
		add_child(t)
		targets.append(t)
		pool.register_target(t)
	var dead = targets[5]
	dead.is_dead = true
	pool._ht_build()
	_check("dead targets are excluded from the snapshot", not pool._ht_nodes.has(dead))
	_check("snapshot keeps the rest (149)", pool._ht_nodes.size() == 149)

	var missed := 0
	var checked := 0
	var unsorted := 0
	var fast_cases := 0
	for n in range(4000):
		var i = n % 1000
		var a = Vector2(randf_range(-2200, 2200), randf_range(-2200, 2200))
		var len = [10.0, 40.0, 120.0, 400.0, 1500.0][randi() % 5]
		var b = a + Vector2.from_angle(randf() * TAU) * len
		pool._prev_position[i] = a
		pool._position[i] = b
		pool._radius[i] = randf_range(3.0, 30.0)
		var cand: PackedInt32Array = pool._ht_candidates(i)
		for k in range(1, cand.size()):
			if cand[k] <= cand[k - 1]: unsorted += 1
		if cand.size() < pool._ht_nodes.size(): fast_cases += 1
		var cset := {}
		for ti in cand: cset[ti] = true
		for ti in range(pool._ht_nodes.size()):
			var tp: Vector2 = pool._ht_pos[ti]
			var near = Geometry2D.get_closest_point_to_segment(tp, a, b)
			if near.distance_to(tp) <= pool._radius[i] + pool._ht_rad[ti]:
				checked += 1
				if not cset.has(ti): missed += 1
	_check("grid never misses a target the brute force would hit (%d real hits checked)" % checked, missed == 0 and checked > 200)
	_check("candidates are ascending (original _targets order)", unsorted == 0)
	_check("the grid actually prunes (%d of 4000 queries returned a subset)" % fast_cases, fast_cases > 2500)

	pool.use_hit_grid = false
	_check("grid disabled returns every target", pool._ht_candidates(0).size() == pool._ht_nodes.size())
	pool.use_hit_grid = true
	print("ProjectileHitGridCheck: %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)
