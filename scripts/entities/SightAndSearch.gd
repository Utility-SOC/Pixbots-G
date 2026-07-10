class_name SightAndSearch
extends RefCounted

# Player-detection and search-pattern AI for non-boss, non-player mechs -
# split out of Mech.gd (see PlayerController/BossBrain/StatusEffectRunner
# for the established composed-RefCounted-helper pattern this follows).
# All state (has_sight_of_player, last_known_player_pos, the _search_*
# fields, and the SIGHT_*/SEARCH_* tuning constants) stays on Mech itself -
# only the BEHAVIOR that reads/writes it moved here, same as the other
# composed helpers keep their state on `mech` rather than copying it.
# Lazily constructed the first time a non-boss mech needs it (see
# Mech._update_player_sight's wrapper), same lazy pattern as boss_brain/
# player_controller.
#
# _gain_sight stays directly on Mech (not moved) - it's called duck-typed
# on OTHER mech instances via mate._gain_sight(...) in
# _share_sight_with_squad below, so it has to be reachable as a plain
# Mech-level method regardless. _update_player_sight keeps a thin wrapper
# on Mech too, since existing debug scripts call enemy._update_player_
# sight(...) directly.

var mech: Mech

# Stuck detection cadence for _execute_search: how often progress is
# sampled, and how far the mech must have actually moved between samples
# for the current leg to be considered making progress. At 0.85x of ~200+
# move speed a healthy leg covers 150px+ per interval - 30px means it's
# grinding an obstacle.
const SEARCH_STUCK_INTERVAL = 0.9
const SEARCH_STUCK_MIN_PROGRESS = 30.0

func _init(p_mech: Mech):
	mech = p_mech

func _effective_sight_range() -> float:
	return mech.SIGHT_RANGE * (mech.SCOUT_SIGHT_MULT if mech.combat_role == "scout" else 1.0)

func _effective_search_radius() -> float:
	return mech.SEARCH_WANDER_RADIUS * (mech.SCOUT_SEARCH_MULT if mech.combat_role == "scout" else 1.0)

# Range + line-of-sight gate. Only updates has_sight_of_player/
# last_known_player_pos - Mech._execute_ai_tactics decides what to actually
# DO with that state (chase vs. search).
func _update_player_sight(delta: float):
	if not mech._search_pos_initialized:
		# Nothing better to go on yet - search near where it woke up rather
		# than freezing until the first lucky spot.
		mech.last_known_player_pos = mech.global_position
		mech._search_pos_initialized = true

	mech._sight_check_timer -= delta
	if mech._sight_check_timer > 0.0:
		return
	mech._sight_check_timer = 1.0 / mech.SIGHT_CHECK_HZ

	# Blind: standing inside the player's own JammerField denies precise
	# targeting entirely, regardless of line of sight - the "snipe from
	# range or go blind" pressure. Continuously re-evaluated on this same
	# throttled check, no separate timer.
	var blind_field = _get_active_player_jammer_field()
	if blind_field and blind_field.is_point_inside(mech.global_position):
		mech.has_sight_of_player = false
		mech.last_known_player_pos = blind_field.global_position
		blind_field.report_jam_contact(mech.global_position)
		return

	var dist = mech.global_position.distance_to(mech.target.global_position)
	var visible = false
	if dist <= _effective_sight_range():
		var space_state = mech.get_world_2d().direct_space_state
		# Collision mask 1 = World/obstacles only (same convention as the
		# strafe-into-walls and boss-retreat-clearance raycasts elsewhere in
		# Mech.gd) - other mechs don't block sight, only terrain/obstacles.
		var query = PhysicsRayQueryParameters2D.create(mech.global_position, mech.target.global_position, 1)
		visible = space_state.intersect_ray(query).is_empty()

	if visible:
		mech._gain_sight(mech.target.global_position)
		# Per Natalia: "if any squad member sees me the whole squad sees
		# me. BUT other squads do not get that freebie." - only broadcasts
		# to THIS mech's own squad.members, never anything global.
		_share_sight_with_squad(mech.target.global_position)
	else:
		mech.has_sight_of_player = false

# Only ever one at a time in practice (one player, one equipped Jammer
# Module), but scans rather than assuming that in case a future mode lets
# the player field multiple sources.
func _get_active_player_jammer_field() -> Node:
	for f in EntityCache.get_group("jammer_field"):
		if is_instance_valid(f) and f.owner_is_player:
			return f
	return null

