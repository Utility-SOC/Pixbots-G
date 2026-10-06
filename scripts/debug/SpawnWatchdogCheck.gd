extends Node

# The spawn watchdog must not fire during a legitimately long, spread-out wave spawn (the old fixed 10 s
# threshold fired every 10 s on every wave and restarted it), must still catch a loop that stops advancing,
# and must not count time spent paused.
var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	var m = load("res://scripts/core/Main.gd").new()
	var now = Time.get_ticks_msec()
	m._spawning_wave = false
	_check("not stalled when no wave is spawning", not m._spawn_loop_stalled())
	m._spawning_wave = true
	m._spawn_progress_deadline = now + 60000 + m.SPAWN_STALL_SLACK_MS
	_check("a 60 s planned wait is not a stall", not m._spawn_loop_stalled())
	m._spawn_progress_deadline = now - 1
	_check("a loop past its deadline is stalled", m._spawn_loop_stalled())
	# pause shifts the deadline
	m._spawn_progress_deadline = now + 5000
	m._notification(Node.NOTIFICATION_PAUSED)
	var paused_for = 40000
	m._paused_at_msec = Time.get_ticks_msec() - paused_for # pretend we paused 40 s ago
	if m._paused_at_msec <= 0:
		m._paused_at_msec = 1
		paused_for = Time.get_ticks_msec() - 1
	m._notification(Node.NOTIFICATION_UNPAUSED)
	_check("a pause pushes the deadline out by its length (+%d ms)" % (m._spawn_progress_deadline - (now + 5000)), m._spawn_progress_deadline >= now + 5000 + paused_for - 50)
	m._spawn_progress_deadline = Time.get_ticks_msec() + 100
	_check("so the wave is not flagged stalled right after the pause", not m._spawn_loop_stalled())
	var src = FileAccess.get_file_as_string("res://scripts/core/Main.gd")
	_check("the old fixed 10 s threshold is gone", not src.contains("_spawning_wave_started_at >= 10000"))
	m.free()
	print("spawn watchdog check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
