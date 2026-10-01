extends RefCounted

# Cross-run, cross-save progression: Research Points (RP) earned by pushing
# further and killing bosses, spent on a few permanent perks. Stored in
# user://meta_progress.json (not per save slot). Deliberately modest: perks
# improve salvage luck, never combat stats, so the difficulty curve is
# untouched. Anti-farm: RP comes from NEW best waves and boss kills only.

static var path: String = "user://meta_progress.json"
static var _data: Dictionary = {}
static var _loaded: bool = false

const MAX_LEVEL = 3
const PERKS = {
	"salvage_contract": {"name": "Salvage Contract", "desc": "+12% drop chance on useful tiles per level", "costs": [3, 6, 10]},
	"mythic_scouting": {"name": "Mythic Scouting", "desc": "+30% Mythic drop chance per level", "costs": [4, 8, 14]},
	"pity_timer": {"name": "Lucky Break", "desc": "Drought protection kicks in sooner per level", "costs": [2, 5, 9]},
}
const RP_PER_NEW_WAVE = 1
const RP_PER_BOSS = 2
const MAX_RP = 100000
const DAILY_KEEP = 30

static func _blank() -> Dictionary:
	return {"rp": 0, "spent": 0, "best_wave": 0, "bosses": 0, "perks": {}, "daily": {}}

static func load_data() -> void:
	_data = _blank()
	_loaded = true
	if not FileAccess.file_exists(path):
		return
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > 65536:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return
	for k in ["rp", "spent", "best_wave", "bosses"]:
		_data[k] = clampi(int(parsed.get(k, 0)), 0, MAX_RP)
	if parsed.get("daily") is Dictionary:
		var keys = parsed["daily"].keys()
		keys.sort()
		keys = keys.slice(maxi(0, keys.size() - DAILY_KEEP))
		for k in keys:
			var ks = str(k)
			if _is_date_key(ks) and int(parsed["daily"][k]) > 0:
				_data["daily"][ks] = clampi(int(parsed["daily"][k]), 0, 100000)
	if parsed.get("perks") is Dictionary:
		for id in PERKS:
			_data["perks"][id] = clampi(int(parsed["perks"].get(id, 0)), 0, MAX_LEVEL)

static func _is_date_key(k: String) -> bool:
	if k.length() != 10 or k[4] != "-" or k[7] != "-":
		return false
	return k.substr(0, 4).is_valid_int() and k.substr(5, 2).is_valid_int() and k.substr(8, 2).is_valid_int()

static func _ensure() -> void:
	if not _loaded:
		load_data()

static func reset_for_tests(test_path: String) -> void:
	path = test_path
	_loaded = false
	_data = {}

static func save_data() -> void:
	_ensure()
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_data))
		f.close()

static func rp() -> int:
	_ensure()
	return int(_data["rp"])

static func best_wave() -> int:
	_ensure()
	return int(_data["best_wave"])

static func perk_level(id: String) -> int:
	_ensure()
	return int(_data["perks"].get(id, 0))

# Returns RP earned (0 if this wave wasn't a new best).
static func note_run_end(wave: int) -> int:
	_ensure()
	var gained = 0
	if wave > int(_data["best_wave"]):
		gained = (wave - int(_data["best_wave"])) * RP_PER_NEW_WAVE
		_data["best_wave"] = wave
		_data["rp"] = mini(int(_data["rp"]) + gained, MAX_RP)
		save_data()
	return gained

static func note_boss_kill() -> int:
	_ensure()
	_data["bosses"] = int(_data["bosses"]) + 1
	_data["rp"] = mini(int(_data["rp"]) + RP_PER_BOSS, MAX_RP)
	save_data()
	return RP_PER_BOSS

static func next_cost(id: String) -> int:
	if not PERKS.has(id):
		return -1
	var lvl = perk_level(id)
	return -1 if lvl >= MAX_LEVEL else int(PERKS[id]["costs"][lvl])

static func can_buy(id: String) -> bool:
	var c = next_cost(id)
	return c >= 0 and rp() >= c

static func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	var c = next_cost(id)
	_data["rp"] = int(_data["rp"]) - c
	_data["spent"] = int(_data["spent"]) + c
	_data["perks"][id] = perk_level(id) + 1
	save_data()
	return true

# Multiplier (>= 1.0) a perk applies to a base value.
static func drop_multiplier(id: String) -> float:
	var lvl = perk_level(id)
	match id:
		"salvage_contract":
			return 1.0 + 0.12 * lvl
		"mythic_scouting":
			return 1.0 + 0.30 * lvl
	return 1.0

# Kills without any tile drop before drought protection starts to help.
static func pity_threshold() -> int:
	return 14 - 3 * perk_level("pity_timer")

# Best wave reached on a given daily date (YYYY-MM-DD); 0 if not played.
static func daily_best(date: String) -> int:
	_ensure()
	return int(_data["daily"].get(date, 0))

static func note_daily_result(date: String, wave: int) -> bool:
	_ensure()
	if wave <= daily_best(date):
		return false
	_data["daily"][date] = clampi(wave, 0, 100000)
	var keys = _data["daily"].keys()
	keys.sort()
	while keys.size() > DAILY_KEEP:
		_data["daily"].erase(keys.pop_front())
	save_data()
	return true
