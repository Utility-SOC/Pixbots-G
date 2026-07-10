extends Node

# Batches the per-frame flight-math dispatch for every live projectile into
# ONE Rust call instead of one call per projectile - see ProjectileFlight.
# compute_batch (rust_ext/src/projectile_flight.rs) for the actual math.
# Godot's per-call FFI dispatch overhead, not the trig itself, is what
# scaled badly once combat got busy (100+ live shots), so this is a
# dispatch-count fix, not a math optimization.
#
# Sequencing: this node's process_priority is set very low (runs before
# every other physics-processing node this same frame - see _ready).
# Each frame: this manager asks every registered projectile to prepare its
# own request (Projectile._prepare_flight_request - the throttled homing-
# target search and ratio/steering setup that MUST run per-projectile,
# since a physics query can't be batched into the pure-math Rust call),
# collects them all, makes ONE batched Rust call, and stashes the results.
# Each projectile's OWN _physics_process then runs (Godot guarantees this
# happens AFTER this manager's, same frame, due to the priority ordering)
# and reads its already-computed result instead of calling Rust itself.
#
# Registration is opt-in (Projectile._ready calls register/unregister) -
# poison mines use a completely different movement model
# (_physics_process_mine) and never register at all.

var _active: Dictionary = {} # instance_id (int) -> Projectile
var _results: Dictionary = {} # instance_id (int) -> Dictionary (this frame's result)

var _flight_checked: bool = false
var _flight_rasterizer = null

func _ready():
	# Lower runs first - see the module comment above for why this matters.
	process_priority = -1000

func _ensure_flight_rust():
	if not _flight_checked:
		_flight_checked = true
		if ClassDB.class_exists("ProjectileFlight"):
			_flight_rasterizer = ClassDB.instantiate("ProjectileFlight")

func is_rust_available() -> bool:
	_ensure_flight_rust()
	return _flight_rasterizer != null

func register(proj: Node):
	_active[proj.get_instance_id()] = proj

func unregister(proj: Node):
	var id = proj.get_instance_id()
	_active.erase(id)
	_results.erase(id)

# Returns this frame's already-computed flight result for a projectile, or
# null if the batch hasn't run yet this frame / the extension isn't loaded
# / this projectile wasn't registered in time (its very first tick, most
# likely - Projectile.gd falls back to its own single-call compute_step in
# that case).
func get_result(instance_id: int):
	return _results.get(instance_id, null)

func _physics_process(delta: float):
	_results.clear()
	_ensure_flight_rust()
	if not _flight_rasterizer or _active.is_empty():
		return

	var requests: Array = []
	var stale_ids: Array = []
	for id in _active:
		var proj = _active[id]
		if not is_instance_valid(proj):
			stale_ids.append(id)
			continue
		var req = proj._prepare_flight_request(delta)
		if req != null:
			requests.append(req)
	for id in stale_ids:
		_active.erase(id)

	if requests.is_empty():
		return

	var batch_results = _flight_rasterizer.compute_batch(requests)
	for res in batch_results:
		_results[int(res["instance_id"])] = res
