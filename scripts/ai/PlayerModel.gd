extends RefCounted

# What the director believes about how the player plays RIGHT NOW, plus the
# "pressure" that keeps the game escalating.
#
# Lifetime-cumulative telemetry (SquadDirector.player_element_usage etc.) never
# notices a player who changes style after many waves - the old habit dominates
# forever. This keeps two exponentially-decayed memories per channel:
#   recent (half-life ~2.4 waves): drives every counter decision
#   slow   (half-life ~23 waves):  the baseline "who this player has been"
# When the recent distribution diverges from the slow one (total-variation
# distance) the player has changed playstyle: the enemy counters built against
# the old style are now obsolete, so the player earns relief (pressure halves)
# and the director re-targets from the recent distribution.
#
# Pressure is what makes the game harder "no matter what the player does": it
# ratchets up a little every wave, a lot when the player is barely scratched,
# and only comes down when they struggle or adapt. It feeds levers that improve
# enemy BEHAVIOUR/LOADOUT (mutation rate, counter-commitment), never raw stats
# or component tier - tier is gated by wave (SquadDirector.RARITY_UNLOCK_WAVES).

const RECENT_DECAY = 0.75
const SLOW_DECAY = 0.97
const SHIFT_THRESHOLD = 0.35
const SHIFT_MIN_DAMAGE_MASS = 300.0
const SHIFT_MIN_KILL_MASS = 10.0
const SHIFT_COOLDOWN_WAVES = 6
const MAX_PRESSURE = 4.0
const DRIFT_PER_WAVE = 0.02

var recent_damage: Dictionary = {}
var slow_damage: Dictionary = {}
var recent_kills: Dictionary = {}
var slow_kills: Dictionary = {}
var pressure: float = 0.0
var waves_since_shift: int = 99
var shift_count: int = 0
var last_dominance: float = 0.0

func log_damage(element: String, amount: float) -> void:
	recent_damage[element] = float(recent_damage.get(element, 0.0)) + amount
	slow_damage[element] = float(slow_damage.get(element, 0.0)) + amount

func log_kill(element: String) -> void:
	recent_kills[element] = float(recent_kills.get(element, 0.0)) + 1.0
	slow_kills[element] = float(slow_kills.get(element, 0.0)) + 1.0

static func _total(d: Dictionary) -> float:
	var t = 0.0
	for k in d:
		t += float(d[k])
	return t

func recent_damage_total() -> float:
	return _total(recent_damage)

func recent_kill_total() -> float:
	return _total(recent_kills)

func recent_damage_share(element: String) -> float:
	var t = recent_damage_total()
	return float(recent_damage.get(element, 0.0)) / t if t > 0.0 else 0.0

func recent_kill_share(element: String) -> float:
	var t = recent_kill_total()
	return float(recent_kills.get(element, 0.0)) / t if t > 0.0 else 0.0

func recent_top_damage_element() -> String:
	var best = ""
	var best_v = 0.0
	for k in recent_damage:
		if float(recent_damage[k]) > best_v:
			best_v = float(recent_damage[k])
			best = k
	return best

static func _tv_distance(a: Dictionary, b: Dictionary) -> float:
	var ta = _total(a)
	var tb = _total(b)
	if ta <= 0.0 or tb <= 0.0:
		return 0.0
	var keys = {}
	for k in a: keys[k] = true
	for k in b: keys[k] = true
	var d = 0.0
	for k in keys:
		d += abs(float(a.get(k, 0.0)) / ta - float(b.get(k, 0.0)) / tb)
	return 0.5 * d

# How different the player's recent behaviour is from their long-run habits (0..1).
func shift_score() -> float:
	var s = 0.0
	if _total(slow_damage) >= SHIFT_MIN_DAMAGE_MASS and _total(recent_damage) >= SHIFT_MIN_DAMAGE_MASS * 0.2:
		s = max(s, _tv_distance(recent_damage, slow_damage))
	if _total(slow_kills) >= SHIFT_MIN_KILL_MASS and _total(recent_kills) >= SHIFT_MIN_KILL_MASS * 0.3:
		s = max(s, _tv_distance(recent_kills, slow_kills))
	return s

static func _decay(d: Dictionary, f: float) -> void:
	for k in d.keys():
		d[k] = float(d[k]) * f

# Called once per cleared wave. `damage_taken` = damage the player absorbed this
# wave, `player_ehp` = their max HP + shield. Returns {"shifted": bool, "dominance": float}.
func end_wave(damage_taken: float, player_ehp: float) -> Dictionary:
	_decay(recent_damage, RECENT_DECAY)
	_decay(recent_kills, RECENT_DECAY)
	_decay(slow_damage, SLOW_DECAY)
	_decay(slow_kills, SLOW_DECAY)
	waves_since_shift += 1

	var shifted = false
	if waves_since_shift >= SHIFT_COOLDOWN_WAVES and shift_score() >= SHIFT_THRESHOLD:
		shifted = true
		shift_count += 1
		waves_since_shift = 0
		pressure *= 0.5
		# The old baseline is obsolete - adopt the new one so the same shift
		# doesn't keep re-firing.
		slow_damage = recent_damage.duplicate()
		slow_kills = recent_kills.duplicate()

	# 1.0 = untouched, 0.0 = nearly dead. Barely-scratched waves raise pressure
	# sharply; a struggling player gets relief; otherwise a small constant drift.
	last_dominance = clamp(1.0 - damage_taken / max(1.0, player_ehp), 0.0, 1.0)
	if not shifted:
		if last_dominance > 0.6:
			pressure += 0.05 + 0.25 * (last_dominance - 0.6) / 0.4
		elif last_dominance < 0.25:
			pressure -= 0.15
		pressure += DRIFT_PER_WAVE
	pressure = clamp(pressure, 0.0, MAX_PRESSURE)
	return {"shifted": shifted, "dominance": last_dominance}

func to_dict() -> Dictionary:
	return {
		"recent_damage": recent_damage, "slow_damage": slow_damage,
		"recent_kills": recent_kills, "slow_kills": slow_kills,
		"pressure": pressure, "waves_since_shift": waves_since_shift,
		"shift_count": shift_count,
	}

func from_dict(data: Dictionary) -> void:
	for f in ["recent_damage", "slow_damage", "recent_kills", "slow_kills"]:
		if data.get(f) is Dictionary:
			var out = {}
			for k in data[f]:
				out[str(k)] = float(data[f][k])
			set(f, out)
	pressure = float(data.get("pressure", 0.0))
	waves_since_shift = int(data.get("waves_since_shift", 99))
	shift_count = int(data.get("shift_count", 0))
