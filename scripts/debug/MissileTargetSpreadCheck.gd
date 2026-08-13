extends Node

# Regression check for Missile Rack target-spreading (user, 2026-08-13:
# "it'd be cool if the missiles were a little cleverer - I'd like to avoid
# 20 missiles hitting one target"). Both pick rules (_find_furthest_target_
# in_range/_find_most_powerful_target_in_range) were otherwise fully
# deterministic - a build with several Missile Racks, or several missile-
# armed mechs on one side, independently re-ran the exact same rule against
# the exact same candidate pool and always converged on the identical
# target. Fix: a shared (static, not per-tile) "recently targeted" registry
# that multiplicatively demotes (never excludes) a just-picked candidate's
# score for RECENT_TARGET_WINDOW_MS - see MissileRackTile._recent_targets'
# own header comment for the full reasoning.
#
# SAFETY: mirrors MissileNukeTierCheck.gd's established safe pattern -
# `components = {}` on every Mech before add_child() so Mech._ready() never
# runs build_loadout_for_role(). No SquadDirector, real or fake, is ever
# constructed here.
#
# EntityCache gotcha (see OrbitingProjectileCheck.gd's own header comment
# for the same warning): EntityCache.get_group() caches its snapshot per
# engine frame stamp, which never advances mid-_ready(). Every mech this
# check will ever need is therefore created UPFRONT, before the first
# _find_*_target_in_range call locks that snapshot in - later "sections"
# stay isolated from each other via non-overlapping [min_range, max_range]
# windows (a pure numeric filter, unaffected by cache staleness) or by
# mutating an EXISTING mech's fields (max_hp) rather than adding/removing
# candidate nodes, never by freeing/re-adding mechs mid-function.

