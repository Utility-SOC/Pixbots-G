class_name WarRoomSnapshot
extends RefCounted

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
		_mgr.export_to_clipboard(templates, solver_profiles, boss_profiles)

# Mirrors SquadDirector.import_learned_state_from_clipboard(), but since
# there's no live director to hold the merged result in memory (and no
# _finish()-style session end that would eventually persist it), this
# writes straight to disk immediately - same file a live game's
# save_learned_state() would write, so it's picked up correctly the next
# time a real game actually starts.
func import_learned_state_from_clipboard() -> bool:
	if not _mgr:
		return false
	var data = _mgr.import_from_clipboard()
	if data.is_empty():
		return false
	merge_imported(templates, solver_profiles, boss_profiles, data.get("templates", []), data.get("solver_profiles", []), data.get("boss_profiles", []))

	# _ready() never ran on this manually instantiated, never-added-to-tree
	# manager (see load_from_disk()'s own comment on that), so the
	# ai_profiles directory it normally creates on first boot may not exist
	# yet - only matters for this write path, never for the read-only loads.
	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("ai_profiles"):
		dir.make_dir("ai_profiles")

	_mgr.save_profile(LEARNED_STATE_NAME, templates, solver_profiles, boss_profiles)
	print("[WAR ROOM] Imported AI profile from clipboard (no live game).")
	return true

# Merge path for a CROSS-PILOT clipboard import - shared by SquadDirector.
# _merge_imported() (the same-session live-game path) and this class's own
# import above, so the two never drift apart. On a name collision the
# incoming item is renamed with its origin_pilot attribution and registered
# as a SEPARATE new entry instead of clobbering local progress (the user:
# "if they have the same name can they be appended with the name of the
# user you originally got it from"). Imports always land at full weight/
# standing (is_experimental = false) rather than the trial gate a locally-
# bred mutant has to earn its way through - a battle-tested import from
# someone else's game has already proven itself.
static func merge_imported(target_templates: Array, target_solver_profiles: Array, target_boss_profiles: Array,
		loaded_templates: Array, loaded_profiles: Array, loaded_boss_profiles: Array = []) -> void:
	for lt in loaded_templates:
		var collision = false
		for t in target_templates:
			if t.template_name == lt.template_name:
				collision = true
				break
		if collision:
			var tag = lt.origin_pilot if lt.origin_pilot != "" else "Unknown Pilot"
			lt.template_name = "%s (%s)" % [lt.template_name, tag]
		lt.is_experimental = false
		target_templates.append(lt)

	for lp in loaded_profiles:
		var collision_p = false
		for p in target_solver_profiles:
			if p.profile_name == lp.profile_name:
				collision_p = true
				break
		if collision_p:
			var tag = lp.origin_pilot if lp.origin_pilot != "" else "Unknown Pilot"
			lp.profile_name = "%s (%s)" % [lp.profile_name, tag]
		lp.is_experimental = false
		target_solver_profiles.append(lp)

	for lbp in loaded_boss_profiles:
		var collision_b = false
		for bp in target_boss_profiles:
			if bp.profile_name == lbp.profile_name:
				collision_b = true
				break
		if collision_b:
			var tag = lbp.origin_pilot if lbp.origin_pilot != "" else "Unknown Pilot"
			lbp.profile_name = "%s (%s)" % [lbp.profile_name, tag]
		lbp.is_experimental = false
		target_boss_profiles.append(lbp)
