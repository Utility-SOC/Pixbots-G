extends RefCounted

# How the player MOVES in fights: range they keep, whether they retreat, strafe,
# charge or camp, which way they like to run, how often they reverse. Sampled a
# few times a second while enemies are alive, decayed per wave so it tracks the
# player's current habits. Feeds plan selection (SquadTactics/TacticGenome) and a
# "cut-off" flanker that pre-positions on the player's favoured escape heading.
# Behaviour only - never stats or tier.

const DECAY = 0.8
const MIN_SAMPLE_TIME = 8.0 # seconds of combat before habits count at all
const CLOSE_RANGE = 200.0
const FAR_RANGE = 500.0
const IDLE_SPEED = 30.0
const MOVE_SPEED = 60.0
const MIN_CONFIDENCE = 0.35

const KEYS = ["t_close", "t_mid", "t_far", "t_idle", "t_move", "t_approach", "t_retreat", "t_strafe", "rx", "ry", "rt", "rev"]
var acc: Dictionary = {}
var _last_heading: Vector2 = Vector2.ZERO

func _add(k: String, v: float) -> void:
	acc[k] = float(acc.get(k, 0.0)) + v

func total_time() -> float:
	return float(acc.get("t_close", 0.0)) + float(acc.get("t_mid", 0.0)) + float(acc.get("t_far", 0.0))

# dt = seconds since last sample. enemy_pos = nearest living enemy.
func sample(dt: float, player_pos: Vector2, player_vel: Vector2, enemy_pos: Vector2) -> void:
	if dt <= 0.0:
		return
	var to_enemy = enemy_pos - player_pos
	var dist = to_enemy.length()
	if dist < CLOSE_RANGE:
		_add("t_close", dt)
	elif dist < FAR_RANGE:
		_add("t_mid", dt)
	else:
		_add("t_far", dt)
	var speed = player_vel.length()
	if speed < IDLE_SPEED:
		_add("t_idle", dt)
		return
	_add("t_move", dt)
	var e = to_enemy / max(dist, 1.0)
	var radial = player_vel.dot(e)
	var tangential = (player_vel - e * radial).length()
	if abs(radial) >= tangential:
		if radial > 0.0:
			_add("t_approach", dt)
		else:
			_add("t_retreat", dt)
			var h = player_vel / speed
			_add("rx", h.x * dt)
			_add("ry", h.y * dt)
			_add("rt", dt)
	else:
		_add("t_strafe", dt)
	if speed >= MOVE_SPEED:
		var heading = player_vel / speed
		if _last_heading != Vector2.ZERO and heading.dot(_last_heading) < -0.3:
			_add("rev", 1.0)
		_last_heading = heading

func end_wave() -> void:
	for k in acc.keys():
		acc[k] = float(acc[k]) * DECAY

func _share(k: String, of: String) -> float:
	var d = float(acc.get(of, 0.0))
	return float(acc.get(k, 0.0)) / d if d > 0.0 else 0.0

# Preferred retreat direction (unit vector) and how consistent it is (0..1).
func retreat_heading() -> Dictionary:
	var rt = float(acc.get("rt", 0.0))
	if rt < 2.0:
		return {"dir": Vector2.ZERO, "confidence": 0.0}
	var v = Vector2(float(acc.get("rx", 0.0)), float(acc.get("ry", 0.0)))
	var conf = v.length() / rt
	return {"dir": v.normalized() if v.length() > 0.001 else Vector2.ZERO, "confidence": clamp(conf, 0.0, 1.0)}

# Fraction of moving time spent reversing heading (high = unpredictable).
func reversal_rate() -> float:
	var t = float(acc.get("t_move", 0.0))
	return clamp(float(acc.get("rev", 0.0)) / max(t, 1.0) * 0.5, 0.0, 1.0)

func ready_for_use() -> bool:
	return total_time() >= MIN_SAMPLE_TIME

func profile() -> Dictionary:
	var t = total_time()
	var p = {
		"close": float(acc.get("t_close", 0.0)) / t if t > 0.0 else 0.0,
		"far": float(acc.get("t_far", 0.0)) / t if t > 0.0 else 0.0,
		"idle": float(acc.get("t_idle", 0.0)) / t if t > 0.0 else 0.0,
		"approach": _share("t_approach", "t_move"),
		"retreat": _share("t_retreat", "t_move"),
		"strafe": _share("t_strafe", "t_move"),
		"reversal": reversal_rate(),
		"seconds": t,
	}
	p["style"] = style(p)
	var rh = retreat_heading()
	p["retreat_dir"] = rh["dir"]
	p["retreat_confidence"] = rh["confidence"]
	return p

static func style(p: Dictionary) -> String:
	if float(p.get("seconds", 0.0)) < MIN_SAMPLE_TIME:
		return "unknown"
	if float(p["idle"]) > 0.35:
		return "camper"
	if float(p["retreat"]) > 0.4:
		return "kiter"
	if float(p["close"]) > 0.5 and float(p["approach"]) > 0.3:
		return "brawler"
	if float(p["strafe"]) > 0.4:
		return "strafer"
	return "mixed"

# Plan weight multipliers for the recognised style: counter the habit, not the build.
const STYLE_PLAN_MULT = {
	"camper": {"synchronized_strike": 1.6, "encircle": 1.4, "hammer_anvil": 1.2, "swarm": 0.8},
	"kiter": {"pincer": 1.5, "hammer_anvil": 1.6, "bait_flank": 1.2, "swarm": 0.7},
	"brawler": {"bait_flank": 1.4, "encircle": 1.2, "swarm": 0.8},
	"strafer": {"synchronized_strike": 1.3, "encircle": 1.3, "swarm": 0.8},
}

func plan_multipliers() -> Dictionary:
	if not ready_for_use():
		return {}
	return STYLE_PLAN_MULT.get(style(profile()), {})

func describe() -> String:
	var p = profile()
	if p["style"] == "unknown":
		return "still watching how you move"
	var s = "%s (range: %d%% close / %d%% far, retreating %d%% of moves, strafing %d%%)" % [p["style"], int(p["close"] * 100), int(p["far"] * 100), int(p["retreat"] * 100), int(p["strafe"] * 100)]
	if float(p["retreat_confidence"]) >= MIN_CONFIDENCE:
		var d: Vector2 = p["retreat_dir"]
		var names = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
		var idx = int(round(d.angle() / (PI / 4.0))) % 8
		if idx < 0:
			idx += 8
		s += ", likes to run %s" % names[idx]
	return s

func to_dict() -> Dictionary:
	return {"acc": acc}

func from_dict(data: Dictionary) -> void:
	acc = {}
	if data.get("acc") is Dictionary:
		for k in KEYS:
			if data["acc"].has(k):
				var v = float(data["acc"][k])
				if is_finite(v):
					acc[k] = clamp(v, -1e6, 1e6)
