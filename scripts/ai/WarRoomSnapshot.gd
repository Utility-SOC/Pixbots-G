class_name WarRoomSnapshot
extends RefCounted

const TacticGenome = preload("res://scripts/ai/TacticGenome.gd")
const GenePool = preload("res://scripts/ai/GenePool.gd")
const SquadTemplateMutator = preload("res://scripts/ai/SquadTemplateMutator.gd")

# Read-only stand-in for a live SquadDirector, built straight from the saved
# learned_state.json - lets the War Room be opened from the Main Menu (no
# game running yet, no director in the scene tree) and still show real
# templates/telemetry from the last session instead of just "no data yet".
# Exposes exactly the fields WarRoomMenu.gd actually reads off a live
# director; anything combat-live-only (active_squads, wild_bots) is just
# left empty rather than faked - the "FIELD STATUS" section degrades to
# "0 active squads" gracefully, same as a fresh save with no combat yet.

var templates: Array[SquadTemplate] = []
var solver_profiles: Array = []
var boss_profiles: Array = []
var stock_builds: Array = []
var active_squads: Array = []
var wild_bots: Array = []
var total_damage_taken: float = 0.0
var player_element_usage: Dictionary = {}
var bot_element_usage: Dictionary = {}
var total_bot_damage_dealt: float = 0.0
var player_kill_methods: Dictionary = {}
var total_player_kills: int = 0
var captured_loadouts: Dictionary = {}

# Kept from load_from_disk() specifically so export/import below can reuse
# the exact same profile-manager instance/settings instead of re-resolving
# the moddable-baseline-pack path a second time.
var _mgr = null
var last_import_report: Dictionary = {}

static func _new_rng() -> RandomNumberGenerator:
	var r = RandomNumberGenerator.new()
	r.randomize()
	return r

const LEARNED_STATE_NAME = "learned_state"

# Explicit load()+new() rather than the bare class_name identifier - this
# codebase has hit the "global class_name cache is stale for a newly-added
# class referencing itself" compile error before (see SquadProfileManager.gd's
# header comment for the same defensive pattern applied to a different file).
static func load_from_disk():
	var snap = load("res://scripts/ai/WarRoomSnapshot.gd").new()
	var mgr = load("res://scripts/ai/SquadProfileManager.gd").new()
	snap._mgr = mgr
	# _ready() never runs on a manually instantiated Node kept outside the
	# tree, but has_profile()/load_*() only ever touch FileAccess - no
	# dependency on _ready()'s ai_profiles-directory creation, which only
	# matters for saving.
	if not mgr.has_profile(LEARNED_STATE_NAME):
		return snap

	snap.templates = mgr.load_profile(LEARNED_STATE_NAME)
	snap.solver_profiles = mgr.load_solver_profiles(LEARNED_STATE_NAME)
	snap.boss_profiles = mgr.load_boss_profiles(LEARNED_STATE_NAME)
	snap.stock_builds = mgr.load_stock_builds(LEARNED_STATE_NAME)

	var telemetry = mgr.load_telemetry(LEARNED_STATE_NAME)
	if telemetry.get("player_element_usage") is Dictionary:
		snap.player_element_usage = telemetry["player_element_usage"]
	snap.total_damage_taken = float(telemetry.get("total_damage_taken", 0.0))
	if telemetry.get("bot_element_usage") is Dictionary:
		snap.bot_element_usage = telemetry["bot_element_usage"]
	snap.total_bot_damage_dealt = float(telemetry.get("total_bot_damage_dealt", 0.0))
	if telemetry.get("player_kill_methods") is Dictionary:
		snap.player_kill_methods = telemetry["player_kill_methods"]
	snap.total_player_kills = int(telemetry.get("total_player_kills", 0))

	var captures = mgr.load_telemetry(LEARNED_STATE_NAME + "_captures")
	if not captures.is_empty():
		snap.captured_loadouts = captures
	return snap

# --- Export/Import without a live game --------------------------------------
# Per the user: "ai profiles aren't related to saves - a game shouldn't need
# to be going. I should just be able to export through the war room." The
# learned-state file this reads is already independent of any save slot
# (SquadDirector reads/writes the exact same user://ai_profiles/learned_
# state.json regardless of which save is active), so there was never a real
# reason export/import needed a live SquadDirector - WarRoomMenu.gd's
# buttons already fall back to whatever _get_director() returns and only
# checked has_method("export_learned_state_to_clipboard") to decide whether
# to offer it, so simply having THIS class implement the same two methods a
# live SquadDirector does is the entire fix - no UI changes needed.
func export_learned_state_to_clipboard():
	if _mgr:
		_mgr.export_to_clipboard(templates, solver_profiles, boss_profiles, stock_builds, _saved_tactic_pool())

