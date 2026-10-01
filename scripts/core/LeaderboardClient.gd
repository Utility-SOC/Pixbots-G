extends RefCounted

# Daily-seed leaderboard interface. There is NO server yet: the default backend
# reports "not configured" and everything else keeps working offline. To add a
# server later, implement a backend object with the same two methods and assign
# it to `backend`:
#
#   submit(card: Dictionary) -> Dictionary   # card = RunCard dict incl. "result"
#       returns {"ok": bool, "rank": int (optional), "reason": String (on failure)}
#   fetch(date: String, limit: int) -> Dictionary
#       returns {"ok": bool, "entries": [{"pilot": String, "wave": int,
#                "seconds": int, "kills": int}], "reason": String (on failure)}
#
# Cards sent here are already validated by RunCard.parse. A real backend must
# still treat every response as untrusted data (clamp/validate before display)
# and must never make the daily seed depend on the server - the seed is derived
# from the date, so runs stay playable offline. See docs/DAILY_SEED.md.

const RunCard = preload("res://scripts/pvp/RunCard.gd")

class NullBackend extends RefCounted:
	func submit(_card: Dictionary) -> Dictionary:
		return {"ok": false, "reason": "No leaderboard server configured."}
	func fetch(_date: String, _limit: int) -> Dictionary:
		return {"ok": false, "entries": [], "reason": "No leaderboard server configured."}

static var backend = NullBackend.new()

static func is_available() -> bool:
	return not (backend is NullBackend)

static func submit(card: Dictionary) -> Dictionary:
	var clean = RunCard.parse(card)
	if clean.is_empty() or not clean.has("result"):
		return {"ok": false, "reason": "Card is not a finished daily run."}
	if not RunCard.matches_daily(clean):
		return {"ok": false, "reason": "Card does not match the daily seed."}
	return backend.submit(clean)

static func fetch(date: String, limit: int = 20) -> Dictionary:
	if not RunCard.valid_date(date):
		return {"ok": false, "entries": [], "reason": "Bad date."}
	var res = backend.fetch(date, clampi(limit, 1, 100))
	if not (res is Dictionary):
		return {"ok": false, "entries": [], "reason": "Bad server response."}
	var entries: Array = []
	if res.get("entries") is Array:
		for e in res["entries"]:
			if e is Dictionary and entries.size() < 100:
				entries.append({"pilot": str(e.get("pilot", "")).substr(0, 40), "wave": clampi(int(e.get("wave", 0)), 0, 100000),
					"seconds": clampi(int(e.get("seconds", 0)), 0, 10000000), "kills": clampi(int(e.get("kills", 0)), 0, 100000000)})
	return {"ok": bool(res.get("ok", false)), "entries": entries, "reason": str(res.get("reason", ""))}