func _share_sight_with_squad(player_pos: Vector2):
	if not mech.squad or not is_instance_valid(mech.squad):
		return
	for mate in mech.squad.members:
		if mate == mech or not is_instance_valid(mate):
			continue
		if mate.has_method("_gain_sight"):
			mate._gain_sight(player_pos)

# What a non-boss mech does while it doesn't have sight of the player -
# always ACTIVELY searching (no idle/give-up state - see the block comment
# above _SEARCH_HEADINGS on Mech.gd). Scouts run a frontier-exploration
# search (see _execute_scout_search); everyone else runs the expanding-
# square pattern. No shooting while searching - it doesn't know where you
# are, it shouldn't be able to hit you.
func _execute_search(delta: float):
	if mech.squad and is_instance_valid(mech.squad):
		# "Everyone in the squad knows where everyone in the squad has
		# looked" - mark the ground actually under us as covered. This is a
		# deliberately cheap stand-in for a full LOS sweep (a real
		# multi-directional raycast fan per mech per tick would be the
		# "more precise" version, but at wave-scale enemy counts that's
		# exactly the kind of per-tick physics query this session already
		# found and fixed for projectiles/homing) - standing somewhere and
		# not immediately spotting the player from here still means this
		# immediate area has been looked at.
		mech.squad.mark_explored(mech.global_position)

	if mech.combat_role == "scout":
		_execute_scout_search(delta)
		return

	# Redatum on fresh INTEL (a sighting moved last_known meaningfully), not
	# on datum drift - the frontier escalation in _advance_search_leg moves
	# the datum away from last_known on purpose, and comparing datum vs
	# last_known here would snap the pattern straight back to the stale spot.
	if not mech._search_pattern_initialized or mech._search_intel_pos.distance_to(mech.last_known_player_pos) > mech.SEARCH_REDATUM_DIST:
		mech._search_intel_pos = mech.last_known_player_pos
		_start_search_pattern(mech.last_known_player_pos)

	if mech.global_position.distance_to(mech._search_leg_target) < 24.0:
		_advance_search_leg()

	# Stuck detection: straight-line legs + move_and_slide means an obstacle
	# pocket (dense Forest/Volcano terrain) can leave a searcher grinding a
	# wall face indefinitely - the leg target sits behind the rock and the
	# proximity check above never trips. If we haven't made real progress in
	# the last interval, abandon the leg instead of pushing the wall.
	mech._search_stuck_timer -= delta
	if mech._search_stuck_timer <= 0.0:
		if mech._search_progress_pos != Vector2.INF and mech.global_position.distance_to(mech._search_progress_pos) < SEARCH_STUCK_MIN_PROGRESS:
			_advance_search_leg()
		mech._search_stuck_timer = SEARCH_STUCK_INTERVAL
		mech._search_progress_pos = mech.global_position

	# Skip legs the squad has already cleared recently rather than
	# dutifully re-walking ground a squadmate just covered - bounded
	# iteration count so a small/crowded search area can't loop forever.
	var skip_guard = 0
	while mech.squad and is_instance_valid(mech.squad) and mech.squad.is_recently_explored(mech._search_leg_target) and skip_guard < 6:
		_advance_search_leg()
		skip_guard += 1

	var search_dir = mech.global_position.direction_to(mech._search_leg_target)
	# More committed than the old passive wander (0.6x) - "more aggressive"
	# per Natalia, though still a notch under a full chase (1.0x) since it's
	# still just a hunch, not a confirmed sighting.
	mech.velocity = search_dir * mech.current_move_speed * mech.speed_modifier * 0.85

# (Re)centers the expanding-square pattern on `datum` - called on first
# search and again whenever a fresh sighting moves the datum meaningfully
# ("redatum-ing", same term SAR crews use for this). Starting heading is
# randomized per mech so squadmates searching the same datum fan out in
# different initial directions instead of all walking the same spiral
# single-file.
func _start_search_pattern(datum: Vector2):
	mech._search_datum = datum
	mech._search_leg_len_units = 1
	mech._search_legs_done_at_this_len = 0
	mech._search_heading_idx = randi() % 4
	mech._search_leg_start = mech.global_position
	mech._search_pattern_initialized = true
	mech._search_leg_target = _next_leg_target()

