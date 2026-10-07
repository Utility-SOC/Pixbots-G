class_name AdaptiveTick
extends Node

# Adaptive physics rate: escape the fixed-timestep "spiral of death".
#
# Godot runs _physics_process at a fixed rate (60 Hz) and, when a frame takes longer than one tick, runs
# several catch-up steps in that frame (capped by max_physics_steps_per_frame, 3 here). Under a heavy
# fight (wave 34, ~120 enemies, ~9 fps) that means every rendered frame pays for THREE full physics ticks
# and the game still only advances 3/60 s = 50 ms of game time per ~100 ms frame: slow motion, with the
# per-tick cost (the biggest slice of the frame) tripled.
#
# This node watches the real frame time and lowers Engine.physics_ticks_per_second in tiers so a slow frame
# needs ~1 larger step instead of 3. Everything gameplay-side is delta-scaled, and projectiles/shots use
# swept tests, so a larger step is the same simulation at coarser granularity. At >= ~50 fps nothing changes
# (the 60 Hz tier). OFF by default; enable with --adaptive-tick (user args) or PIXBOTS_ADAPTIVE_TICK=1.
# DebugRoom A/B (wave 34, ~190 enemies): game speed 0.32 -> 0.65 avg, fps 6.3 -> 7.1 avg but one run collapsed
# at the 15 Hz floor; motion smoothness at low physics rates is unverified.

const TIERS := [60, 40, 30, 20, 15]
const EVAL_INTERVAL := 0.5
const DOWN_MARGIN := 0.85 # step down when achieved fps < tier * this
const UP_MARGIN := 1.15 # step up when achieved fps > next tier * this
const MIN_HOLD := 2.0 # seconds to hold a tier before stepping UP again

static var enabled: bool = false # opt-in: PIXBOTS_ADAPTIVE_TICK=1 or --adaptive-tick (needs a human playtest: 15-20 Hz physics looks steppy without interpolation)
static var current_hz: int = 60

var _ema_ms := 16.7
var _last_us := 0
var _eval_t := 0.0
var _since_change := 0.0
var _tier := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100000 # sample after everything else so the interval covers the whole frame
	if OS.get_environment("PIXBOTS_ADAPTIVE_TICK") == "1" or OS.get_cmdline_user_args().has("--adaptive-tick"):
		enabled = true
	current_hz = Engine.physics_ticks_per_second

func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_us == 0:
		_last_us = now
		return
	var ms := (now - _last_us) / 1000.0
	_last_us = now
	if ms > 2000.0:
		return # a load hitch / window drag, not a sustained rate
	_ema_ms = lerpf(_ema_ms, ms, 0.12)
	_eval_t += ms / 1000.0
	_since_change += ms / 1000.0
	if _eval_t < EVAL_INTERVAL:
		return
	_eval_t = 0.0
	if not enabled:
		if _tier != 0:
			_apply(0)
		return
	if get_tree().paused:
		return # menus/garage: frame time there says nothing about combat load
	var fps := 1000.0 / maxf(_ema_ms, 0.1)
	var want := _tier
	if _tier < TIERS.size() - 1 and fps < TIERS[_tier] * DOWN_MARGIN:
		want = _tier + 1
		# Jump straight to the right tier when far off, not one step per half second.
		while want < TIERS.size() - 1 and fps < TIERS[want] * DOWN_MARGIN:
			want += 1
	elif _tier > 0 and _since_change >= MIN_HOLD and fps > TIERS[_tier - 1] * UP_MARGIN:
		want = _tier - 1
	if want != _tier:
		_apply(want)

func _apply(tier: int) -> void:
	_tier = tier
	_since_change = 0.0
	current_hz = TIERS[tier]
	Engine.physics_ticks_per_second = current_hz

# Pure policy for tests: given the current tier and measured fps, which tier next?
static func next_tier(tier: int, fps: float, since_change: float) -> int:
	if tier < TIERS.size() - 1 and fps < TIERS[tier] * DOWN_MARGIN:
		var want := tier + 1
		while want < TIERS.size() - 1 and fps < TIERS[want] * DOWN_MARGIN:
			want += 1
		return want
	if tier > 0 and since_change >= MIN_HOLD and fps > TIERS[tier - 1] * UP_MARGIN:
		return tier - 1
	return tier
