class_name CoverBrain
extends RefCounted

# One enemy mech using cover: when pressured (recently hit, or wounded) a ranged bot picks a hiding cell the player
# cannot see (CoverSense.find_cover), runs to it, waits out of sight, then steps to a nearby peek cell, fires, and
# ducks back. After a few cycles, or once the pressure is off, it returns to normal behaviour for a cooldown.
#
# While active this brain owns the mech's movement (Mech asks desired_velocity) and suppresses the "lost sight -> search"
# fallback, since hiding is deliberate. Bosses and melee bots never use it. At most half a squad is in cover at once so
# a squad still pressures the player instead of vanishing.

enum Mode { NONE, SEEK, HIDE, PEEK }

const MIN_ENGAGEMENT = 170.0 # melee-range bots just charge
const WOUNDED_FRAC = 0.5
# Per-bot caution (stable, from its instance id) is the chance it takes cover each time it evaluates while pressured.
# Backline roles are warier. (tune)
const CAUTION_RANGE = Vector2(0.35, 0.85)
const BACKLINE_CAUTION_BONUS = 0.15
# Pressure: damage taken (as a fraction of max HP) within a ~2 s window, or being wounded. A single chip does not send a
# healthy bot running. (tune)
const DAMAGE_WINDOW = 2.0
const DAMAGE_TRIGGER = 0.12
# Hit this hard (fraction of max HP) while peeking and the bot ducks back at once instead of finishing its peek.
const PEEK_PUNISH = 0.06
# How often a hidden bot checks that its cover still works (the player moved, or the rock was shot away).
const COVER_CHECK_INTERVAL = 0.5
const SEEK_TIMEOUT = 4.0
const HIDE_TIME = Vector2(0.8, 1.6)
const PEEK_TIME = Vector2(1.2, 2.2)
const MAX_CYCLES = 3
const COOLDOWN = 4.0
const FAIL_COOLDOWN = 1.5
const ARRIVE = 14.0
const ABORT_CLOSE = 110.0 # the player is on top of us: stop hiding
const EVAL_INTERVAL = 0.4
const MAX_SQUAD_FRACTION = 0.5

# Diagnostics (read by BenchGame): how many cover sequences started / peeks happened this process.
static var stat_started: int = 0
static var stat_peeks: int = 0
static var stat_ducks: int = 0 # peeks cut short by taking a hit
static var stat_replans: int = 0 # hide cells that stopped working (player moved / cover destroyed)
static var stat_why: Dictionary = {} # reason a candidate did not take cover -> count

static func _why(k: String) -> void:
	stat_why[k] = int(stat_why.get(k, 0)) + 1
var m: Node
var mode: int = Mode.NONE
var hide_pos: Vector2 = Vector2.ZERO
var peek_pos: Vector2 = Vector2.ZERO
var _timer: float = 0.0
var _cycles: int = 0
var _cooldown: float = 0.0
var _eval: float = 0.0
var _recent_damage: float = 0.0 # decayed fraction of max HP lost recently
var _last_hp: float = -1.0
var _peek_damage: float = 0.0
var _check: float = 0.0
var caution: float = 0.6

func _init(mech: Node) -> void:
	m = mech
	_eval = float(m.get_instance_id() % 5) * 0.08 # spread evaluations across mechs
	# posmod: instance ids get large enough that id * 2654435761 wraps 64 bits negative, and a plain % then went negative too
	# (caution fell below CAUTION_RANGE for some bots).
	var h = float(posmod(m.get_instance_id() * 2654435761, 1000)) / 1000.0
	caution = lerpf(CAUTION_RANGE.x, CAUTION_RANGE.y, h)
	if "combat_role" in m and str(m.combat_role) in CoverSense.BACKLINE_ROLES:
		caution = minf(caution + BACKLINE_CAUTION_BONUS, 1.0)

func active() -> bool:
	return mode != Mode.NONE

func hiding() -> bool:
	return mode == Mode.HIDE

func label() -> String:
	return ["", "TO COVER", "IN COVER", "PEEK"][mode]

func _threat_pos() -> Vector2:
	if m.has_sight_of_player or m.last_known_player_pos == Vector2.ZERO:
		return m.target.global_position
	return m.last_known_player_pos

func _eligible() -> bool:
	if m.is_boss or float(m.engagement_distance) < MIN_ENGAGEMENT:
		_why("ineligible")
		return false
	return m.target != null and is_instance_valid(m.target)

func _track_damage(delta: float) -> float:
	var hp = float(m.hp)
	var lost = 0.0
	if _last_hp >= 0.0 and hp < _last_hp:
		lost = (_last_hp - hp) / maxf(float(m.max_hp), 1.0)
	_last_hp = hp
	_recent_damage = _recent_damage * exp(-delta / DAMAGE_WINDOW) + lost
	return lost

func _pressured() -> bool:
	var hp_frac = float(m.hp) / maxf(float(m.max_hp), 1.0)
	return _recent_damage >= DAMAGE_TRIGGER or hp_frac < WOUNDED_FRAC

func _squad_cover_share() -> float:
	var sq = m.squad
	if sq == null or not ("members" in sq) or sq.members.size() <= 1:
		return 0.0
	var n = 0
	var inside = 0
	for o in sq.members:
		if not is_instance_valid(o):
			continue
		n += 1
		if o != m and "cover_brain" in o and o.cover_brain != null and o.cover_brain.active():
			inside += 1
	return float(inside + 1) / float(maxi(n, 1))

