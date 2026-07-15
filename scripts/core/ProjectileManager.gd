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

# --- Saturation tiers (playtest: "when this much is on the screen it
# cripples performance (1-3 fps)") -----------------------------------------
# Since every live projectile registers here, _active.size() is a free,
# always-current census of how busy the screen is. Three graduated responses
# key off it, all of which relax back to zero cost the moment the count
# drops (nothing latches):
#   1. lite_visuals(): above ~90 live shots, newly built projectiles skip
#      their per-shot particle systems / helix orbiters / trail Line2Ds and
#      keep just the core synergy shape. At that density the ornaments are
#      unreadable overdraw anyway.
#   2. consolidation_factor(): above the tiers below, weapon mounts merge
#      every K volleys into ONE projectile carrying the combined packet
#      (see HexTile._fire_combined_projectile) - total damage output is
#      preserved, the shot gets bigger (magnitude already drives visual
#      scale and hitbox), but the Area2D/broadphase population stops
#      growing. This is the fix for the actual bottleneck (physics pairs +
#      per-node dispatch), not just the rendering.
#   3. request_floater(): global budget for damage/CRIT popups so a bullet
#      storm doesn't also spawn hundreds of tweened Labels.
const LITE_VISUALS_THRESHOLD = 90
const CONSOLIDATE_TIERS = [[350, 8], [240, 4], [150, 2]] # [live count, merge-K]

func live_count() -> int:
	return _active.size()

func lite_visuals() -> bool:
	return _active.size() >= LITE_VISUALS_THRESHOLD

func consolidation_factor() -> int:
	var n = _active.size()
	for tier in CONSOLIDATE_TIERS:
		if n >= tier[0]:
			return tier[1]
	return 1

const FLOATER_WINDOW_SEC = 0.5
const FLOATER_CAP_CRIT = 14   # crits get the full budget...
const FLOATER_CAP_NORMAL = 7  # ...ordinary numbers only the first half
var _floater_window_start: float = 0.0
var _floaters_this_window: int = 0

func request_floater(is_crit: bool) -> bool:
	var now = Time.get_ticks_msec() / 1000.0
	if now - _floater_window_start > FLOATER_WINDOW_SEC:
		_floater_window_start = now
		_floaters_this_window = 0
	if _floaters_this_window >= (FLOATER_CAP_CRIT if is_crit else FLOATER_CAP_NORMAL):
		return false
	_floaters_this_window += 1
	return true

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