func _next_leg_target() -> Vector2:
	var heading = mech._SEARCH_HEADINGS[mech._search_heading_idx % 4]
	var length = mech._search_leg_len_units * mech.SEARCH_LEG_UNIT * (mech.SCOUT_SEARCH_MULT if mech.combat_role == "scout" else 1.0)
	var target = mech._search_leg_start + heading * length

	# Line-of-sight/obstacle awareness: don't commit to a leg that just
	# marches straight into a wall - try rotating through the other 3
	# headings first (same mask-1/Env-only raycast convention as the
	# player-sight check above) before giving up and using it anyway.
	var space_state = mech.get_world_2d().direct_space_state
	var attempts = 0
	while attempts < 3:
		var query = PhysicsRayQueryParameters2D.create(mech._search_leg_start, target, 1)
		if space_state.intersect_ray(query).is_empty():
			break
		attempts += 1
		heading = mech._SEARCH_HEADINGS[(mech._search_heading_idx + attempts) % 4]
		target = mech._search_leg_start + heading * length

	return target

# Advances to the next leg of the expanding square: turn 90 degrees, and
# every 2 legs the leg length grows by one unit (the classic 1,1,2,2,3,3...
# ES pattern). Past SEARCH_MAX_LEG_UNITS the whole pattern completed with
# no sighting - the player is NOT here. The old behavior recentered on the
# same datum and paced the exact same (already-searched) square forever,
# which is the "search AI feels slow/dumb" play report in a nutshell: a
# squad that lost you at wave start would haunt one patch of map all round.
# Now the mech escalates: it picks a frontier point (favoring ground its
# squad hasn't covered recently) as the NEW datum and marches the pattern
# over there - searchers migrate across the map hunting you down instead of
# re-sweeping known-empty ground.
func _advance_search_leg():
	mech._search_leg_start = mech._search_leg_target
	mech._search_heading_idx = (mech._search_heading_idx + 1) % 4
	mech._search_legs_done_at_this_len += 1
	if mech._search_legs_done_at_this_len >= 2:
		mech._search_legs_done_at_this_len = 0
		mech._search_leg_len_units += 1
	if mech._search_leg_len_units > mech.SEARCH_MAX_LEG_UNITS:
		_start_search_pattern(_pick_frontier_point(ESCALATE_HOP_MIN, ESCALATE_HOP_MAX))
		return
	mech._search_leg_target = _next_leg_target()

# Scouts don't hunt for one specific last-known spot - per Natalia, "scouts
# optimize for seeing unseen map": push outward into whichever nearby
# direction the squad HASN'T already marked explored, continually
# expanding the squad's collective vision instead of converging on a single
# point. Genuine reconnaissance rather than a wider version of the same
# datum search everyone else runs.
func _execute_scout_search(delta: float):
	mech._search_waypoint_timer -= delta
	if mech._search_waypoint_timer <= 0.0 or mech.global_position.distance_to(mech._search_waypoint) < 40.0:
		mech._search_waypoint_timer = mech.SEARCH_WAYPOINT_INTERVAL * 1.5
		mech._search_waypoint = _pick_frontier_point()

	var search_dir = mech.global_position.direction_to(mech._search_waypoint)
	mech.velocity = search_dir * mech.current_move_speed * mech.speed_modifier # scouts commit fully - no caution discount

# How far a non-scout hops when its expanding square exhausts (see
# _advance_search_leg) - most of a completed square's ~880px footprint, so
# consecutive patterns tile fresh ground with a little overlap.
const ESCALATE_HOP_MIN = 500.0
const ESCALATE_HOP_MAX = 900.0

# Cheap frontier-exploration heuristic: sample a ring of candidate points
# around the mech, favor ones further out, and heavily discount any the
# squad has already covered recently - a bounded-cost stand-in for a full
# unexplored-region search that still reliably pushes toward genuinely new
# ground instead of re-treading it. Scouts use the default (their wander
# radius); exhausted square-searchers pass an explicit hop range.
func _pick_frontier_point(min_dist: float = 250.0, max_dist: float = -1.0) -> Vector2:
	if max_dist < 0.0:
		max_dist = _effective_search_radius()
	var best = Vector2.ZERO
	var best_score = -1.0
	for i in range(8):
		var ang = (TAU / 8.0) * i + randf_range(-0.3, 0.3)
		var dist = randf_range(min_dist, max_dist)
		var candidate = mech.global_position + Vector2(cos(ang), sin(ang)) * dist
		var score = dist
		if mech.squad and is_instance_valid(mech.squad) and mech.squad.is_recently_explored(candidate):
			score *= 0.15
		if score > best_score:
			best_score = score
			best = candidate
	if best == Vector2.ZERO:
		best = mech.global_position + Vector2(1, 0).rotated(randf() * TAU) * 300.0
	return best
