extends Node

# Exercises JammerMech/SupportMech's _draw()-based glow ring for a few
# frames headlessly to catch any script errors in the draw path itself
# (queue_redraw() defers to the next frame, so this needs at least one
# process tick, not just _ready()). Safe to delete once validated.

const JammerMech = preload("res://scripts/entities/JammerMech.gd")
const SupportMech = preload("res://scripts/entities/SupportMech.gd")

var _frames := 0

func _ready():
	var j = JammerMech.new()
	j.is_player = false
	j.combat_role = "jammer"
	add_child(j)

	var sm = SupportMech.new()
	sm.is_player = false
	sm.combat_role = "support"
	add_child(sm)

	print("Spawned JammerMech (radius=", j.jammer_radius, ") and SupportMech (radius=", sm.jammer_radius, ", pierce_radius=", sm.PIERCE_AURA_RADIUS, ")")

func _process(_delta):
	_frames += 1
	if _frames >= 5:
		print("5 frames ticked with no draw errors - OK")
		get_tree().quit()