# Mirrors SquadDirector.import_learned_state_from_clipboard(), but since
# there's no live director to hold the merged result in memory (and no
# _finish()-style session end that would eventually persist it), this
# writes straight to disk immediately - same file a live game's
# save_learned_state() would write, so it's picked up correctly the next
# time a real game actually starts.
func import_learned_state_from_clipboard() -> bool:
	if not _mgr:
		return false
	return import_gene_payload(_mgr.import_from_clipboard())

func import_raw_payload(raw: Dictionary) -> bool:
	if not _mgr:
		return false
	return import_gene_payload(_mgr.parse_payload(raw))

func build_gene_export(compact: bool = true) -> Dictionary:
	if not _mgr:
		return {}
	return _mgr.build_export_payload(templates, solver_profiles, boss_profiles, stock_builds, _saved_tactic_pool(), compact)

func gene_diversity() -> Dictionary:
	return GenePool.diversity(templates, solver_profiles, _saved_tactic_pool(), stock_builds)

func _saved_tactic_pool() -> Dictionary:
	if _mgr == null or not _mgr.has_profile(LEARNED_STATE_NAME):
		return {}
	var tel = _mgr.load_telemetry(LEARNED_STATE_NAME)
	return TacticGenome.sanitize(tel.get("tactic_pool")) if tel.get("tactic_pool") is Dictionary else {}

# Shared by the clipboard path above and style-card imports. Persists straight
# to the learned-state file; the existing telemetry (PlayerModel, tactic pool,
# ...) is read back and rewritten so an import can never wipe it.
func import_gene_payload(data: Dictionary) -> bool:
	if data.is_empty() or _mgr == null:
		return false
	var telemetry: Dictionary = _mgr.load_telemetry(LEARNED_STATE_NAME) if _mgr.has_profile(LEARNED_STATE_NAME) else {}
	var pool = TacticGenome.sanitize(telemetry.get("tactic_pool")) if telemetry.get("tactic_pool") is Dictionary else TacticGenome.seed_pool()
	TacticGenome.ensure_archetypes(pool)
	var res = TacticGenome.immigrate(pool, data.get("tactic_pool", {}), int(telemetry.get("tactic_serial", 1)), str(data.get("pilot", "")), _new_rng())
	telemetry["tactic_pool"] = pool
	telemetry["tactic_serial"] = res["serial"]
	last_import_report = merge_imported(templates, solver_profiles, boss_profiles, data.get("templates", []), data.get("solver_profiles", []), data.get("boss_profiles", []), stock_builds, data.get("stock_builds", []))

	# _ready() never ran on this manually instantiated, never-added-to-tree
	# manager (see load_from_disk()'s own comment on that), so the
	# ai_profiles directory it normally creates on first boot may not exist
	# yet - only matters for this write path, never for the read-only loads.
	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("ai_profiles"):
		dir.make_dir("ai_profiles")

	last_import_report["tactics"] = res["added"].size() + res["hybrids"].size()
	_mgr.save_profile(LEARNED_STATE_NAME, templates, solver_profiles, boss_profiles, stock_builds, telemetry)
	print("[WAR ROOM] Imported AI profile from clipboard (no live game).")
	return true

