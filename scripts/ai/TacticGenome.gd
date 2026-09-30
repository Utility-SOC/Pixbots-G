extends RefCounted

# Evolvable squad tactics. SquadTactics.PLANS are the founding archetypes; a
# genome is {id, base, params, n, mean, gen, parent}: an archetype plus a few
# overridden parameters (flank share/arc, staging distance, standoff, lead
# bonus, replan patience) and optionally toggled flags (staging, split flanks).
#
# The pool is selected, credited, culled and bred with the same par-normalised
# squad fitness the build evolution uses (100 = typical squad), so a tactic
# that beats this player's habits spreads and one that gets ground down dies.
# Mutation step grows with pressure. The pool is plain data (saved with the
# learned state) and never changes a squad's stats or tier - only behaviour.
#
# Caveat: squad fitness also reflects the squad's builds. Genomes are assigned
# to squads at random, so build luck averages out over n; culling needs n>=4.

const SquadTacticsScript = preload("res://scripts/ai/SquadTactics.gd")

const MAX_PER_BASE = 4
const CULL_MIN_N = 4
const CULL_BELOW = 70.0
const REPLACE_MIN_N = 5
const REPLACE_MARGIN = 25.0
const PARENT_MIN_N = 3
const PARENT_MIN_MEAN = 95.0
const UNTESTED_BONUS = 1.25

# gene -> [min, max, step]; "needs" gates which genes apply to an archetype.
const GENES = {
	"flank_share": {"min": 0.2, "max": 0.8, "step": 0.15, "needs": "flank"},
	"arc": {"min": 0.6, "max": 3.14159, "step": 0.5, "needs": "flank"},
	"stage_extra": {"min": 150.0, "max": 520.0, "step": 90.0, "needs": "stage"},
	"timeout": {"min": 3.0, "max": 10.0, "step": 1.5, "needs": "stage"},
	"standoff": {"min": 0.7, "max": 1.4, "step": 0.15, "needs": "goals"},
	"lead_bonus": {"min": -0.2, "max": 0.3, "step": 0.1, "needs": ""},
	"replan_after": {"min": 6.0, "max": 18.0, "step": 3.0, "needs": ""},
}
const FLAG_CHANCE = 0.2

static func seed_genome(base: String) -> Dictionary:
	if not SquadTacticsScript.PLANS.has(base):
		base = "swarm"
	return {"id": base, "base": base, "params": {}, "n": 0, "mean": 100.0, "gen": 0, "parent": ""}

# Founding pool: one genome per archetype, optionally inheriting old per-plan stats.
static func seed_pool(legacy_stats: Dictionary = {}) -> Dictionary:
	var pool = {}
	for base in SquadTacticsScript.PLANS:
		var g = seed_genome(base)
		var st = legacy_stats.get(base)
		if st is Dictionary:
			g["n"] = int(st.get("n", 0))
			g["mean"] = float(st.get("mean", 100.0))
		pool[base] = g
	return pool

# Effective plan config: archetype defaults overlaid with the genome's params.
static func cfg_of(g: Dictionary) -> Dictionary:
	return SquadTacticsScript.cfg_for(g)

static func base_min_wave(g: Dictionary) -> int:
	return int(SquadTacticsScript.plan_cfg(str(g.get("base", "swarm"))).get("min_wave", 0))

static func _applies(need: String, cfg: Dictionary) -> bool:
	match need:
		"flank":
			return float(cfg.get("flank_share", 0.0)) > 0.0
		"stage":
			return bool(cfg.get("stage", false))
		"goals":
			return bool(cfg.get("stage", false)) or bool(cfg.get("ring", false)) or bool(cfg.get("bait", false)) or float(cfg.get("flank_share", 0.0)) > 0.0
	return true

static func available(pool: Dictionary, wave: int) -> Array:
	var out = []
	for id in pool:
		if wave >= base_min_wave(pool[id]):
			out.append(id)
	out.sort() # deterministic iteration for seeded rng
	return out

# Two-stage pick: archetype first (anti-repeat, outcome, pressure), then a
# genome within it (outcome-weighted, untested mutants get a fair trial).
# Returns a genome id. `recent` holds archetype names.
# Weight multiplier for the squad template's preferred archetype.
const BIAS_WEIGHT = 2.5

