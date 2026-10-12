extends RefCounted

# Enemy "radio chatter": short readable lines describing what squads are doing
# (plan chosen, staging done and committing, plan failing and switching,
# casualties, wipe-outs). Fed by SquadTactics / Squad / SquadDirector events.
#
# Deliberately slow: one line per MIN_GAP seconds, a per-squad-per-kind
# cooldown, a short pending queue that drops stale/low-priority lines, so it
# reads as a commentary track rather than a spam feed.

signal line_emitted(entry)

const MIN_GAP = 2.5
const KIND_COOLDOWN = 8.0
const MAX_PENDING = 3
const PENDING_TTL = 6.0
const HISTORY_CAP = 50

const PRIORITY = {"wipe": 5, "replan": 4, "casualty": 3, "commit": 2, "plan": 1}

# Voice: the Trainer, the Corp's training AI that runs the enemy squads. Clinical, polite, faintly bureaucratic, a little too
# pleased with itself; it never panics and never shouts. (The Shopkeeper is the warm, wry human voice; see docs/VOICE.md.)
const PLAN_LINES = {
	"swarm": ["%s: Approach vector: direct. Subtlety module not installed.", "%s: Plan one of six. Everyone, at once."],
	"synchronized_strike": ["%s: Staging. Fire on my mark. Mark pending.", "%s: Holding for coordinated fire. Subject is asked to remain stationary."],
	"pincer": ["%s: Splitting left and right. Subject's attention budget: exceeded.", "%s: Pincer. Both sides. Courtesy of geometry."],
	"hammer_anvil": ["%s: One unit holds the line. The rest are relocating behind you.", "%s: Anvil pins. Hammer arrives shortly. Please do not move."],
	"encircle": ["%s: Forming a ring. Gaps are discouraged.", "%s: Closing the circle."],
	"bait_flank": ["%s: Bait deployed. Bait has been informed.", "%s: Decoy forward. Flankers in transit."],
}
const COMMIT_LINES = ["%s: Committing. Good luck to someone.", "%s: Engaging. Paperwork later.", "%s: In position. Engage."]
const REPLAN_LINES = ["%s: Current plan underperforming. Revising.", "%s: Subject has adapted. So will we.", "%s: Plan B. There is a plan C."]
const CASUALTY_LINES = ["%s: Unit lost. Noted.", "%s: One fewer. Tightening up.", "%s: Casualty logged. Efficiency down."]
const WIPE_LINES = ["%s: Squad offline. Filing a complaint.", "%s: Contact lost with every unit. Learning from this."]

var history: Array = []
var _pending: Array = []
var _last_emit: float = -999.0
var _kind_last: Dictionary = {}
var _clock: float = 0.0
var _rng := RandomNumberGenerator.new()

func _init():
	_rng.randomize()

# `detail` is the new plan name for "plan"/"replan"/"commit" events.
func post(kind: String, squad_name: String, squad_key: int, plan: String = "") -> void:
	var cd_key = "%d:%s" % [squad_key, kind]
	if _kind_last.has(cd_key) and _clock - float(_kind_last[cd_key]) < KIND_COOLDOWN:
		return
	var text = _compose(kind, squad_name, plan)
	if text == "":
		return
	_kind_last[cd_key] = _clock
	_pending.append({"kind": kind, "text": text, "t": _clock, "prio": int(PRIORITY.get(kind, 0))})
	# Keep only the most important pending lines.
	if _pending.size() > MAX_PENDING:
		_pending.sort_custom(func(a, b): return a["prio"] > b["prio"] or (a["prio"] == b["prio"] and a["t"] > b["t"]))
		_pending.resize(MAX_PENDING)

func _compose(kind: String, squad_name: String, plan: String) -> String:
	var name = squad_name.substr(0, 40) if squad_name != "" else "Squad"
	var pool: Array = []
	match kind:
		"plan", "replan":
			pool = PLAN_LINES.get(plan, [])
			if kind == "replan" and not pool.is_empty():
				return _pick(REPLAN_LINES) % name + " " + (_pick(pool) % name).trim_prefix(name + ": ")
		"commit":
			pool = COMMIT_LINES
		"casualty":
			pool = CASUALTY_LINES
		"wipe":
			pool = WIPE_LINES
	if pool.is_empty():
		return ""
	return _pick(pool) % name

func _pick(arr: Array) -> String:
	return arr[_rng.randi() % arr.size()]

# Called every frame by the director.
func pump(delta: float) -> void:
	_clock += delta
	if _pending.is_empty() or _clock - _last_emit < MIN_GAP:
		return
	_pending = _pending.filter(func(e): return _clock - float(e["t"]) <= PENDING_TTL)
	if _pending.is_empty():
		return
	# Most important first, oldest among equals.
	_pending.sort_custom(func(a, b): return a["prio"] > b["prio"] or (a["prio"] == b["prio"] and a["t"] < b["t"]))
	var e = _pending.pop_front()
	_last_emit = _clock
	var entry = {"text": e["text"], "kind": e["kind"], "t": _clock}
	history.append(entry)
	while history.size() > HISTORY_CAP:
		history.pop_front()
	line_emitted.emit(entry)