# Merge path for a CROSS-PILOT import (clipboard or style card) - shared by
# SquadDirector._merge_imported() (live game) and this class's own no-live-game
# import above. Everything arriving here is untrusted and lands on PROBATION
# (see GenePool): sanitized, capped per import, flagged experimental with the
# exporter's record cleared, so it has to beat THIS player's habits before it
# counts as core. On a name collision the incoming item is renamed with its
# origin_pilot and registered as a separate entry instead of clobbering local
# progress; re-importing the same export is a no-op (exact duplicates skipped).
# Imported templates are also crossbred with the best local template right
# away (capped hybrids), so their traits mix in rather than merely co-exist.
# Returns a report {"templates", "profiles", "bosses", "builds", "donors",
# "hybrids", "skipped"} for the UI.
static func merge_imported(target_templates: Array, target_solver_profiles: Array, target_boss_profiles: Array,
		loaded_templates: Array, loaded_profiles: Array, loaded_boss_profiles: Array = [],
		target_stock_builds: Array = [], loaded_stock_builds: Array = []) -> Dictionary:
	var report = {"templates": 0, "profiles": 0, "bosses": 0, "builds": 0, "donors": 0, "hybrids": 0, "skipped": 0}
	var renamed: Dictionary = {} # incoming template name -> accepted local name
	var accepted_templates: Array = []

	var considered = 0
	for lt in GenePool.top_by_fitness(loaded_templates, GenePool.MAX_LIST):
		# Duplicates count against the cap too, so re-importing one export
		# keeps looking at the same top entries and changes nothing.
		considered += 1
		if considered > GenePool.TEMPLATE_CAP:
			report["skipped"] += 1
			continue
		var original_name = lt.template_name
		if not GenePool.sanitize_template(lt):
			report["skipped"] += 1
			continue
		var dup = false
		var collision = false
		for t in target_templates:
			if t.template_name == lt.template_name:
				collision = true
				# Same name AND same roles from the same pilot = an earlier
				# import of this very template.
				if t.required_roles == lt.required_roles and t.origin_pilot == lt.origin_pilot:
					dup = true
		if collision and not dup:
			var tag = lt.origin_pilot if lt.origin_pilot != "" else "Unknown Pilot"
			lt.template_name = "%s (%s)" % [lt.template_name, tag]
		for t in target_templates:
			if t.template_name == lt.template_name and t.required_roles == lt.required_roles:
				dup = true
		if dup:
			report["skipped"] += 1
			continue
		GenePool.put_on_probation(lt)
		target_templates.append(lt)
		accepted_templates.append(lt)
		renamed[original_name] = lt.template_name
		report["templates"] += 1

	# Breed the incoming doctrine with the best local one.
	var locals: Array = []
	for t in target_templates:
		if not t.is_experimental and t.origin_pilot == "":
			locals.append(t)
	if not locals.is_empty():
		locals = GenePool.top_by_fitness(locals, 1)
		for lt in accepted_templates.slice(0, 2):
			var hybrid = SquadTemplateMutator.crossover(locals[0], lt)
			if hybrid != null:
				hybrid.is_experimental = true
				target_templates.append(hybrid)
				report["hybrids"] += 1

	considered = 0
	for lp in GenePool.top_by_fitness(loaded_profiles, GenePool.MAX_LIST):
		considered += 1
		if considered > GenePool.PROFILE_CAP:
			report["skipped"] += 1
			continue
		var collision_p = false
		var skip_dup = false
		for p in target_solver_profiles:
			if p.profile_name == lp.profile_name:
				collision_p = true
				if p.origin_pilot != "" and p.origin_pilot == lp.origin_pilot:
					collision_p = false
					skip_dup = true
				break
		if skip_dup:
			report["skipped"] += 1
			continue
		if collision_p:
			var tag = lp.origin_pilot if lp.origin_pilot != "" else "Unknown Pilot"
			lp.profile_name = "%s (%s)" % [lp.profile_name, tag]
			var again = false
			for p in target_solver_profiles:
				if p.profile_name == lp.profile_name:
					again = true
			if again:
				report["skipped"] += 1
				continue
		GenePool.put_on_probation(lp)
		target_solver_profiles.append(lp)
		report["profiles"] += 1

	considered = 0
	for lbp in GenePool.top_by_fitness(loaded_boss_profiles, GenePool.MAX_LIST):
		considered += 1
		if considered > GenePool.BOSS_CAP:
			report["skipped"] += 1
			continue
		var collision_b = false
		var skip_dup = false
		for bp in target_boss_profiles:
			if bp.profile_name == lbp.profile_name:
				collision_b = true
				if bp.origin_pilot != "" and bp.origin_pilot == lbp.origin_pilot:
					collision_b = false
					skip_dup = true
				break
		if skip_dup:
			report["skipped"] += 1
			continue
		if collision_b:
			var tag = lbp.origin_pilot if lbp.origin_pilot != "" else "Unknown Pilot"
			lbp.profile_name = "%s (%s)" % [lbp.profile_name, tag]
			var again_b = false
			for bp in target_boss_profiles:
				if bp.profile_name == lbp.profile_name:
					again_b = true
			if again_b:
				report["skipped"] += 1
				continue
		GenePool.put_on_probation(lbp)
		target_boss_profiles.append(lbp)
		report["bosses"] += 1

	# Stock builds: a build for an accepted template rides along under the
	# template's (possibly renamed) name. Everything else good enough becomes a
	# DONOR - kept under a name no template uses, so it can never replace a
	# local champion, only lend one body slot at a time to a deviation candidate
	# (StockBuildEvolution._make_candidate).
	var donors: Array = []
	for lsb in loaded_stock_builds:
		if not GenePool.sanitize_build(lsb):
			report["skipped"] += 1
			continue
		if lsb.origin_pilot == "":
			lsb.origin_pilot = "Unknown Pilot"
		if renamed.has(lsb.template_name):
			lsb.template_name = renamed[lsb.template_name]
			lsb.is_experimental = true
			target_stock_builds.append(lsb)
			report["builds"] += 1
		elif GenePool.donor_quality(lsb) >= GenePool.DONOR_MIN_MEAN:
			donors.append(lsb)
	for lsb in GenePool.top_by_fitness(donors, GenePool.DONOR_CAP):
		lsb.template_name = GenePool.DONOR_PREFIX + lsb.origin_pilot
		lsb.is_experimental = true
		target_stock_builds.append(lsb)
		report["donors"] += 1
	# Bounded store: evict the oldest donors first.
	var donor_idx: Array = []
	for i in range(target_stock_builds.size()):
		if GenePool.is_donor(target_stock_builds[i]):
			donor_idx.append(i)
	while donor_idx.size() > GenePool.DONOR_STORE_CAP:
		target_stock_builds.remove_at(donor_idx[0])
		donor_idx.pop_front()
		for j in range(donor_idx.size()):
			donor_idx[j] -= 1
	return report