func _stop(cooldown: float) -> void:
	mode = Mode.NONE
	_cooldown = cooldown
	_cycles = 0

func update(delta: float, map) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	var lost = _track_damage(delta)
	if not _eligible():
		if active():
			_stop(COOLDOWN)
		return
	var threat = _threat_pos()
	if mode == Mode.NONE:
		_eval -= delta
		if _eval > 0.0 or _cooldown > 0.0:
			return
		_eval = EVAL_INTERVAL
		if map == null or not _pressured() or m.global_position.distance_to(threat) < ABORT_CLOSE * 1.5:
			_why("not_pressured")
			return
		if _squad_cover_share() > MAX_SQUAD_FRACTION or SimRng.stream("ai").randf() > caution:
			_why("squad_or_chance")
			_cooldown = FAIL_COOLDOWN
			return
		if not CoverSense.take_budget():
			_why("budget")
			return
		var spot = CoverSense.find_cover(map, m.global_position, threat, float(m.engagement_distance), bool(m.is_amphibious))
		if spot.is_empty():
			_why("no_spot")
			_cooldown = FAIL_COOLDOWN
			return
		var amph = bool(m.is_amphibious)
		if not map.segment_walkable(m.global_position, spot["hide"], amph) or not map.segment_walkable(spot["hide"], spot["peek"], amph):
			_why("path")
			_cooldown = FAIL_COOLDOWN # steering is a straight line: only use cover we can walk to directly
			return
		hide_pos = spot["hide"]
		peek_pos = spot["peek"]
		mode = Mode.SEEK
		stat_started += 1
		_timer = SEEK_TIMEOUT
		return

	# Active: abort when the player is on top of us, or the threat vanished.
	if m.global_position.distance_to(threat) < ABORT_CLOSE:
		_stop(COOLDOWN)
		return
	_timer -= delta
	match mode:
		Mode.SEEK:
			if m.global_position.distance_to(hide_pos) <= ARRIVE:
				mode = Mode.HIDE
				_timer = SimRng.stream("ai").randf_range(HIDE_TIME.x, HIDE_TIME.y) * (1.4 if float(m.hp) < float(m.max_hp) * WOUNDED_FRAC else 1.0)
			elif _timer <= 0.0:
				_stop(FAIL_COOLDOWN)
		Mode.HIDE:
			_check -= delta
			if _check <= 0.0:
				_check = COVER_CHECK_INTERVAL
				if not _cover_still_works(map, threat):
					_replan(map, threat)
					return
			if _timer <= 0.0:
				mode = Mode.PEEK
				stat_peeks += 1
				_peek_damage = 0.0
				_timer = SimRng.stream("ai").randf_range(PEEK_TIME.x, PEEK_TIME.y)
		Mode.PEEK:
			_peek_damage += lost
			if _peek_damage >= PEEK_PUNISH:
				stat_ducks += 1
				mode = Mode.HIDE # punished for standing in the open: back behind the rock now
				_cycles += 1
				_timer = SimRng.stream("ai").randf_range(HIDE_TIME.x, HIDE_TIME.y)
				return
			if _timer <= 0.0:
				_cycles += 1
				if _cycles >= MAX_CYCLES or not _pressured_loosely():
					_stop(COOLDOWN)
				else:
					mode = Mode.HIDE
					_timer = SimRng.stream("ai").randf_range(HIDE_TIME.x, HIDE_TIME.y)

# Is the hide cell still out of the threat's sight (the player may have moved, or the rock been shot away)?
func _cover_still_works(map, threat: Vector2) -> bool:
	if map == null:
		return true
	return bool(CoverSense.body_cover(map, hide_pos, threat)["covered"])

# The cover failed: find new cover from where we stand, or give up for a short cooldown and fight on.
func _replan(map, threat: Vector2) -> void:
	stat_replans += 1
	if map == null or not CoverSense.take_budget():
		_stop(FAIL_COOLDOWN)
		return
	var amph = bool(m.is_amphibious)
	var spot = CoverSense.find_cover(map, m.global_position, threat, float(m.engagement_distance), amph)
	if spot.is_empty() or not map.segment_walkable(m.global_position, spot["hide"], amph) or not map.segment_walkable(spot["hide"], spot["peek"], amph):
		_stop(FAIL_COOLDOWN)
		return
	hide_pos = spot["hide"]
	peek_pos = spot["peek"]
	mode = Mode.SEEK
	_timer = SEEK_TIMEOUT

# Keep ducking while the fight is still hot: hit within a few windows, or still wounded.
func _pressured_loosely() -> bool:
	return _recent_damage >= DAMAGE_TRIGGER * 0.5 or float(m.hp) < float(m.max_hp) * WOUNDED_FRAC

# Steering toward the current cover point; zero once arrived.
func desired_velocity(speed: float) -> Vector2:
	var goal = peek_pos if mode == Mode.PEEK else hide_pos
	var to_goal: Vector2 = goal - m.global_position
	if to_goal.length() <= ARRIVE * 0.5:
		return Vector2.ZERO
	return to_goal.normalized() * speed * (1.0 if to_goal.length() > 40.0 else to_goal.length() / 40.0)
