class_name WarRoomNames
extends RefCounted

# Procedural, Stargate-style low-collision designations for AI-generated
# squad templates and solver profiles (e.g. "P3X-774", "K9M-041").
# Letter+digit+letter+3 digits = ~5.3M combinations, so within-session
# collisions are effectively impossible - but unique_designation() still
# accepts a taken-list for belt-and-braces uniqueness against saved state.

# No I, O, or Q - avoids 1/0 visual confusion in a pixel font.
const _LETTERS = "ABCDEFGHJKLMNPRSTUVWXYZ"

static func designation() -> String:
	var l1 = _LETTERS[randi() % _LETTERS.length()]
	var d1 = str(randi() % 10)
	var l2 = _LETTERS[randi() % _LETTERS.length()]
	return l1 + d1 + l2 + "-" + "%03d" % (randi() % 1000)

static func unique_designation(taken: Array = []) -> String:
	for i in range(16):
		var name = designation()
		if not taken.has(name):
			return name
	# 16 straight collisions out of 5.3M combos: statistically not happening,
	# but never loop forever on principle.
	return designation()
