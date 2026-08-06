extends Node

# AAA Polish Roadmap Phase 1: "Impact Hitstop (Frame Freeze)" - a brief
# Engine.time_scale dip on dramatic hits (Pierce executions, boss deaths)
# so they land with real weight instead of blending into the normal damage
# tick stream. Global time_scale affects every _process/_physics_process
# delta in the game uniformly (physics, AI timers, projectile flight all
# scale together), which is exactly the "everything hitches for a beat"
# feel hitstop wants - and since it's uniform, nothing desyncs from
# anything else during the freeze.
#
# Self-restoring by construction: the recovery timer is created with
# ignore_time_scale=true, so it always fires after `duration_sec` of REAL
# wall-clock time regardless of how low time_scale itself was just set to.
# Without that, a 0.05 freeze_scale would make its own recovery timer take
# 20x longer than intended (and any bug in the call site - an exception
# before the restore, e.g. - could leave the whole game stuck in
# slow-motion forever). One in-flight guard (_active) so an overlapping
# second trigger (e.g. a pierce-execution landing mid-freeze from an
# already-active hitstop) can't stack multiple restores against each other
# or fight over time_scale.

var _active: bool = false

# duration_sec: real-world seconds the freeze lasts (roadmap spec: 2-4
# frames at 60fps, ~0.03-0.06s). freeze_scale: how slow time runs during
# that window (not fully paused - 0.0 would also stop the recovery timer's
# OWN node processing in edge cases, and a near-frozen-but-not-quite frame
# reads better than a hard stutter anyway).
func trigger(duration_sec: float = 0.045, freeze_scale: float = 0.05):
	if _active:
		return
	_active = true
	Engine.time_scale = freeze_scale
	var timer = get_tree().create_timer(duration_sec, true, false, true)
	timer.timeout.connect(_restore)

func _restore():
	Engine.time_scale = 1.0
	_active = false
