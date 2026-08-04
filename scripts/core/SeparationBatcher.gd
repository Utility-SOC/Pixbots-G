extends Node

# Batches Mech._compute_separation() across every eligible enemy mech into
# ONE call per cadence instead of each mech independently running its own
# PhysicsShapeQueryParameters2D circle query on its own staggered timer -
# see rust_ext/src/separation.rs's module comment for the full rationale
# (Big-O analysis prompted by a friend's bad-performance playtest, 2026-08-03:
# separation is O(n x k) where k trends toward n in a dense cluster, exactly
# the shape combat produces).
#
# Autoload, same register-nothing/poll-EntityCache-directly pattern
# ProjectileBroadphase.gd uses for its target list - mechs don't need to
# individually register here, since EntityCache.get_group("enemy") already
# is the authoritative live population.
#
# Sequencing: runs on its own timer (matches Mech.SEPARATION_QUERY_INTERVAL,
# 0.2s) rather than every physics tick - the batched call itself is cheap,
# but there's no reason to recompute steering nudges faster than the value
# meaningfully changes at 5Hz already provided smooth-enough movement before.

var _timer: float = 0.0
var _checked: bool = false
var _rasterizer = null

func _ensure_rust():
	if not _checked:
		_checked = true
		if ClassDB.class_exists("SeparationRs"):
			_rasterizer = ClassDB.instantiate("SeparationRs")

func _physics_process(delta: float):
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = Mech.SEPARATION_QUERY_INTERVAL
	_ensure_rust()

	var mechs: Array = []
	for m in EntityCache.get_group("enemy"):
		if not is_instance_valid(m) or m.is_boss or m.get("_diag_skip_separation") == true:
			continue
		mechs.append({"id": m.get_instance_id(), "pos": m.global_position})

	if mechs.is_empty():
		return

	var _t_sep = Time.get_ticks_usec()
	var results: Array
	if _rasterizer:
		results = _rasterizer.batch_compute_separation(mechs, Mech.SEPARATION_RADIUS)
	else:
		results = _batch_compute_separation_fallback(mechs, Mech.SEPARATION_RADIUS)
	Mech._perf_separation_usec += Time.get_ticks_usec() - _t_sep

	for r in results:
		var mech = instance_from_id(int(r.id))
		if mech and is_instance_valid(mech):
			mech._cached_separation = r.push

# Pure-GDScript reference implementation - the fallback contract every
# Rust-ported system in this codebase keeps (see ProjectileBroadphase.
# _query_hits_fallback): the DLL must never become a hard dependency.
# Same grid-bucket approach as SeparationRs, just in GDScript.
func _batch_compute_separation_fallback(mechs: Array, radius: float) -> Array:
	var cell_size = max(1.0, radius)
	var buckets: Dictionary = {} # (cx, cy) packed key -> Array of indices
	var pos_of: Array = []
	for m in mechs:
		pos_of.append(m.pos)
	for i in range(mechs.size()):
		var key = _cell_key(pos_of[i], cell_size)
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(i)

	var out: Array = []
	for i in range(mechs.size()):
		var pos = pos_of[i]
		var cx = floori(pos.x / cell_size)
		var cy = floori(pos.y / cell_size)
		var push = Vector2.ZERO
		var count = 0
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var key = "%d:%d" % [cx + dx, cy + dy]
				if not buckets.has(key):
					continue
				for j in buckets[key]:
					if j == i:
						continue
					var away = pos - pos_of[j]
					var d = away.length()
					if d > 0.001 and d < radius:
						push += away.normalized() * (1.0 - d / radius)
						count += 1
		if count > 0:
			push /= count
		out.append({"id": mechs[i].id, "push": push})
	return out

func _cell_key(pos: Vector2, cell_size: float) -> String:
	return "%d:%d" % [floori(pos.x / cell_size), floori(pos.y / cell_size)]
