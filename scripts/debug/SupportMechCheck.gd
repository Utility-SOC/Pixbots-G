extends Node

# Regression harness for: "Replace [the piercing jammer unit] with a
# general support unit with healing and sensor jammers. Make sure the
# commanders have enough support to be able to make a difference in a
# pitched battle."
#
# Verifies SupportMech (replacing the old single-purpose PiercingJammerMech)
# actually delivers all three support functions:
#   1. Healing capacity (has_healer/heal_pulse_* seeded directly, same
#      pipeline any Heal-Beacon-tile-equipped mech uses).
#   2. Sensor jamming (spawns a real JammerField that blinds the player -
#      not owner_is_player - same "Blind" mechanic the tile-driven Jammer
#      Module's VISION mode grants).
#   3. Pierce-execution immunity, preserved from the old PiercingJammerMech
#      (joins "pierce_immunity_aura", Mech._is_pierce_execution_exempt()
#      respects both the unit itself AND anyone standing in its aura).
# Plus: the inherited JammerMech power-jam aura still works (unchanged
# behavior, just inherited rather than reimplemented).

const SupportMechScript = preload("res://scripts/entities/SupportMech.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var support = SupportMechScript.new()
	support.is_player = false
	support.combat_role = "support"
	support.components = {}
	add_child(support)

	_check("healing capacity is granted directly (has_healer)", support.has_healer)
	_check("heal_pulse_power is a real positive value", support.heal_pulse_power > 0.0)
	_check("heal_pulse_radius is a real positive value", support.heal_pulse_radius > 0.0)
	_check("heal_pulse_interval is a real positive value", support.heal_pulse_interval > 0.0)

	_check("joins pierce_immunity_aura group (execute-immunity preserved)",
		support.is_in_group("pierce_immunity_aura"))
	_check("PIERCE_AURA_RADIUS constant exists and is positive",
		SupportMechScript.PIERCE_AURA_RADIUS > 0.0)

	_check("the support unit itself is exempt from PIERCE execution",
		support._is_pierce_execution_exempt())

	# A separate nearby mech (e.g. a squadmate) should ALSO be exempt while
	# standing inside the aura, and NOT exempt once it's far away.
	var nearby = MechScript.new()
	nearby.is_player = false
	nearby.combat_role = "brawler"
	nearby.components = {}
	add_child(nearby)
	nearby.global_position = support.global_position + Vector2(50, 0)
	_check("a squadmate standing inside the aura is ALSO exempt",
		nearby._is_pierce_execution_exempt())
	nearby.global_position = support.global_position + Vector2(SupportMechScript.PIERCE_AURA_RADIUS + 200, 0)
	_check("that same squadmate is NOT exempt once far outside the aura",
		not nearby._is_pierce_execution_exempt())

	# Sensor jamming: a _process tick should spawn a real JammerField
	# belonging to this (non-player) unit.
	support._process(0.016)
	_check("a sensor-jam JammerField was created", support.sensor_jam_field != null and is_instance_valid(support.sensor_jam_field))
	_check("the field correctly identifies as a HOSTILE (non-player) field",
		support.sensor_jam_field and not support.sensor_jam_field.owner_is_player)

	# Inherited power-jam aura (JammerMech behavior) still present.
	_check("still inherits JammerMech's continuous power-jam aura field",
		"jammer_power" in support and "jammer_radius" in support)

	if failures == 0:
		print("PASS: SupportMech delivers healing, sensor jamming, and pierce-execution immunity together")
	get_tree().quit(0 if failures == 0 else 1)
