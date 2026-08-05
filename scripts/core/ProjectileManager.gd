extends Node

# Batches the per-frame flight-math dispatch for every live projectile into
# ONE Rust call instead of one call per projectile - see ProjectileFlight.
# compute_batch_flat (rust_ext/src/projectile_flight.rs) for the actual math.
# Godot's per-call FFI dispatch overhead, not the trig itself, is what
# scaled badly once combat got busy (100+ live shots), so this is a
# dispatch-count fix, not a math optimization. (2026-08-03: the batched
# CALL COUNT fix alone wasn't the whole story either - at 500 live
# projectiles the marshalling cost of the batch's PAYLOAD, an Array of 500
# nested Dictionaries, was itself ~1.94ms/tick. Rewritten to flat
# PackedInt64Array/PackedFloat64Array payloads - see compute_batch_flat's
# and Projectile._prepare_flight_request_flat's comments, and Status.md's
# physics-tick-at-scale investigation - dropped that to ~0.4ms/tick.)
#
# Sequencing: this node's process_priority is set very low (runs before
# every other physics-processing node this same frame - see _ready).
# Each frame: this manager asks every registered projectile to prepare its
# own request (Projectile._prepare_flight_request_flat - the throttled
# homing-target search and ratio/steering setup that MUST run per-
# projectile, since a physics query can't be batched into the pure-math
# Rust call), collects them all into flat arrays, makes ONE batched Rust
# call, and stashes the results (reconstructed into per-projectile
# Dictionaries here in GDScript, matched back to their Projectile by
# array POSITION, not by an echoed instance_id - see _physics_process).
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
#   1. lite_visuals() / should_show_full_ornament(): above ~90 live shots,
#      newly built projectiles thin their per-shot particle systems / helix
#      orbiters / trail Line2Ds at a per-synergy rate (see
#      should_show_full_ornament's own comment) rather than dropping them
#      all at once - at that density the ornaments are unreadable overdraw
#      anyway, but a stable partial rate reads as a deliberate style rather
#      than a flicker.
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
# Tightened (playtest video: still "a really low framerate" under heavy
# fire even with the original tiers active) - two changes: consolidation
# now starts at 90 live shots instead of 150 (catches the climb earlier,
# before the physics-server broad-phase cost has already piled up), and a
# new top tier (500+, merge every 16) exists for genuinely extreme counts
# that the old ceiling (350 -> merge every 8) didn't cap hard enough. This
# is the real lever until the full Rust broadphase port (eliminating
# Area2D per projectile entirely) lands - see ProjectileManager's own
# header for why that's the actual architectural fix.
const CONSOLIDATE_TIERS = [[500, 16], [350, 8], [240, 5], [150, 3], [90, 2]] # [live count, merge-K]

func live_count() -> int:
	return _active.size()

func lite_visuals() -> bool:
	return _active.size() >= LITE_VISUALS_THRESHOLD

# Per-synergy ornament thinning (playtest: "could you thin the types of
# particles rather than fully trimming some? half as many kinetic showing
# up on screen, and a quarter of the vortex - showing up consistently").
# Once the overall saturation gate (lite_visuals) trips, a shot's dominant
# synergy no longer gets a flat all-or-nothing ornament - each synergy has
# its own "1 in N shots gets the full ornament" rate, decided by a stable
# ROTATING counter per synergy (not a per-shot coin flip), so the ratio
# reads as a consistent, deliberate pattern rather than random flicker.
# Below the saturation threshold, every shot always gets the full ornament
# (unchanged prior behavior) - this only kicks in once things are already
# busy enough that ProjectileManager's own header docs call "unreadable
# overdraw anyway". Synergies not listed default to
# ORNAMENT_DEFAULT_FULL_RATE; a synergy whose current visual has no lite/
# full distinction at all (e.g. Kinetic's plain polygon) is unaffected
# either way - the rate just never gets consulted for it yet.
const ORNAMENT_FULL_RATE = {
	EnergyPacket.SynergyType.VORTEX: 4,   # 1 in 4 gets the full spiral/helix orbs
	EnergyPacket.SynergyType.FIRE: 2,     # 1 in 2 gets the full particle trail
	EnergyPacket.SynergyType.KINETIC: 2,  # 1 in 2 gets the full speed trail
}
const ORNAMENT_DEFAULT_FULL_RATE = 2
var _ornament_counters: Dictionary = {} # synergy_type (int) -> running count

