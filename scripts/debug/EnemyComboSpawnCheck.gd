extends Node

# The director rolls ElementCombos at spawn: Casual never produces a combo bot, the top difficulty at a late wave produces
# plenty, combo bots carry both elements of an interacting pair on their weapons, and support roles never get one.

var current_wave := 60 # SquadDirector reads current_wave off the current scene (this node)
var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _spawn_many(director, role: String, n: int) -> Array:
	var bots = []
	for i in range(n):
		var b = director._spawn_bot_for_role(role, false, 0, "ComboTemplate", false, i % 3, true)
		if b != null:
			if b.get_parent() == null:
				add_child(b)
			bots.append(b)
	return bots

func _count_combo(bots: Array) -> int:
	var n = 0
	for b in bots:
		if not b.element_combo.is_empty():
			n += 1
	return n

func _ready():
	SimRng.seed_all(20261011)
	var director = load("res://scripts/ai/SquadDirector.gd").new()
	director.name = "SquadDirector"
	add_child(director)
	var old_difficulty = SaveManager.difficulty

	SaveManager.difficulty = 0
	var casual = _spawn_many(director, "brawler", 14)
	await get_tree().process_frame
	_check("Casual: no combo bots (%d of %d)" % [_count_combo(casual), casual.size()], casual.size() > 0 and _count_combo(casual) == 0)

	SaveManager.difficulty = 3
	var hard = _spawn_many(director, "brawler", 14)
	await get_tree().process_frame
	var n = _count_combo(hard)
	_check("Top difficulty at wave 60: most bots are combo bots (%d of %d)" % [n, hard.size()], hard.size() > 0 and n >= hard.size() / 2)
	var carries_pair = 0
	for b in hard:
		if b.element_combo.is_empty():
			continue
		b.is_grid_dirty = true
		b._recalculate_grid()
		var seen = {}
		for data in b.precalculated_weapons:
			for k in data.packet.synergies:
				if float(data.packet.synergies[k]) > 0.0:
					seen[int(k)] = true
		if seen.has(int(b.element_combo["a"])) and seen.has(int(b.element_combo["b"])):
			carries_pair += 1
	_check("combo bots' weapons carry both elements of their pair (%d of %d)" % [carries_pair, n], n > 0 and carries_pair == n)

	var support = _spawn_many(director, "support", 6)
	await get_tree().process_frame
	_check("support roles never get a combo", support.size() > 0 and _count_combo(support) == 0)

	SaveManager.difficulty = old_difficulty
	print("EnemyComboSpawnCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
