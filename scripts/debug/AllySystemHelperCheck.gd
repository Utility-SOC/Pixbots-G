extends Node

# Regression harness for AllySystemHelper.get_allies(), extracted from a
# triplicated ~7-line block that used to live separately in
# AegisShieldPulseSystem/HealBeaconSystem/CloakSystem (found by a full-
# codebase audit). HealBeaconSystem's copy was also missing the
# is_inside_tree() guard the other two had - this locks in the safe version
# for all three going forward.

const AllySystemHelperScript = preload("res://scripts/entities/AllySystemHelper.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# --- AI mech: allies come from the "enemy" group ---
	var ai_mech = MechScript.new()
	ai_mech.is_player = false
	add_child(ai_mech)
	await get_tree().process_frame # EntityCache group snapshot needs a fresh frame stamp
	var ai_allies = AllySystemHelperScript.get_allies(ai_mech)
	_check("AI mech's allies come from the 'enemy' group (found itself in it)", ai_allies.has(ai_mech))

	# --- Player mech with no drone_nodes on the scene: empty, no crash ---
	var player_mech = MechScript.new()
	player_mech.is_player = true
	add_child(player_mech)
	var player_allies_no_scene = AllySystemHelperScript.get_allies(player_mech)
	_check("Player mech with no drone_nodes source returns an empty array, not a crash", player_allies_no_scene.is_empty())

	# --- Player mech NOT in the tree: must not crash (the bug HealBeaconSystem's old copy had) ---
	var detached_mech = MechScript.new()
	detached_mech.is_player = true
	var detached_allies = AllySystemHelperScript.get_allies(detached_mech)
	_check("Player mech not in the tree returns empty without crashing (the is_inside_tree() guard)", detached_allies.is_empty())

	if failures == 0:
		print("PASS: AllySystemHelper.get_allies() behaves consistently for AI and player mechs")
	get_tree().quit(0 if failures == 0 else 1)
