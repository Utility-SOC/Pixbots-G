extends Node

# Task #33 ("batch homing-target search + vortex pull queries into Rust") -
# batches Projectile.gd's throttled per-projectile
# PhysicsShapeQueryParameters2D.intersect_shape() calls into Rust-batched
# calls per physics tick. Mirrors ProjectileBroadphase.gd's register-
# nothing/report-per-tick/resolve-once pattern. Real measured baseline
# (ProjectileTargetingPerfCheck.gd, 100 projectiles/60 targets): ~24-38us/
# call homing, ~19-20us/call vortex.
#
# HONEST MIXED RESULT after a same-process interleaved A/B
# (ProjectileTargetingABCheck.gd, 10 trials/config):
#   - Homing (_resolve_homing, via ProximityQueryRs.batch_find_best):
#     **shipped, real win, 23.9% faster**. Only ever needs the single
#     closest/furthest match, so batch_find_best does that reduction inside
#     Rust and only crosses the FFI boundary with one winner per query - no
#     nested hits array to marshal.
#   - Vortex (_resolve_vortex, via ProximityQueryRs.batch_radius_query):
#     **reverted, measured 46.2% SLOWER**, matching the packet_tax.rs/
#     Phase 4 precedent. Vortex pull must apply a force to EVERY candidate
#     within radius, so it can't avoid the full-hits-array marshalling cost
#     the way homing did - Projectile.gd calls _pull_nearby_items (the real
#     per-projectile physics query) directly again. request_vortex_pull/
#     _resolve_vortex stay in this file, unused, in case a future
#     full-frame-batch redesign changes the economics (same "keep the
#     reverted module" precedent as packet_tax.rs).
#
# Rust only ever does the SPATIAL "who's within radius" part - every
# per-target GAME RULE (is_player, vortex immunity/protection, apply_damage
# dispatch) and every Node mutation (pull_towards/velocity lerp) stays in
# Projectile.gd's _apply_vortex_pull_to_target, called back from here on
# each hit (on the vortex path, when it's ever re-enabled). Point-distance
# approximation (not shape overlap against real collision geometry), same
# accepted-tier tradeoff as SeparationBatcher.gd.
#
# One tick of latency is introduced for homing (a request made THIS tick
# resolves at the END of this same tick, via process_priority ordering
# below, so the projectile's OWN _physics_process earlier this same tick
# still reads the PREVIOUS cached target - the fresh result lands starting
# next tick) - negligible against the existing 0.1s throttle interval, same
# tier of soft-heuristic timing slop every other batcher this session
# already accepted.
#
# Lightning blink-hop target search (request_blink_target/_resolve_blink,
# added 2026-08-09) - confirmed real, severe hotspot via live playtest:
# every Lightning-ratio Projectile was independently linear-scanning the
# WHOLE enemy/player pool every BLINK_INTERVAL (0.11s) in what used to be
# Projectile._update_blink's own inline scan - O(shots x entities), 4-6fps
# whenever firing a Lightning-heavy weapon with entities on screen, fine
# with none. Reuses _batch_find_best_fallback (same single-winner shape
# proven by homing above), extended with a per-query "exclude" set for
# Projectile._handled_targets (already-hit targets on that projectile's
# own chain - homing never needed this, self-exclusion was enough).
# GDScript-only this pass, deliberately bypassing the Rust ProximityQueryRs
# path even when loaded (that signature doesn't support per-query
# exclusion yet - see _resolve_blink's own comment) - port only if a live
# playtest shows the GDScript fix alone doesn't recover enough headroom,
# same "prototype first, measure before porting" rule that already caught
# vortex's own revert above.

var _checked: bool = false
var _rasterizer = null

