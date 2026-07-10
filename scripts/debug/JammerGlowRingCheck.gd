extends Node

# Exercises JammerMech/PiercingJammerMech's new _draw()-based glow ring for
# a few frames headlessly to catch any script errors in the draw path
# itself (queue_redraw() defers to the next frame, so this needs at least
# one process tick, not just _ready()). Safe to delete once validated.

const JammerMech = preload("res://scripts/entities/JammerMech.gd")
const PiercingJammerMech = preload("res://scripts/entities/PiercingJammerMech.gd")

var _frames := 0

func _ready():
	var j = JammerMech.new()
	j.is_player = false
	j.combat_role = "jammer"
	add_child(j)

	var pj = PiercingJammerMech.new()
	pj.is_player = false
	pj.combat_role = "piercing_jammer"
	add_child(pj)

	print("Spawned JammerMech (radius=", j.jammer_radius, ") and PiercingJammerMech (radius=", pj.jammer_radius, ", pierce_radius=", pj.PIERCE_AURA_RADIUS, ")")

func _process(_delta):
	_frames += 1
	if _frames >= 5:
		print("5 frames ticked with no draw errors - OK")
		get_tree().quit()
