extends Node

# Autoload. Per-tick batched replacement for Projectile.gd's old Area2D-based
# hit detection (one live physics-server body per projectile, tracked/
# updated by the engine every tick regardless of proximity to anything) - see
# rust_ext/src/projectile_broadphase.rs for the actual math and
# C:\Users\Utility\.claude\plans\effervescent-exploring-pine.md for the full
# design. Mirrors ProjectileManager.gd's existing flight-batch pattern:
# projectiles register once, report per-tick data, one batched call resolves
# everyone at once instead of N separate physics-server queries.
#
# Sequencing: process_priority is a large POSITIVE number (opposite of
# ProjectileManager's -1000, which runs FIRST) so this runs LAST among
# physics-processing nodes each tick - after every registered projectile's
# own _physics_process has already applied this tick's movement and reported
# it via report_movement().
#
# Gameplay logic for what a hit actually DOES lives entirely in
# Projectile._handle_hit() and is NOT touched by this file - this module's
# only job is "who overlapped whom this tick," dispatched straight into that
# existing, unchanged function.

var _registered: Dictionary = {}   # instance_id (int) -> Projectile
var _reports: Dictionary = {}      # instance_id (int) -> {prev, curr, radius, mask}

var _checked: bool = false
var _rasterizer = null

func _ready():
	process_priority = 1000

func register(proj: Node):
	_registered[proj.get_instance_id()] = proj

func unregister(proj: Node):
	var id = proj.get_instance_id()
	_registered.erase(id)
	_reports.erase(id)

# Called by Projectile._physics_process_body/_physics_process_mine right
# after applying this tick's movement. Replaces the old
# TUNNEL_RISK_MOVE_THRESHOLD-gated call to _sweep_for_tunneled_hits - this
# runs unconditionally every tick now, since the cost moved from "expensive
# per-projectile physics-server shape query" to "cheap batched Rust math",
# so the old speed-gated optimization has no reason to exist anymore (and
# tunneling protection is strictly better as a result: every projectile gets
# a swept-segment check every tick, not just ones that moved far enough to
# trip the old threshold).
func report_movement(proj: Node, prev_pos: Vector2, curr_pos: Vector2, radius: float):
	_reports[proj.get_instance_id()] = {
		"prev": prev_pos, "curr": curr_pos, "radius": radius, "mask": proj.collision_mask
	}

func _ensure_rust():
	if not _checked:
		_checked = true
		if ClassDB.class_exists("ProjectileBroadphaseRs"):
			_rasterizer = ClassDB.instantiate("ProjectileBroadphaseRs")

func _physics_process(_delta):
	_ensure_rust()
	if _reports.is_empty():
		return

	var targets: Array = []
	for h in EntityCache.get_group("part_hitbox"):
		if not is_instance_valid(h):
			continue
		targets.append({"id": h.get_instance_id(), "pos": h.global_position, "radius": h.broadphase_radius, "layer": h.collision_layer})
	for o in EntityCache.get_group("obstacle"):
		if not is_instance_valid(o):
			continue
		targets.append({"id": o.get_instance_id(), "pos": o.global_position, "radius": o.broadphase_radius, "layer": o.collision_layer})

	var projectiles: Array = []
	for id in _reports:
		var r = _reports[id]
		projectiles.append({"id": id, "prev": r["prev"], "curr": r["curr"], "radius": r["radius"], "mask": r["mask"]})
	_reports.clear()

	if targets.is_empty() or projectiles.is_empty():
		return

	var pairs: Array
	if _rasterizer:
		pairs = _rasterizer.query_hits(targets, projectiles)
	else:
		pairs = _query_hits_fallback(targets, projectiles)

	for pair in pairs:
		var proj = instance_from_id(int(pair["projectile_id"]))
		if proj == null or not is_instance_valid(proj) or proj.is_queued_for_deletion():
			continue
		var target = instance_from_id(int(pair["target_id"]))
		if target == null or not is_instance_valid(target):
			continue
		proj._handle_hit(target)

# Pure-GDScript reference implementation - the fallback contract every
# Rust-ported system in this codebase keeps (see ProjectileFlight/
# _ensure_flight_rust): the DLL must never become a hard dependency. Slower
# than the Rust path, but correctness-equivalent - this is also the ground
# truth ProjectileBroadphaseParityCheck.gd diffs the Rust path against.
func _query_hits_fallback(targets: Array, projectiles: Array) -> Array:
	var pairs: Array = []
	for p in projectiles:
		for t in targets:
			if (int(t["layer"]) & int(p["mask"])) == 0:
				continue
			if _segment_circle_hit(p["prev"], p["curr"], t["pos"], float(t["radius"]) + float(p["radius"])):
				pairs.append({"projectile_id": p["id"], "target_id": t["id"]})
	return pairs

func _segment_circle_hit(a: Vector2, b: Vector2, center: Vector2, combined_radius: float) -> bool:
	var ab = b - a
	var len_sq = ab.length_squared()
	var closest: Vector2
	if len_sq <= 1e-9:
		closest = a
	else:
		var t = clamp((center - a).dot(ab) / len_sq, 0.0, 1.0)
		closest = a + ab * t
	return center.distance_to(closest) <= combined_radius