var _homing_requests: Dictionary = {} # projectile_id -> {proj, pos, min_dist, prefer_furthest}
var _vortex_requests: Dictionary = {} # projectile_id -> {proj, pos, radius, elapsed}
# Lightning blink-hop target search (confirmed real hotspot, live playtest:
# every Lightning-ratio projectile was independently linear-scanning the
# WHOLE enemy/player pool every 0.11s - see Projectile._update_blink's own
# comment). Same register-per-tick/resolve-once shape as the two above;
# "exclude" holds a direct reference to that projectile's own _handled_
# targets Dictionary (already-hit targets on its own chain) - see
# _batch_find_best_fallback's "exclude" field comment for why passing the
# live reference instead of a copy is safe here.
var _blink_requests: Dictionary = {} # projectile_id -> {proj, pos, max_dist, fired_by_player, exclude}

func _ready():
	process_priority = 998 # after projectiles' own _physics_process, same "resolve batched requests late" ordering as ProjectileBroadphase.gd (1000)/SeparationBatcher.gd

func _ensure_rust():
	if not _checked:
		_checked = true
		if ClassDB.class_exists("ProximityQueryRs"):
			_rasterizer = ClassDB.instantiate("ProximityQueryRs")

# Called by Projectile._request_homing_target - only the search-ENEMY case
# (player-fired homing/Vampiric shots, searching among potentially dozens
# of enemies) reaches here. The search-PLAYER case (enemy-fired Vampiric
# shots) only ever has one real candidate - too small a batch to be worth a
# Rust round-trip, same "don't batch trivial work" lesson Phase 4's
# BossBrain attempt confirmed - so it's resolved directly by the projectile
# itself instead.
func request_homing_target(proj: Node, min_dist: float, prefer_furthest: bool):
	_homing_requests[proj.get_instance_id()] = {"proj": proj, "pos": proj.global_position, "min_dist": min_dist, "prefer_furthest": prefer_furthest}

func request_vortex_pull(proj: Node, radius: float, elapsed: float):
	_vortex_requests[proj.get_instance_id()] = {"proj": proj, "pos": proj.global_position, "radius": radius, "elapsed": elapsed}

func request_blink_target(proj: Node, max_dist: float, fired_by_player: bool, exclude: Dictionary):
	_blink_requests[proj.get_instance_id()] = {"proj": proj, "pos": proj.global_position, "max_dist": max_dist, "fired_by_player": fired_by_player, "exclude": exclude}

func _physics_process(_delta):
	_ensure_rust()
	_resolve_homing()
	_resolve_vortex()
	_resolve_blink()
	_homing_requests.clear()
	_vortex_requests.clear()
	_blink_requests.clear()

func _resolve_homing():
	if _homing_requests.is_empty():
		return

	var candidates: Array = []
	for m in EntityCache.get_group("enemy"):
		if is_instance_valid(m) and m.has_method("apply_damage"):
			candidates.append({"id": m.get_instance_id(), "pos": m.global_position})

	if candidates.is_empty():
		for id in _homing_requests:
			var proj = instance_from_id(id)
			if proj and is_instance_valid(proj):
				proj._cached_homing_target = null
		return

	var queries: Array = []
	for id in _homing_requests:
		var req = _homing_requests[id]
		queries.append({"id": id, "pos": req.pos, "radius": req.min_dist, "prefer_furthest": req.prefer_furthest})

	# batch_find_best, not batch_radius_query: homing only ever consumes
	# ONE result (closest or furthest), so returning every hit in a nested
	# per-query array is pure unnecessary FFI/marshalling overhead. A
	# same-process A/B (ProjectileTargetingABCheck.gd) caught this the hard
	# way - the full-hits-array version measured 103% SLOWER than the old
	# unbatched per-projectile physics queries, matching the packet_tax.rs
	# pattern exactly. batch_find_best does the closest/furthest reduction
	# INSIDE Rust and only ever crosses the FFI boundary with one winner
	# per query.
	var _t_homing = Time.get_ticks_usec()
	var results: Array
	if _rasterizer:
		results = _rasterizer.batch_find_best(queries, candidates)
	else:
		results = _batch_find_best_fallback(queries, candidates)
	Projectile._perf_homing_query_usec += Time.get_ticks_usec() - _t_homing

	for r in results:
		var id = int(r.id)
		var proj = instance_from_id(id)
		if not proj or not is_instance_valid(proj):
			continue
		if r.found:
			proj._cached_homing_target = instance_from_id(int(r.best_id))
		else:
			proj._cached_homing_target = null