static func choose(wave: int, pressure: float, recent: Array, pool: Dictionary, exclude_base: String = "", rng: RandomNumberGenerator = null, bias: String = "", habit_mult: Dictionary = {}) -> String:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var ids = available(pool, wave)
	if ids.is_empty():
		return "swarm"
	var by_base = {}
	for id in ids:
		var b = str(pool[id]["base"])
		if not by_base.has(b):
			by_base[b] = []
		by_base[b].append(id)
	var bases = by_base.keys()
	bases.sort()
	if exclude_base != "" and bases.size() > 1:
		bases.erase(exclude_base)
	var base: String
	if bases.size() == 1:
		base = bases[0]
	elif rng.randf() < min(0.25, 0.05 * pressure):
		base = bases[rng.randi() % bases.size()]
	else:
		var weights = []
		var total = 0.0
		for b in bases:
			var w = float(SquadTacticsScript.plan_cfg(b).get("weight", 1.0))
			var seen = 0
			for r in recent:
				if r == b:
					seen += 1
			w *= pow(0.5, seen)
			if bias != "" and b == bias:
				w *= BIAS_WEIGHT
			w *= clamp(float(habit_mult.get(b, 1.0)), 0.25, 3.0)
			var n_sum = 0
			var m_sum = 0.0
			for id in by_base[b]:
				var g = pool[id]
				n_sum += int(g["n"])
				m_sum += float(g["mean"]) * int(g["n"])
			if n_sum >= 3:
				w *= clamp(0.6 + (m_sum / n_sum) / 250.0, 0.6, 1.4)
			if b == "swarm":
				w /= (1.0 + pressure)
			else:
				w *= 1.0 + 0.15 * pressure
			weights.append(w)
			total += w
		base = bases[bases.size() - 1]
		var roll = rng.randf() * total
		for i in range(bases.size()):
			roll -= weights[i]
			if roll <= 0.0:
				base = bases[i]
				break
	var cands = by_base[base]
	if cands.size() == 1:
		return cands[0]
	var gw = []
	var gt = 0.0
	for id in cands:
		var g = pool[id]
		var w = UNTESTED_BONUS if int(g["n"]) < PARENT_MIN_N else clamp(0.6 + float(g["mean"]) / 250.0, 0.6, 1.4)
		gw.append(w)
		gt += w
	var r2 = rng.randf() * gt
	for i in range(cands.size()):
		r2 -= gw[i]
		if r2 <= 0.0:
			return cands[i]
	return cands[cands.size() - 1]

# Folds a squad's par-normalised fitness into a genome's running mean.
static func record(pool: Dictionary, id: String, normalized: float) -> void:
	var g = pool.get(id)
	if not (g is Dictionary):
		return
	var n = int(g["n"]) + 1
	g["mean"] = lerp(float(g["mean"]), normalized, max(1.0 / n, 0.1)) if int(g["n"]) > 0 else normalized
	g["n"] = n

static func mutate(parent: Dictionary, serial: int, rng: RandomNumberGenerator, pressure: float) -> Dictionary:
	var child = {
		"id": "%s.%d" % [parent["base"], serial], "base": parent["base"],
		"params": parent.get("params", {}).duplicate(), "n": 0, "mean": 100.0,
		"gen": int(parent.get("gen", 0)) + 1, "parent": parent["id"],
	}
	var scale = 1.0 + 0.25 * pressure
	var changed = false
	var tries = 0
	while not changed and tries < 6:
		tries += 1
		var cfg = cfg_of(child)
		if rng.randf() < FLAG_CHANCE:
			changed = _toggle_flag(child, cfg, rng) or changed
		var genes = []
		for k in GENES:
			if _applies(str(GENES[k]["needs"]), cfg):
				genes.append(k)
		genes.sort()
		var count = 2 if rng.randf() < 0.4 else 1
		for i in range(count):
			if genes.is_empty():
				break
			var key: String = genes[rng.randi() % genes.size()]
			var spec = GENES[key]
			var cur = float(cfg.get(key, _default_for(key)))
			var nv = clamp(cur + rng.randfn(0.0, float(spec["step"]) * scale), float(spec["min"]), float(spec["max"]))
			if abs(nv - cur) > float(spec["step"]) * 0.15:
				child["params"][key] = snappedf(nv, 0.01)
				cfg[key] = child["params"][key]
				changed = true
	return child

static func _default_for(key: String) -> float:
	match key:
		"standoff": return 1.0
		"lead_bonus": return 0.0
		"replan_after": return SquadTacticsScript.REPLAN_AFTER
		"stage_extra": return 300.0
		"timeout": return 6.0
	return 0.0

static func _toggle_flag(child: Dictionary, cfg: Dictionary, rng: RandomNumberGenerator) -> bool:
	var params: Dictionary = child["params"]
	if float(cfg.get("flank_share", 0.0)) > 0.0 and not cfg.get("bait", false) and rng.randf() < 0.5:
		params["split"] = not bool(cfg.get("split", false))
		return true
	if not bool(cfg.get("bait", false)):
		var staged = not bool(cfg.get("stage", false))
		params["stage"] = staged
		if staged:
			params["stage_extra"] = float(cfg.get("stage_extra", 300.0))
			params["timeout"] = float(cfg.get("timeout", 6.0))
		return true
	return false

