extends RefCounted
class_name ProjectilePool

# Task #35 - real Projectile object pool, attempted per the user's explicit
# choice to try it anyway despite real structural risk found during
# scoping (see Status.md's task #35 entry and the plan at
# C:\Users\Utility\.claude\plans\effervescent-drifting-kazoo.md). Static
# functions/free-list rather than an autoload - no per-frame work needed,
# just an acquire/release API any call site can use directly.
#
# The scoping investigation found `_build_visuals()`'s output is synergy-
# dependent (can't be cheaply reused across dissimilar shots), so this pool
# does NOT attempt to reuse that subtree - Projectile.gd's own _ready()
# still fully tears down and rebuilds `visual_node` every activation, same
# as before pooling existed. What IS safely reused: the outer Projectile
# node itself, its lifetime Timer, and its VisibleOnScreenNotifier2D (see
# Projectile.gd's _ready() guarded-creation blocks, task #35 B3) - the
# honest, narrower savings this investigation's own read predicted.
#
# The instance-ID-reuse concern (ProjectileManager/ProjectileBroadphase key
# their tracking Dictionaries by get_instance_id(), which never changes for
# a reused node) is resolved for free: release() uses remove_child(), not
# queue_free() - Godot's _exit_tree() fires on ANY tree exit, not just
# destruction, so Projectile._exit_tree()'s existing
# ProjectileManager.unregister/ProjectileBroadphase.unregister calls
# already fire correctly with zero new code here. Re-acquiring calls
# request_ready() so _ready() (which _exit_tree()'s counterpart,
# re-registering + rebuilding visuals + resetting state via
# _reset_pooled_state()) runs again on the next add_child(), confirmed
# working via ProjectileReuseMechanicsCheck.gd before this pool was built.

const MAX_POOL_SIZE = 300

static var _free_list: Array[Projectile] = []

static func acquire() -> Projectile:
	while not _free_list.is_empty():
		var proj = _free_list.pop_back()
		if is_instance_valid(proj):
			proj.request_ready()
			return proj
		# else: instance died some other way (shouldn't normally happen for
		# a pooled/parked node, but stay defensive) - keep popping.
	return Projectile.new()

# Caller must NOT have already queue_free()'d proj - release() is the
# alternative to that, not a companion to it. Safe to call on a projectile
# that's already outside the tree (e.g. a caller that already removed it)
# as long as it's still a valid instance.
static func release(proj: Projectile):
	if not is_instance_valid(proj):
		return
	var parent = proj.get_parent()
	if parent:
		parent.remove_child(proj) # triggers _exit_tree() -> existing ProjectileManager/ProjectileBroadphase unregister, no new code needed
	if _free_list.size() >= MAX_POOL_SIZE:
		proj.queue_free() # pool's full - a genuinely dead instance beats unbounded growth
		return
	_free_list.append(proj)

# Debug/test-only: lets a fresh benchmark or check start from a known-empty
# pool instead of whatever a previous test in the same process left behind.
static func _clear_for_testing():
	for proj in _free_list:
		if is_instance_valid(proj):
			proj.queue_free()
	_free_list.clear()