func _resolve_vortex():
	if _vortex_requests.is_empty():
		return

	# Always pull Loot, Enemies, and Player - matches _pull_nearby_items'
	# collision_mask = 16 | 4 | 8 exactly, just sourced from EntityCache
	# groups instead of a physics-layer shape query.
	var candidates: Array = []
	for m in EntityCache.get_group("enemy"):
		if is_instance_valid(m):
			candidates.append({"id": m.get_instance_id(), "pos": m.global_position})
	for p in EntityCache.get_group("player"):
		if is_instance_valid(p):
			candidates.append({"id": p.get_instance_id(), "pos": p.global_position})
	for l in EntityCache.get_group("loot"):
		if is_instance_valid(l):
			candidates.append({"id": l.get_instance_id(), "pos": l.global_position})

	if candidates.is_empty():
		return

	var queries: Array = []
	for id in _vortex_requests:
		var req = _vortex_requests[id]
		queries.append({"id": id, "pos": req.pos, "radius": req.radius})

	var _t_vortex = Time.get_ticks_usec()
	var results: Array
	if _rasterizer:
		results = _rasterizer.batch_radius_query(queries, candidates)
	else:
		results = _batch_radius_query_fallback(queries, candidates)
	Projectile._perf_vortex_query_usec += Time.get_ticks_usec() - _t_vortex

	for r in results:
		var id = int(r.id)
		var proj = instance_from_id(id)
		if not proj or not is_instance_valid(proj):
			continue
		var req = _vortex_requests[id]
		for hit in r.hits:
			var target = instance_from_id(int(hit.id))
			if target and is_instance_valid(target):
				proj._apply_vortex_pull_to_target(target, req.elapsed)

# Splits pending blink requests by fired_by_player (a Lightning shot hunts
# the OPPOSITE side's pool - player-fired hunts enemies, enemy-fired hunts
# the player), builds each pool's candidate list once, resolves both
# through the grid-bucket fallback. Deliberately ALWAYS uses
# _batch_find_best_fallback directly, even when the Rust extension is
# loaded (unlike _resolve_homing/_resolve_vortex above) - per-query
# exclusion sets are a GDScript-only extension this pass (see this file's
# header and _batch_find_best_fallback's "exclude" comment); the Rust
# ProximityQueryRs.batch_find_best signature doesn't know about "exclude"
# and would silently ignore it, which would let a chain re-hit a target it
# already struck. Revisit only if a live playtest shows the GDScript fix
# alone doesn't recover enough headroom to justify porting.
func _resolve_blink():
	if _blink_requests.is_empty():
		return

	var enemy_queries: Array = []
	var player_queries: Array = []
	for id in _blink_requests:
		var req = _blink_requests[id]
		var q = {"id": id, "pos": req.pos, "radius": req.max_dist, "prefer_furthest": false, "exclude": req.exclude}
		if req.fired_by_player:
			enemy_queries.append(q)
		else:
			player_queries.append(q)

	var _t_blink = Time.get_ticks_usec()
	if not enemy_queries.is_empty():
		var enemy_candidates: Array = []
		for m in EntityCache.get_group("enemy"):
			if is_instance_valid(m) and not m.get("is_dead"):
				enemy_candidates.append({"id": m.get_instance_id(), "pos": m.global_position})
		_apply_blink_results(_batch_find_best_fallback(enemy_queries, enemy_candidates))
	if not player_queries.is_empty():
		var player_candidates: Array = []
		for p in EntityCache.get_group("player"):
			if is_instance_valid(p) and not p.get("is_dead"):
				player_candidates.append({"id": p.get_instance_id(), "pos": p.global_position})
		_apply_blink_results(_batch_find_best_fallback(player_queries, player_candidates))
	Projectile._perf_blink_query_usec += Time.get_ticks_usec() - _t_blink

func _apply_blink_results(results: Array):
	for r in results:
		var id = int(r.id)
		var proj = instance_from_id(id)
		if not proj or not is_instance_valid(proj):
			continue
		if r.found:
			proj._cached_blink_target = instance_from_id(int(r.best_id))
		else:
			proj._cached_blink_target = null

