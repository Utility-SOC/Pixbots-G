extends Node

# Regression check for Main._compute_spawn_interval (user: "90 per wave
# just for spawning, they spawn spread out over 90 seconds" - replaces the
# old fixed 0.12s-per-squad beat, which compressed a whole wave's worth of
# squads into the first ~2-3 seconds after wave start, concentrating
# AutoEquipSolver spawn cost into one tiny window instead of spreading it
# across the wave). Main.gd can't be safely instantiated standalone in a
# headless check (see CampaignMapRotationCheck.gd's own header comment for
# the @onready constraint) - _compute_spawn_interval only touches plain
# instance vars (active_enemies/garage_timer), so it's safe to call
# directly on a bare Main.new() as long as it's never added to the tree.

const MainScript = preload("res://scripts/core/Main.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var m = MainScript.new()

	# --- 1: right at wave start (garage_timer fresh, no elapsed time), a
	# realistic wave (80 enemies, ~4/squad estimate -> ~20 squads) should
	# get a real, meaningfully-spread interval, not the old instant beat.
	m.active_enemies = 0
	m.garage_timer = 90.0
	var interval_start = m._compute_spawn_interval(80, 90.0)
	_check("at wave start, the interval is meaningfully spread out, not the old instant 0.12s beat (got %.3fs)" % interval_start,
		interval_start > 1.0)

	# --- 2: as active_enemies climbs toward target, remaining time is
	# divided among fewer remaining squads - interval should still be
	# reasonable, not blow up or collapse to zero.
	m.active_enemies = 76 # only 4 enemies (≈1 squad) left of 80
	m.garage_timer = 60.0 # 15s elapsed of the 75s spread window
	var interval_late = m._compute_spawn_interval(80, 90.0)
	_check("late in the wave with few enemies left, the interval stays sane (got %.3fs, expect roughly the remaining ~60s spread window / ~1 squad)" % interval_late,
		interval_late > 1.0 and interval_late < 90.0)

	# --- 3: once garage_timer drops into the safety-margin tail, falls
	# back to the fast anti-freeze beat so a wave still finishes spawning
	# rather than idling right up to extraction opening.
	m.active_enemies = 40
	m.garage_timer = 5.0 # below WAVE_SPAWN_SAFETY_MARGIN_SECONDS (8.0)
	var interval_tail = m._compute_spawn_interval(80, 90.0)
	_check("inside the safety-margin tail, falls back to the fast 0.12s anti-freeze beat (got %.3fs)" % interval_tail,
		abs(interval_tail - 0.12) < 0.001)

	# --- 4: nothing left to spawn - falls back to the fast beat too (loop
	# exits on its own condition anyway, but the function itself shouldn't
	# divide by zero or produce a nonsensical value).
	m.active_enemies = 80
	m.garage_timer = 90.0
	var interval_done = m._compute_spawn_interval(80, 90.0)
	_check("with nothing left to spawn, falls back to the fast beat rather than a nonsensical value (got %.3fs)" % interval_done,
		abs(interval_done - 0.12) < 0.001)

	# --- 5: the interval NEVER exceeds what's left of the actual spread
	# window - i.e. pacing can't overshoot and finish spawning AFTER
	# garage_timer would already be in its safety-margin tail on its own.
	m.active_enemies = 4
	m.garage_timer = 89.0 # essentially the whole window still ahead, but very few enemies left
	var interval_few_left = m._compute_spawn_interval(80, 90.0)
	_check("with very few enemies left early in the wave, the interval doesn't wildly overshoot the remaining spread window (got %.3fs)" % interval_few_left,
		interval_few_left < 80.0)

	if failures == 0:
		print("PASS: wave-spawn pacing spreads squads across the wave's spread window, adapts as enemies/time remaining change, and safely falls back to the fast anti-freeze beat in the tail/edge cases")
	get_tree().quit(0 if failures == 0 else 1)