# After a genome is credited: cull proven losers, and breed from a proven
# winner. Returns {"born": Dictionary or {}, "culled": Array}.
static func evolve(pool: Dictionary, id: String, serial: int, rng: RandomNumberGenerator, pressure: float) -> Dictionary:
	var out = {"born": {}, "culled": []}
	var g = pool.get(id)
	if not (g is Dictionary):
		return out
	var base = str(g["base"])
	var family = []
	for k in pool:
		if pool[k]["base"] == base:
			family.append(k)
	family.sort()
	for k in family:
		var e = pool[k]
		if family.size() - out["culled"].size() > 1 and int(e["n"]) >= CULL_MIN_N and float(e["mean"]) < CULL_BELOW:
			pool.erase(k)
			out["culled"].append(k)
	if not pool.has(id):
		return out
	var live = family.size() - out["culled"].size()
	var chance = min(0.85, 0.5 + 0.1 * pressure)
	if int(g["n"]) < PARENT_MIN_N or float(g["mean"]) < PARENT_MIN_MEAN or rng.randf() >= chance:
		return out
	if live >= MAX_PER_BASE:
		var worst = ""
		for k in family:
			if pool.has(k) and k != id and int(pool[k]["n"]) >= REPLACE_MIN_N and float(pool[k]["mean"]) < float(g["mean"]) - REPLACE_MARGIN:
				if worst == "" or float(pool[k]["mean"]) < float(pool[worst]["mean"]):
					worst = k
		if worst == "":
			return out
		pool.erase(worst)
		out["culled"].append(worst)
	var child = mutate(g, serial, rng, pressure)
	pool[child["id"]] = child
	out["born"] = child
	return out

static func describe(g: Dictionary) -> String:
	var parts = []
	var params = g.get("params", {})
	var keys = params.keys()
	keys.sort()
	for k in keys:
		var v = params[k]
		parts.append("%s=%s" % [k, ("%.2f" % v) if v is float else str(v)])
	return "%s gen%d n=%d mean=%.0f [%s]" % [g.get("id", "?"), int(g.get("gen", 0)), int(g.get("n", 0)), float(g.get("mean", 100.0)), ", ".join(parts)]

# Loads untrusted saved data into a valid pool, dropping anything malformed.
static func sanitize(raw: Variant) -> Dictionary:
	var pool = {}
	if not (raw is Dictionary):
		return pool
	for id in raw:
		var g = raw[id]
		if not (g is Dictionary) or not SquadTacticsScript.PLANS.has(str(g.get("base", ""))):
			continue
		var params = {}
		if g.get("params") is Dictionary:
			for k in g["params"]:
				var key = str(k)
				var v = g["params"][k]
				if GENES.has(key) and (v is float or v is int):
					params[key] = clamp(float(v), float(GENES[key]["min"]), float(GENES[key]["max"]))
				elif (key == "stage" or key == "split") and v is bool:
					params[key] = v
		pool[str(id)] = {
			"id": str(id), "base": str(g["base"]), "params": params,
			"n": int(g.get("n", 0)), "mean": float(g.get("mean", 100.0)),
			"gen": int(g.get("gen", 0)), "parent": str(g.get("parent", "")),
			"origin": str(g.get("origin", "")).substr(0, 40),
		}
	return pool

# Every archetype must stay represented so selection always has an option.
static func ensure_archetypes(pool: Dictionary) -> void:
	for base in SquadTacticsScript.PLANS:
		var has_one = false
		for id in pool:
			if pool[id]["base"] == base:
				has_one = true
				break
		if not has_one:
			pool[base] = seed_genome(base)

# --- sharing ---------------------------------------------------------------------

const IMMIGRANT_SLACK = 2 # a family may exceed MAX_PER_BASE by this much while immigrants are on trial
const IMMIGRANT_MAX = 4 # accepted per import
const IMMIGRANT_POOL_SHARE = 0.34

# Genomes worth sharing: anything that has proven itself locally, never the
# bare founding archetypes (those everyone already has).
static func exportable(pool: Dictionary, limit: int = 12) -> Dictionary:
	var ids = []
	for id in pool:
		var g = pool[id]
		if not g.get("params", {}).is_empty() and int(g.get("n", 0)) >= PARENT_MIN_N and float(g.get("mean", 0.0)) >= PARENT_MIN_MEAN:
			ids.append(id)
	ids.sort_custom(func(a, b): return float(pool[a]["mean"]) > float(pool[b]["mean"]))
	var out = {}
	for id in ids.slice(0, limit):
		out[id] = pool[id]
	return out

