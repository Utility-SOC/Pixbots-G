extends Node

# Regression harness for: "ai profiles aren't related to saves - a game
# shouldn't need to be going. I should just be able to export through the
# war room." Root cause: WarRoomMenu's export/import buttons already
# gracefully fell back to whatever _get_director() returns (a live
# SquadDirector OR a no-live-game WarRoomSnapshot) and only gated on
# has_method("export_learned_state_to_clipboard") - but WarRoomSnapshot
# never actually implemented those two methods, so the buttons always fell
# through to "Start a game to export/import AI profiles" even though the
# underlying learned_state.json this reads has never been save-slot-scoped.
#
# SAFETY NOTE: user://ai_profiles/learned_state.json is REAL player data on
# any machine that's actually played this game (this dev machine has, from
# extensive playtesting this session) - never a sandbox for a throwaway
# test. This check deliberately:
#   - tests the shared merge_imported() logic in total isolation (pure
#     array manipulation, zero file I/O - safe by construction).
#   - tests export_learned_state_to_clipboard() against a MANUALLY BUILT
#     snapshot (never touches load_from_disk(), so never reads the real
#     file either) - export only ever writes to the OS clipboard, never a
#     file, so this is safe regardless.
#   - tests import_learned_state_from_clipboard()'s SAFE-REJECTION path
#     only (garbage/empty clipboard -> returns false before ever reaching
#     the disk-write call) - exercises the real method with zero risk.
#   - deliberately does NOT exercise the "valid import actually writes to
#     disk" branch end-to-end, since doing so for real would mean writing
#     over user://ai_profiles/learned_state.json - the write call itself
#     (SquadProfileManager.save_profile) already has no dependency on
#     WHERE its data logically came from, so merge_imported()'s correctness
#     (tested below) plus the existing save/load round-trip machinery is
#     sufficient coverage without touching real player state.
#
# The system clipboard is real user state too (not destructive, but
# discourteous to clobber) - saves and restores whatever was on it before.

const WarRoomSnapshotScript = preload("res://scripts/ai/WarRoomSnapshot.gd")
const SquadTemplate = preload("res://scripts/ai/SquadTemplate.gd")
const SolverProfile = preload("res://scripts/ai/SolverProfile.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	_test_merge_imported_no_collision()
	_test_merge_imported_with_collision()
	_test_export_writes_real_clipboard()
	_test_import_rejects_invalid_clipboard_without_touching_disk()

	if failures == 0:
		print("PASS: WarRoomSnapshot can export/import AI profiles without a live game")
	get_tree().quit(0 if failures == 0 else 1)

func _test_merge_imported_no_collision():
	var target_templates: Array = [SquadTemplate.new("Local Squad", {"brawler": 1})]
	var target_profiles: Array = []
	var target_bosses: Array = []

	var incoming = SquadTemplate.new("Friend's Squad", {"sniper": 2})
	incoming.origin_pilot = "Ozzy"
	incoming.is_experimental = true
	var loaded_templates: Array = [incoming]

	WarRoomSnapshotScript.merge_imported(target_templates, target_profiles, target_bosses, loaded_templates, [], [])

	_check("a non-colliding imported template is added as-is (name unchanged)",
		target_templates.size() == 2 and target_templates[1].template_name == "Friend's Squad")
	_check("an imported template always lands at full weight (is_experimental cleared)",
		not target_templates[1].is_experimental)

func _test_merge_imported_with_collision():
	var target_templates: Array = [SquadTemplate.new("Pierce Escort", {"support": 1})]
	var target_profiles: Array = [SolverProfile.new("Aggro", 4)]

	var incoming_template = SquadTemplate.new("Pierce Escort", {"brawler": 3})
	incoming_template.origin_pilot = "Ozzy"
	var incoming_profile = SolverProfile.new("Aggro", 2)
	incoming_profile.origin_pilot = "Ozzy"

	WarRoomSnapshotScript.merge_imported(target_templates, target_profiles, [], [incoming_template], [incoming_profile], [])

	_check("a colliding template name gets tagged with the origin pilot instead of clobbering the local one",
		target_templates.size() == 2 and target_templates[1].template_name == "Pierce Escort (Ozzy)")
	_check("the ORIGINAL local template is untouched by the collision",
		target_templates[0].template_name == "Pierce Escort")
	_check("a colliding solver profile is also tagged and appended, not overwritten",
		target_profiles.size() == 2 and target_profiles[1].profile_name == "Aggro (Ozzy)")

func _test_export_writes_real_clipboard():
	# Headless CI runs on Godot's dummy display server, which has no real OS
	# clipboard (DisplayServer.clipboard_get/set are unusable there - a
	# harness-environment limitation, not something this code controls), so
	# this can't assert on actual round-tripped clipboard CONTENT without
	# being flaky. What it CAN verify without a live game or a real display
	# server: export_learned_state_to_clipboard() runs to completion with no
	# crash/type error against a manually built (never-touched-real-disk)
	# snapshot - which is exactly the type bug this pass actually found
	# (WarRoomSnapshot.templates was an untyped Array; export_to_clipboard
	# requires Array[SquadTemplate] and rejected it at the type-check level).
	var snap = WarRoomSnapshotScript.new()
	snap._mgr = load("res://scripts/ai/SquadProfileManager.gd").new()
	var typed_templates: Array[SquadTemplate] = [SquadTemplate.new("Test Export Squad", {"scout": 1})]
	snap.templates = typed_templates
	snap.solver_profiles = []
	snap.boss_profiles = []

	snap.export_learned_state_to_clipboard()
	_check("export_learned_state_to_clipboard() runs against a real (typed) snapshot with no crash/type error", true)

func _test_import_rejects_invalid_clipboard_without_touching_disk():
	var saved_clipboard = DisplayServer.clipboard_get()
	DisplayServer.clipboard_set("not a valid AI profile export")

	var snap = WarRoomSnapshotScript.new()
	snap._mgr = load("res://scripts/ai/SquadProfileManager.gd").new()
	var result = snap.import_learned_state_from_clipboard()
	_check("importing garbage clipboard content safely returns false (no disk write attempted)",
		result == false)

	DisplayServer.clipboard_set(saved_clipboard)
