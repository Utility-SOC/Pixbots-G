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

var templates: Array = []
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

const LEARNED_STATE_NAME = "learned_state"

# Explicit load()+new() rather than the bare class_name identifier - this
# codebase has hit the "global class_name cache is stale for a newly-added
# class referencing itself" compile error before (see SquadProfileManager.gd's
# header comment for the same defensive pattern applied to a different file).
static func load_from_disk():
	var snap = load("res://scripts/ai/WarRoomSnapshot.gd").new()
	var mgr = load("res://scripts/ai/SquadProfileManager.gd").new()
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
	return snap