# Uniform crossover of two same-archetype genomes: each gene/flag comes from
# one parent (or their midpoint for numeric genes).
static func cross(a: Dictionary, b: Dictionary, serial: int, rng: RandomNumberGenerator, origin: String = "") -> Dictionary:
	var params = {}
	var keys = {}
	for k in a.get("params", {}):
		keys[k] = true
	for k in b.get("params", {}):
		keys[k] = true
	var ks = keys.keys()
	ks.sort()
	for k in ks:
		var va = a.get("params", {}).get(k)
		var vb = b.get("params", {}).get(k)
		if va == null or vb == null:
			params[k] = va if va != null else vb
		elif va is bool or vb is bool:
			params[k] = va if rng.randf() < 0.5 else vb
		else:
			params[k] = snappedf((float(va) + float(vb)) / 2.0 if rng.randf() < 0.4 else (float(va) if rng.randf() < 0.5 else float(vb)), 0.01)
	return {
		"id": "%s.h%d" % [a["base"], serial], "base": a["base"], "params": params, "n": 0, "mean": 100.0,
		"gen": max(int(a.get("gen", 0)), int(b.get("gen", 0))) + 1, "parent": "%s+%s" % [a["id"], b["id"]], "origin": "",
	}

static func _family(pool: Dictionary, base: String) -> Array:
	var out = []
	for k in pool:
		if pool[k]["base"] == base:
			out.append(k)
	out.sort()
	return out

# Folds another pilot's proven genomes into the pool as untested immigrants
# (n=0, neutral mean, tagged with their origin), and breeds one hybrid of each
# with a local genome of the same archetype so the trait can mix in. Capped per
# import, one live immigrant per archetype, and a share of the pool.
# Returns {"added": [ids], "hybrids": [ids], "serial": next serial}.
static func immigrate(pool: Dictionary, incoming_raw: Variant, serial: int, pilot: String, rng: RandomNumberGenerator) -> Dictionary:
	var out = {"added": [], "hybrids": [], "serial": serial}
	var incoming = sanitize(incoming_raw)
	var ids = incoming.keys()
	ids.sort_custom(func(a, b): return float(incoming[a]["mean"]) > float(incoming[b]["mean"]))
	for id in ids:
		if out["added"].size() >= IMMIGRANT_MAX:
			break
		var g = incoming[id]
		if g["params"].is_empty():
			continue
		if int(g["n"]) < PARENT_MIN_N or float(g["mean"]) < PARENT_MIN_MEAN:
			continue
		var base = str(g["base"])
		var fam = _family(pool, base)
		if fam.size() >= MAX_PER_BASE + IMMIGRANT_SLACK:
			continue
		var has_immigrant = false
		var dup = false
		for k in fam:
			if _on_trial(pool[k]):
				has_immigrant = true
			if pool[k]["params"] == g["params"]:
				dup = true
		if has_immigrant or dup:
			continue
		if float(_immigrant_count(pool) + 1) / float(pool.size() + 1) > IMMIGRANT_POOL_SHARE:
			break
		var imm = {
			"id": "%s.i%d" % [base, out["serial"]], "base": base, "params": g["params"].duplicate(), "n": 0, "mean": 100.0,
			"gen": int(g["gen"]), "parent": "", "origin": pilot.substr(0, 40) if pilot != "" else "Unknown Pilot",
		}
		out["serial"] += 1
		pool[imm["id"]] = imm
		out["added"].append(imm["id"])
		var locals = []
		for k in fam:
			if str(pool[k].get("origin", "")) == "":
				locals.append(k)
		if not locals.is_empty() and _family(pool, base).size() < MAX_PER_BASE + IMMIGRANT_SLACK:
			locals.sort_custom(func(a, b): return float(pool[a]["mean"]) > float(pool[b]["mean"]))
			var partner = pool[locals[0]]
			var hyb = cross(imm, partner, out["serial"], rng)
			out["serial"] += 1
			if hyb["params"] != imm["params"] and hyb["params"] != partner["params"]:
				pool[hyb["id"]] = hyb
				out["hybrids"].append(hyb["id"])
	return out

static func _immigrant_count(pool: Dictionary) -> int:
	var n = 0
	for k in pool:
		if _on_trial(pool[k]):
			n += 1
	return n

# An immigrant stays "on trial" until it has REPLACE_MIN_N credited squads.
static func _on_trial(g: Dictionary) -> bool:
	return str(g.get("origin", "")) != "" and int(g.get("n", 0)) < REPLACE_MIN_N
