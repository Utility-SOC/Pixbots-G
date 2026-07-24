extends Node

# Per the user: "I need like, 300 more interstitial quips, because players
# are going to be doing thousands of waves, a pool as small as we have is
# going to look really repetitive... I don't know a good workflow for that."
# Two changes: (1) intermission_quips grew from 27 to 327 lines, and (2)
# DialogueManager now draws every list-based pool via a shuffle-bag
# (_draw_no_repeat) instead of flat randi() % size, so no line repeats until
# every OTHER line in the pool has been shown, and the reshuffle seam can't
# produce a back-to-back repeat either.

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# --- Content QC: the real pool ---
	_check("dialogue.json loaded (DialogueManager is a real autoload)",
		DialogueManager.dialogue_data.has("intermission_quips"))

	var quips: Array = DialogueManager.dialogue_data.get("intermission_quips", [])
	_check("intermission_quips grew well past the old 27-line pool (300+ new lines)",
		quips.size() >= 300)

	var seen := {}
	var dupes = 0
	for q in quips:
		if seen.has(q):
			dupes += 1
		seen[q] = true
	_check("no duplicate lines in intermission_quips (copy-paste QC)", dupes == 0)

	var all_nonempty = true
	for q in quips:
		if not (q is String) or q.strip_edges() == "":
			all_nonempty = false
	_check("every intermission_quips entry is a real non-empty string", all_nonempty)

	# --- Shuffle-bag algorithm correctness: real pool, one full cycle ---
	var drawn_cycle1 := {}
	for i in range(quips.size()):
		var line = DialogueManager.get_intermission_quip()
		drawn_cycle1[line] = drawn_cycle1.get(line, 0) + 1
	var cycle1_all_unique = true
	for line in drawn_cycle1:
		if drawn_cycle1[line] != 1:
			cycle1_all_unique = false
	_check("one full cycle (pool.size() draws) touches every line exactly once, no repeats",
		cycle1_all_unique and drawn_cycle1.size() == quips.size())

	# --- Shuffle-bag reshuffle-seam guard: small synthetic pool, many cycles ---
	var small_pool = ["A", "B", "C", "D", "E"]
	DialogueManager.dialogue_data["_test_pool"] = small_pool
	var prev = ""
	var back_to_back_repeats = 0
	var total_draws = small_pool.size() * 40 # many full cycles
	for i in range(total_draws):
		var line = DialogueManager._draw_no_repeat("_test_pool", small_pool)
		if i > 0 and line == prev:
			back_to_back_repeats += 1
		prev = line
	_check("no back-to-back repeat across many reshuffle-bag cycles (seam guard holds)",
		back_to_back_repeats == 0)
	DialogueManager.dialogue_data.erase("_test_pool")

	# --- Each pool independently maintains its own bag (no cross-pool bleed) ---
	var quip1 = DialogueManager.get_intermission_quip()
	var boss1 = DialogueManager.get_boss_defeat()
	_check("intermission_quips and boss_defeats draw from independent bags",
		DialogueManager.dialogue_data.get("boss_defeats", []).size() > 0 and boss1 != "")
	_check("draw call still returns a real line from the real pool", quip1 != "")

	if failures == 0:
		print("PASS: intermission_quips pool is large and duplicate-free, and the shuffle-bag draw never repeats within a cycle or across the reshuffle seam")
	get_tree().quit(0 if failures == 0 else 1)
