extends RefCounted

# Shared-AI plumbing: what an imported AI profile (clipboard JSON or a style
# card PNG) is allowed to do to the local gene pool. Everything arrives as
# untrusted data, is sanitized, and lands on PROBATION - a capped number of
# experimental entries that must earn their keep against this player before
# they count as core. Only genes travel: never PlayerModel, telemetry or
# fitness history that would pollute the receiving director's read of its
# own player.

const SquadTemplateMutator = preload("res://scripts/ai/SquadTemplateMutator.gd")
const SquadTacticsScript = preload("res://scripts/ai/SquadTactics.gd")
const TacticGenomeScript = preload("res://scripts/ai/TacticGenome.gd")

const SCHEMA = 2
const MAX_LIST = 200 # anything longer is hostile or corrupt
const TEMPLATE_CAP = 3
const PROFILE_CAP = 3
const BOSS_CAP = 2
const DONOR_CAP = 8
const DONOR_STORE_CAP = 16
const DONOR_PREFIX = "~donor:"
const DONOR_MIN_MEAN = 90.0
const PROBATION_WEIGHT = 70.0
const EXPORT_BUILD_CAP = 24

# --- export ------------------------------------------------------------------

static func top_by_fitness(items: Array, n: int) -> Array:
	var sorted_items = items.duplicate()
	# Name tie-break keeps the pick deterministic, so re-importing one export
	# always considers the same top entries (and is then a no-op).
	sorted_items.sort_custom(func(a, b):
		var fa = _fitness_of(a)
		var fb = _fitness_of(b)
		if fa != fb:
			return fa > fb
		return _name_of(a) < _name_of(b))
	return sorted_items.slice(0, n)

static func _name_of(item) -> String:
	for k in ["template_name", "profile_name", "boss_name"]:
		if k in item:
			return str(item.get(k))
	return ""

static func _fitness_of(item) -> float:
	if item.has_method("get_average_fitness"):
		var f = float(item.get_average_fitness())
		if f > 0.0:
			return f
	return 0.0

# `compact` (style cards) keeps only the best of each list so the PNG payload
# stays small; the clipboard export sends everything.
static func build_export(templates: Array, profiles: Array, bosses: Array, builds: Array, tactic_pool: Dictionary, pilot: String, compact: bool = false) -> Dictionary:
	if compact:
		templates = top_by_fitness(templates, 6)
		profiles = top_by_fitness(profiles, 5)
		bosses = top_by_fitness(bosses, 4)
		builds = top_by_fitness(builds, EXPORT_BUILD_CAP)
	var out = {"schema": SCHEMA, "pilot": pilot, "templates": [], "solver_profiles": [], "boss_profiles": [], "stock_builds": [], "tactic_pool": TacticGenomeScript.exportable(tactic_pool)}
	for t in templates:
		out["templates"].append(_stamp(t.to_dict(), pilot))
	for p in profiles:
		out["solver_profiles"].append(_stamp(p.to_dict(), pilot))
	for b in bosses:
		out["boss_profiles"].append(_stamp(b.to_dict(), pilot))
	for s in builds:
		out["stock_builds"].append(_stamp(s.to_dict(), pilot))
	return out

# A template bred here becomes "from me" the moment it leaves; an item that
# was already imported keeps crediting its real originator.
static func _stamp(d: Dictionary, pilot: String) -> Dictionary:
	if str(d.get("origin_pilot", "")) == "":
		d["origin_pilot"] = pilot
	return d

# --- sanitizing ---------------------------------------------------------------

static func list_ok(raw) -> bool:
	return raw is Array and raw.size() <= MAX_LIST

# Returns false if the template is unusable. Clamps roles, size and weights so
# a hostile import can't spawn 500-bot squads.
static func sanitize_template(t: SquadTemplate) -> bool:
	var roles: Dictionary = {}
	if t.required_roles is Dictionary:
		for k in t.required_roles:
			var role = str(k)
			if not SquadTemplateMutator.ALL_ROLES.has(role):
				continue
			var count = int(t.required_roles[k])
			if count >= 1:
				roles[role] = min(count, SquadTemplate.MAX_TOTAL_SIZE)
	if roles.is_empty():
		return false
	t.required_roles = SquadTemplateMutator.clamp_size(roles)
	t.template_name = t.template_name.substr(0, 60)
	if t.tactic_bias != "" and not SquadTacticsScript.PLANS.has(t.tactic_bias):
		t.tactic_bias = ""
	t.formation_spread = clamp(t.formation_spread, SquadTemplate.SPREAD_MIN, SquadTemplate.SPREAD_MAX)
	t.origin_pilot = t.origin_pilot.substr(0, 40)
	t.parent_name = t.parent_name.substr(0, 60)
	return true

