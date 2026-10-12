extends Node

# Regression: a Drone Bay's loadout (a ComponentEquipment Node) used to leak one orphan Node pair per bay every time an enemy
# carrying one was freed (about 6 orphans per 12 command/support/jammer bots), growing to hundreds over a long session. Spawns and
# frees such bots repeatedly and asserts the orphan count does not climb. (Orphan counts only exist in debug builds; elsewhere
# the monitor reads 0 and this passes vacuously.)

var current_wave := 30 # SquadDirector reads it off the current scene (this node)
var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _orph() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

func _ready():
	SimRng.seed_all(5)
	var director = load("res://scripts/ai/SquadDirector.gd").new()
	director.name = "SquadDirector"
	add_child(director)
	await get_tree().process_frame
	var baseline = _orph()
	var roles = ["commander", "support", "jammer", "brawler"]
	for round in range(3):
		var bots = []
		for i in range(12):
			var b = director._spawn_bot_for_role(roles[i % 4], false, 0, "T%d" % (i % 3), false, i % 3, true)
			if b != null:
				if b.get_parent() == null:
					add_child(b)
				bots.append(b)
		await get_tree().process_frame
		await get_tree().process_frame
		for b in bots:
			if is_instance_valid(b):
				b.queue_free()
		for k in range(4):
			await get_tree().process_frame
	var grown = _orph() - baseline
	_check("freeing drone-carrying bots leaves no orphan nodes behind (grew by %d)" % grown, grown <= 2)

	# Replacing a bay's loadout frees the old one; a loadout parented to a live Drone is left alone.
	var bay = DroneBayTile.new()
	bay.build_drone_loadout()
	var first = bay.drone_loadout
	bay.build_drone_loadout()
	_check("replacing the loadout frees the old orphan", not is_instance_valid(first))
	var held_parent = Node.new()
	add_child(held_parent)
	held_parent.add_child(bay.drone_loadout)
	var held = bay.drone_loadout
	bay.build_drone_loadout()
	_check("a loadout equipped by a live parent is not freed from under it", is_instance_valid(held))
	held_parent.queue_free()
	print("DroneBayOrphanCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
