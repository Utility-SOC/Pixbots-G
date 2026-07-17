extends Node

# Regression harness for the "Hit by: Environment" misattribution report:
# a player was killed by a bot's KINETIC weapon hit but the death report
# blamed "Environment". Root cause: Projectile._handle_hit() nulls out
# source_mech if the shooter died mid-flight (Godot rejects a freed Node
# reference even for a nullable param), and Mech._log_incoming_damage()
# fell back to "Environment" whenever source was null/invalid - with no way
# to recover the shooter's identity after the fact. Fix: capture the
# shooter's label at FIRE time (Mech.resolve_attacker_label, while the
# shooter is still alive) and thread it through apply_damage() as
# source_label_override, used only when the live source can't be resolved.

const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0

func _check(label: String, actual, expected):
	if actual != expected:
		push_error("FAIL: %s - got %s, expected %s" % [label, actual, expected])
		failures += 1
	else:
		print("ok: %s = %s" % [label, actual])

func _ready():
	# --- 1. resolve_attacker_label() priority: Rival > Boss > role > Environment ---
	_check("null source resolves to Environment", MechScript.resolve_attacker_label(null), "Environment")

	var boss = MechScript.new()
	boss.is_boss = true
	add_child(boss)
	_check("is_boss source resolves to Boss", MechScript.resolve_attacker_label(boss), "Boss")

	var roled = MechScript.new()
	roled.combat_role = "sniper"
	add_child(roled)
	_check("combat_role source resolves to capitalized role", MechScript.resolve_attacker_label(roled), "Sniper")

	var rival = MechScript.new()
	rival.combat_role = "brawler"
	rival.set_meta("rival_name", "Ozzy")
	add_child(rival)
	_check("rival_name meta takes priority over combat_role", MechScript.resolve_attacker_label(rival), "Rival Ozzy")

	# --- 2. apply_damage: live, valid source resolves normally (unchanged) ---
	var player = MechScript.new()
	player.is_player = true
	add_child(player)
	player.apply_damage(50.0, "KINETIC", roled, false, "Should Not Be Used")
	_check("live valid source ignores label_override", player.recent_damage_log[-1]["label"], "Sniper")

	# --- 3. The actual reported bug: shooter is gone by the time damage lands ---
	# Simulates Projectile._handle_hit() calling apply_damage(..., null, false,
	# source_label) after source_mech died mid-flight - valid_source is null
	# (exactly what Godot's type check forces), but source_label was captured
	# back when the shooter fired and is still alive.
	player.apply_damage(115.0, "KINETIC", null, false, "Sniper")
	_check("dead-shooter kill credits the captured label, not Environment",
		player.recent_damage_log[-1]["label"], "Sniper")

	# --- 4. No override available - still falls back to Environment (unchanged) ---
	player.apply_damage(10.0, "RAW", null, false, "")
	_check("no override and no live source still falls back to Environment",
		player.recent_damage_log[-1]["label"], "Environment")

	if failures == 0:
		print("PASS: death-report attribution survives the shooter dying mid-flight")
	get_tree().quit(0 if failures == 0 else 1)