const MissileRackTileScript = preload("res://scripts/tiles/MissileRackTile.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0
var world: Node = null

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _make_mech(pos: Vector2, p_max_hp: float) -> Node:
	var m = MechScript.new()
	m.is_player = false
	m.components = {}
	m.max_hp = p_max_hp
	m.hp = p_max_hp
	world.add_child(m)
	m.global_position = pos
	return m

func _ready():
	world = Node.new()
	add_child(world)
	var tile = MissileRackTileScript.new()
	var tile_b = MissileRackTileScript.new()
	var muzzle = Vector2.ZERO

	# Every mech needed by every section below, created upfront (see this
	# file's own EntityCache gotcha comment) - each section's own distinct
	# [min_range, max_range] window is what actually isolates it.
	var near = _make_mech(Vector2(1000, 0), 500.0)   # Furthest/Most-Powerful spread section: window [900, 3500]
	var mid = _make_mech(Vector2(2000, 0), 500.0)
	var far = _make_mech(Vector2(3000, 0), 500.0)
	var lone = _make_mech(Vector2(600, 0), 500.0)     # lone-candidate section: window [100, 800]
	var target_a = _make_mech(Vector2(8000, 0), 500.0) # expiry section: window [5500, 8500]
	var target_b = _make_mech(Vector2(6000, 0), 500.0)
	var only_target = _make_mech(Vector2(9500, 0), 500.0) # shared-registry section: window [8700, 10000]
	var other_target = _make_mech(Vector2(9000, 0), 500.0)

	# --- Furthest mode: a genuinely-furthest target gets demoted after
	# being picked, letting the next-furthest one win instead -------------
	MissileRackTileScript._recent_targets.clear()
	# min_r1 starts at 900 (not 100) specifically to exclude `lone` (dist
	# 600, created below for its own section) from this window - it's
	# otherwise a valid candidate at any range starting below 600.
	var min_r1 = 900.0
	var max_r1 = 3500.0

	var pick1 = tile._find_furthest_target_in_range(muzzle, true, min_r1, max_r1)
	_check("first pick is the genuinely furthest target (no history yet)",
		pick1 == far)

	var pick2 = tile._find_furthest_target_in_range(muzzle, true, min_r1, max_r1)
	_check("second pick avoids the just-targeted furthest target, spreading to the next-furthest instead",
		pick2 == mid)

	var pick3 = tile._find_furthest_target_in_range(muzzle, true, min_r1, max_r1)
	_check("third pick spreads to the last untouched candidate",
		pick3 == near)

	# --- A recently-targeted candidate is DEMOTED, not excluded - if it's
	# the only valid target in range, it still gets picked ------------------
	MissileRackTileScript._recent_targets.clear()
	var min_r2 = 100.0
	var max_r2 = 800.0 # only `lone` (dist 600) qualifies; near/mid/far/others are all further out

	var lone_pick1 = tile._find_furthest_target_in_range(muzzle, true, min_r2, max_r2)
	_check("a lone candidate is picked on the first call",
		lone_pick1 == lone)
	var lone_pick2 = tile._find_furthest_target_in_range(muzzle, true, min_r2, max_r2)
	_check("the SAME lone candidate is still picked immediately after (demoted, never excluded - firing at nothing would be worse than overkill)",
		lone_pick2 == lone)

	# --- The penalty expires after RECENT_TARGET_WINDOW_MS - a target
	# doesn't stay permanently deprioritized for the whole fight -----------
	MissileRackTileScript._recent_targets.clear()
	var min_r3 = 5500.0
	var max_r3 = 8500.0 # only target_a (8000) and target_b (6000) qualify

	var expiry_pick1 = tile._find_furthest_target_in_range(muzzle, true, min_r3, max_r3)
	_check("expiry test: first pick is the furthest (target_a)",
		expiry_pick1 == target_a)
	# Simulate the window elapsing by backdating target_a's recorded
	# timestamp directly, rather than a real sleep - same "test the state,
	# not real wall-clock time" reasoning used elsewhere in this codebase's
	# checks (e.g. the lightning-zigzag segment-bucket math).
	var iid_a = target_a.get_instance_id()
	MissileRackTileScript._recent_targets[iid_a] = Time.get_ticks_msec() - (MissileRackTileScript.RECENT_TARGET_WINDOW_MS + 50)
	var expiry_pick2 = tile._find_furthest_target_in_range(muzzle, true, min_r3, max_r3)
	_check("once the window has elapsed, the previously-targeted candidate becomes fully eligible again (still the objectively furthest)",
		expiry_pick2 == target_a)

	# --- Most Powerful mode gets the identical treatment - reuses
	# near/mid/far, mutating max_hp rather than adding new candidates -----
	MissileRackTileScript._recent_targets.clear()
	near.max_hp = 100.0
	mid.max_hp = 200.0
	far.max_hp = 300.0
	var power_pick1 = tile._find_most_powerful_target_in_range(muzzle, true, min_r1, max_r1)
	_check("Most Powerful: first pick is the genuinely toughest target",
		power_pick1 == far)
	var power_pick2 = tile._find_most_powerful_target_in_range(muzzle, true, min_r1, max_r1)
	_check("Most Powerful: second pick spreads to the next-toughest target instead of re-picking the same one",
		power_pick2 == mid)

	# --- A pick actually GETS recorded, not just read - a second independent
	# tile instance (a second Missile Rack on the same or a different mech)
	# sees and respects the first tile's pick too, since the registry is
	# shared, not per-tile -----------------------------------------------
	MissileRackTileScript._recent_targets.clear()
	var min_r4 = 8700.0
	var max_r4 = 10000.0 # only only_target (9500) and other_target (9000) qualify

	var tile_a_pick = tile._find_furthest_target_in_range(muzzle, true, min_r4, max_r4)
	_check("shared-registry setup: tile A picks the furthest of the two (only_target)",
		tile_a_pick == only_target)
	var tile_b_pick = tile_b._find_furthest_target_in_range(muzzle, true, min_r4, max_r4)
	_check("a SECOND, independent tile instance sees tile A's pick and spreads to the other target instead of also converging on it",
		tile_b_pick == other_target)

	MissileRackTileScript._recent_targets.clear()

	if failures == 0:
		print("PASS: Missile Rack targeting spreads across multiple valid candidates (both Furthest and Most Powerful modes, and across independent tile instances) instead of always converging on the single best target, while never leaving a lone candidate untargeted and never permanently blacklisting a target past RECENT_TARGET_WINDOW_MS")
	get_tree().quit(0 if failures == 0 else 1)