# Pure-GDScript reference implementation of
# ProximityQueryRs.batch_radius_query - the fallback contract every
# Rust-ported system in this codebase keeps (see
# SeparationBatcher._batch_compute_separation_fallback). Variable-radius
# aware (cell size from the query set's own median radius), same design as
# the Rust side, not a fixed 3x3 neighborhood.
func _batch_radius_query_fallback(queries: Array, candidates: Array) -> Array:
	var radii: Array = []
	for q in queries:
		radii.append(q.radius)
	radii.sort()
	var cell_size = max(32.0, radii[radii.size() / 2]) if not radii.is_empty() else 150.0

	var buckets: Dictionary = {} # cell key -> Array of candidate indices
	for i in range(candidates.size()):
		var key = _cell_key(candidates[i].pos, cell_size)
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(i)

	var out: Array = []
	for q in queries:
		var qcx = floori(q.pos.x / cell_size)
		var qcy = floori(q.pos.y / cell_size)
		var span = max(1, ceili(q.radius / cell_size))
		var hits: Array = []
		for dx in range(-span, span + 1):
			for dy in range(-span, span + 1):
				var key = "%d:%d" % [qcx + dx, qcy + dy]
				if not buckets.has(key):
					continue
				for i in buckets[key]:
					var c = candidates[i]
					if c.id == q.id:
						continue
					var d = q.pos.distance_to(c.pos)
					if d <= q.radius:
						hits.append({"id": c.id, "dist": d})
		hits.sort_custom(func(a, b): return a.dist < b.dist)
		out.append({"id": q.id, "hits": hits})
	return out

func _cell_key(pos: Vector2, cell_size: float) -> String:
	return "%d:%d" % [floori(pos.x / cell_size), floori(pos.y / cell_size)]

# Pure-GDScript reference implementation of ProximityQueryRs.batch_find_best
# - same grid-bucket approach as _batch_radius_query_fallback, but tracks
# only the running best (closest or furthest) candidate per query instead
# of collecting every hit, matching the Rust side's own no-hits-array
# design.
#
# "exclude" (optional per-query Dictionary, id -> true, same as-a-set shape
# Projectile._handled_targets already uses) - added for Lightning blink-hop
# (see request_blink_target/_resolve_blink), which needs to skip specific
# already-hit targets per query, not just self. Homing's own queries never
# set this field, so q.has("exclude") is false for them and this is a
# complete no-op on that path - byte-for-byte unchanged behavior there.
func _batch_find_best_fallback(queries: Array, candidates: Array) -> Array:
	var radii: Array = []
	for q in queries:
		radii.append(q.radius)
	radii.sort()
	var cell_size = max(32.0, radii[radii.size() / 2]) if not radii.is_empty() else 150.0

	var buckets: Dictionary = {}
	for i in range(candidates.size()):
		var key = _cell_key(candidates[i].pos, cell_size)
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(i)

	var out: Array = []
	for q in queries:
		var qcx = floori(q.pos.x / cell_size)
		var qcy = floori(q.pos.y / cell_size)
		var span = max(1, ceili(q.radius / cell_size))
		var prefer_furthest = q.get("prefer_furthest", false)
		var best_id = -1
		var best_dist = 0.0
		var found = false
		var exclude = q.get("exclude", null)
		for dx in range(-span, span + 1):
			for dy in range(-span, span + 1):
				var key = "%d:%d" % [qcx + dx, qcy + dy]
				if not buckets.has(key):
					continue
				for i in buckets[key]:
					var c = candidates[i]
					if c.id == q.id:
						continue
					if exclude != null and exclude.has(c.id):
						continue
					var d = q.pos.distance_to(c.pos)
					if d > q.radius:
						continue
					if not found or (prefer_furthest and d > best_dist) or (not prefer_furthest and d < best_dist):
						found = true
						best_id = c.id
						best_dist = d
		if found:
			out.append({"id": q.id, "found": true, "best_id": best_id, "dist": best_dist})
		else:
			out.append({"id": q.id, "found": false})
	return out