func should_show_full_ornament(synergy_type: int) -> bool:
	if not lite_visuals():
		return true
	var rate = ORNAMENT_FULL_RATE.get(synergy_type, ORNAMENT_DEFAULT_FULL_RATE)
	var count = _ornament_counters.get(synergy_type, 0) + 1
	_ornament_counters[synergy_type] = count
	return count % rate == 0

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
	# Must survive get_tree().paused == true, same as AudioManager/ProceduralMusic/
	# FpsCounter (see their own _ready()) - the Garage's Test Range deliberately
	# keeps its whole subtree PROCESS_MODE_ALWAYS so it can live-fire while the
	# tree is paused, but every one of those projectiles still registers here.
	# Without this, this batch dispatch simply never runs while the Garage is
	# open, and every live projectile falls back to its own individual
	# per-frame Rust FFI call for its whole lifetime - exactly the per-call
	# overhead this batching exists to avoid (see module header).
	process_mode = Node.PROCESS_MODE_ALWAYS

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

# Perf instrumentation (2026-08-03, ongoing physics-tick-at-scale
# investigation - see ProjectilePhysicsBreakdownCheck.gd/Status.md).
# Splits this function's two real costs: the GDScript-side collection loop
# (500+ individual _prepare_flight_request() calls, each building a nested
# Dictionary) vs. the single Rust FFI call marshalling that whole array
# across the boundary. Same pattern as Projectile._perf_physics_usec -
# static, accumulated, meant to be read+reset by a diagnostic/FpsCounter,
# not per-call overhead-sensitive.
static var _perf_collect_usec: int = 0
static var _perf_rust_call_usec: int = 0

const RESPONSE_STRIDE = 12 # MUST match rust_ext/src/projectile_flight.rs's contract exactly

func _physics_process(delta: float):
	_results.clear()
	_ensure_flight_rust()
	if not _flight_rasterizer or _active.is_empty():
		return

	# Flat-array collection (2026-08-03 rewrite, see module comment + Status.md's
	# physics-tick-at-scale investigation): projectiles_in_order[i] is the
	# Projectile this loop is currently building request i for -
	# instance_ids/requests_flat/the eventual results_flat are all
	# positionally aligned to this same array, so results get matched back
	# by INDEX, not by re-parsing an echoed instance_id out of Rust.
	var _t_collect = Time.get_ticks_usec()
	var projectiles_in_order: Array = []
	var instance_ids := PackedInt64Array()
	var requests_flat := PackedFloat64Array()
	var stale_ids: Array = []
	for id in _active:
		var proj = _active[id]
		if not is_instance_valid(proj):
			stale_ids.append(id)
			continue
		projectiles_in_order.append(proj)
		instance_ids.append(id)
		requests_flat.append_array(proj._prepare_flight_request_flat(delta))
	for id in stale_ids:
		_active.erase(id)
	_perf_collect_usec += Time.get_ticks_usec() - _t_collect

	if projectiles_in_order.is_empty():
		return

	var _t_rust = Time.get_ticks_usec()
	var results_flat: PackedFloat64Array = _flight_rasterizer.compute_batch_flat(instance_ids, requests_flat)
	for i in projectiles_in_order.size():
		var base = i * RESPONSE_STRIDE
		_results[instance_ids[i]] = {
			"direction": Vector2(results_flat[base], results_flat[base + 1]),
			"velocity": Vector2(results_flat[base + 2], results_flat[base + 3]),
			"visual_offset": Vector2(results_flat[base + 4], results_flat[base + 5]),
			"current_speed": results_flat[base + 6],
			"gravity_velocity": Vector2(results_flat[base + 7], results_flat[base + 8]),
			"lightning_segment_index": int(results_flat[base + 9]),
			"lightning_prev_offset": results_flat[base + 10],
			"lightning_target_offset": results_flat[base + 11],
		}
	_perf_rust_call_usec += Time.get_ticks_usec() - _t_rust