static func sanitize_build(b: StockBuild) -> bool:
	if not (b.serialized_components is Dictionary) or b.serialized_components.is_empty() or b.role == "":
		return false
	for k in b.serialized_components:
		if not (b.serialized_components[k] is Dictionary):
			return false
	b.rarity = clamp(b.rarity, 0, 4)
	b.sub_archetype_slot = clamp(b.sub_archetype_slot, 0, 2)
	b.origin_pilot = b.origin_pilot.substr(0, 40)
	return true

# --- probation -----------------------------------------------------------------

# Clears the exporter's record so the entry is judged on THIS player, and puts
# it on the experimental track (capped, culled if it flops, graduated if not).
static func put_on_probation(item) -> void:
	item.is_experimental = true
	item.spawn_weight = PROBATION_WEIGHT
	item.base_spawn_weight = PROBATION_WEIGHT
	if "times_deployed" in item:
		item.times_deployed = 0
	if "times_used" in item:
		item.times_used = 0
	item.total_fitness = 0.0
	if "fitness_history" in item:
		item.fitness_history = []
	if "recent_fitness_ema" in item:
		item.recent_fitness_ema = 100.0

static func donor_quality(b: StockBuild) -> float:
	if b.fitness_history.is_empty():
		return 100.0
	var total = 0.0
	for f in b.fitness_history:
		total += float(f)
	return total / float(b.fitness_history.size())

static func is_donor(b: StockBuild) -> bool:
	return b.template_name.begins_with(DONOR_PREFIX)

# --- diversity -------------------------------------------------------------------

# Shannon entropy of a count distribution, normalised to 0..1.
static func _entropy(counts: Dictionary) -> float:
	var total = 0.0
	for k in counts:
		total += float(counts[k])
	if total <= 0.0 or counts.size() <= 1:
		return 0.0
	var h = 0.0
	for k in counts:
		var p = float(counts[k]) / total
		if p > 0.0:
			h -= p * log(p)
	return h / log(float(counts.size()))

# Headline numbers for the War Room: how varied is this AI, and how much of it
# came from other pilots. All 0..1 (higher = more varied) except the counts.
static func diversity(templates: Array, profiles: Array, tactic_pool: Dictionary, builds: Array) -> Dictionary:
	var role_counts = {}
	var bias_counts = {}
	var foreign_t = 0
	for t in templates:
		for r in t.required_roles:
			role_counts[r] = role_counts.get(r, 0) + int(t.required_roles[r])
		bias_counts[t.tactic_bias] = bias_counts.get(t.tactic_bias, 0) + 1
		if t.origin_pilot != "":
			foreign_t += 1
	var syn_counts = {}
	var foreign_p = 0
	for p in profiles:
		syn_counts[p.favored_synergy] = syn_counts.get(p.favored_synergy, 0) + 1
		if p.origin_pilot != "":
			foreign_p += 1
	var tactic_counts = {}
	var foreign_g = 0
	for id in tactic_pool:
		var g = tactic_pool[id]
		var key = "%s|%s" % [g.get("base", "?"), JSON.stringify(g.get("params", {}))]
		tactic_counts[key] = 1
		if str(g.get("origin", "")) != "":
			foreign_g += 1
	var splices = 0
	for b in builds:
		if b.splice_from != "":
			splices += 1
	return {
		"role_entropy": _entropy(role_counts),
		"doctrine_entropy": _entropy(bias_counts),
		"synergy_entropy": _entropy(syn_counts),
		"tactic_variants": tactic_counts.size(),
		"foreign_templates": foreign_t,
		"foreign_profiles": foreign_p,
		"foreign_tactics": foreign_g,
		"spliced_builds": splices,
		"immigrant_share": float(foreign_t + foreign_p + foreign_g) / max(1.0, float(templates.size() + profiles.size() + tactic_pool.size())),
	}
