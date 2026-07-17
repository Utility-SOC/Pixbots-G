class_name WarRoomNames
extends RefCounted

# Procedural, Stargate-style low-collision designations for AI-generated
# squad templates and solver profiles (e.g. "P3X-774", "K9M-041").
# Letter+digit+letter+3 digits = ~5.3M combinations, so within-session
# collisions are effectively impossible.

# No I, O, or Q - avoids 1/0 visual confusion in a pixel font.
const _LETTERS = "ABCDEFGHJKLMNPRSTUVWXYZ"

static func designation() -> String:
	var l1 = _LETTERS[randi() % _LETTERS.length()]
	var d1 = str(randi() % 10)
	var l2 = _LETTERS[randi() % _LETTERS.length()]
	return l1 + d1 + l2 + "-" + "%03d" % (randi() % 1000)
