extends Node

# Phase 2 of the AI-tactics Rust-cutover plan (see
# C:\Users\Utility\.claude\plans\effervescent-drifting-kazoo.md) - batches
# the sight-check GATE (range test + line-of-sight) across every eligible
# enemy mech into one shared cadence instead of each mech independently
# polling its own staggered SIGHT_CHECK_HZ timer with its own per-mech
# PhysicsRayQueryParameters2D call. Writes has_sight_of_player/
# last_known_player_pos directly onto each mech, same "batcher writes state,
# Mech just reads it" shape as SeparationBatcher.gd's _cached_separation.
#
# The real Rust-batching value here comes entirely from Phase 1's already-
# built SolidGridBatcher.batch_line_of_sight (one grid-marched LOS query per
# in-range mech, in a single FFI call) - the distance-squared range gate
# itself is too cheap to be worth its own Rust port (same "batch size that
# matters" lesson packet_tax.rs proved: there's no meaningful compute in a
# single subtraction+compare to save), so it stays plain GDScript arithmetic
# here and this file has no companion .rs module of its own.
#
# NOT done here: the expanding-square search-PATTERN state machine
# (_execute_search/_advance_search_leg/_pick_frontier_point/etc. in
# SightAndSearch.gd) - that's a separate, larger follow-up with its own
# stateful-field/RNG-boundary risk profile, not bundled into this pass.
# SightAndSearch.gd's search logic is untouched and still runs per-mech,
# reading has_sight_of_player the same way it always did.
#
# Shared-cadence rationale: the old per-mech independent stagger
# (Mech._sight_check_timer = randf() * (1/SIGHT_CHECK_HZ) at spawn) existed
# specifically to avoid a thundering herd of simultaneous per-mech physics
# raycasts - once batched into one shared call per tick, that concern is
# gone, same reasoning SeparationBatcher.gd's own header already established
# for separation queries. Net behavior change: previously-staggered
# per-mech sight updates are now synchronized to one shared tick - a minor,
# disclosed approximation in the same tier as SeparationBatcher's
# point-distance tradeoff, not a correctness bug.

var _timer: float = 0.0

func _physics_process(delta: float):
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.0 / Mech.SIGHT_CHECK_HZ

	var blind_field = _get_active_player_jammer_field()

	var in_range_mechs: Array = []
	var queries: Array = []
	for m in EntityCache.get_group("enemy"):
		if not is_instance_valid(m) or m.is_boss:
			continue
		if not m.target or not is_instance_valid(m.target):
			continue

		if not m._search_pos_initialized:
			# Nothing better to go on yet - search near where it woke up
			# rather than freezing until the first lucky spot. Same
			# first-run initialization _update_player_sight always did.
			m.last_known_player_pos = m.global_position
			m._search_pos_initialized = true

		if blind_field and blind_field.is_point_inside(m.global_position):
			m.has_sight_of_player = false
			m.last_known_player_pos = blind_field.global_position
			blind_field.report_jam_contact(m.global_position)
			continue

		if not m.sight_and_search:
			m.sight_and_search = SightAndSearch.new(m)
		var sight_range = m.sight_and_search._effective_sight_range()
		var dist_sq = m.global_position.distance_squared_to(m.target.global_position)
		if dist_sq > sight_range * sight_range:
			m.has_sight_of_player = false
			continue

		in_range_mechs.append(m)
		queries.append({"from": m.global_position, "to": m.target.global_position})

	if queries.is_empty():
		return

	var _t_sight = Time.get_ticks_usec()
	var results = SolidGridBatcher.batch_line_of_sight(queries)
	Mech._perf_sight_usec += Time.get_ticks_usec() - _t_sight

	for i in range(in_range_mechs.size()):
		var m = in_range_mechs[i]
		if results[i]:
			m._gain_sight(m.target.global_position)
			# Per the user: "if any squad member sees me the whole squad
			# sees me. BUT other squads do not get that freebie." - only
			# broadcasts to THIS mech's own squad.members, never global.
			m.sight_and_search._share_sight_with_squad(m.target.global_position)
		else:
			m.has_sight_of_player = false

# Only ever one at a time in practice (one player, one equipped Jammer
# Module), but scans rather than assuming that - same as
# SightAndSearch._get_active_player_jammer_field, just resolved ONCE per
# batch tick here instead of once per mech (identical result for every
# mech asking, since it doesn't take a mech parameter).
func _get_active_player_jammer_field() -> Node:
	for f in EntityCache.get_group("jammer_field"):
		if is_instance_valid(f) and f.owner_is_player:
			return f
	return null
