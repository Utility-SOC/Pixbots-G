extends RefCounted

# Moving "par" for raw fitness per bucket (e.g. "sniper:2" = role:rarity), so
# a score of 100 always means "as good as a typical enemy of this kind at this
# tier". Raw fitness scales with wave HP/damage multipliers and with component
# rarity; comparing raw numbers across waves or tiers just rewards being
# higher-tier (a race to Mythic). Normalising against par makes fitness judge
# behaviour and loadout quality relative to what's expected at that level, and
# lets the fixed cull/graduate/promote thresholds (60/110/100) stay meaningful.

const EMA_RATE = 0.08
const MIN_PAR = 25.0
const MAX_NORMALIZED = 400.0

var _par: Dictionary = {}
var _samples: Dictionary = {}

# Returns fitness relative to par (100 = par), then folds the raw sample into par.
# Normalising BEFORE updating keeps a lone outlier from erasing its own signal.
func normalize_and_update(bucket: String, raw: float) -> float:
	raw = max(raw, 0.0)
	if not _par.has(bucket):
		_par[bucket] = max(raw, MIN_PAR)
		_samples[bucket] = 1
		return 100.0
	var par: float = _par[bucket]
	var normalized: float = clamp(100.0 * raw / max(par, MIN_PAR), 0.0, MAX_NORMALIZED)
	_par[bucket] = lerp(par, max(raw, MIN_PAR), EMA_RATE)
	_samples[bucket] = int(_samples.get(bucket, 0)) + 1
	return normalized

func par_for(bucket: String) -> float:
	return float(_par.get(bucket, 0.0))

func to_dict() -> Dictionary:
	return {"par": _par.duplicate(), "samples": _samples.duplicate()}

func from_dict(data: Dictionary) -> void:
	if data.get("par") is Dictionary:
		_par = {}
		for k in data["par"]:
			_par[str(k)] = float(data["par"][k])
	if data.get("samples") is Dictionary:
		_samples = {}
		for k in data["samples"]:
			_samples[str(k)] = int(data["samples"][k])
