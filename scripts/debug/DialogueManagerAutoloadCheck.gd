extends Node

# Regression harness for: DialogueManager used to be instantiated via
# `load("res://scripts/core/DialogueManager.gd").new()` at ~14 call sites
# across Main.gd/SquadDirector.gd/GarageMarket.gd/MainMenu.gd, each one
# manually calling `dm._ready()` to force the file read since the instance
# was never add_child()'d - meaning every dialogue trigger re-read and
# re-parsed config/dialogue.json from disk, AND leaked the Node (extends
# Node, not RefCounted; never added to the tree, never freed).
#
# Now an autoload: _ready() runs exactly once at game startup. This also
# caught a real bug along the way - Main.gd's travelling-champion dialogue
# called the nonexistent dm.get_travelling_champion() (real method is
# get_travelling_champion_data()); load()'s dynamic typing meant GDScript
# never caught the bad method name until it actually ran.

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var singleton = get_tree().root.get_node_or_null("DialogueManager")
	_check("DialogueManager autoload is present in the tree", singleton != null)
	if not singleton:
		get_tree().quit(1)
		return
	_check("it's the real DialogueManager (extends Node, has dialogue_data)",
		"dialogue_data" in singleton)
	_check("dialogue_data was already parsed from disk by the time this runs (autoload _ready ran before ours)",
		singleton.dialogue_data is Dictionary and not singleton.dialogue_data.is_empty())

	# Every getter used by a real call site (Main.gd, SquadDirector.gd,
	# GarageMarket.gd, MainMenu.gd) - proves both the autoload wiring AND
	# that config/dialogue.json actually has content for each key.
	_check("get_intermission_quip() returns real content", DialogueManager.get_intermission_quip() != "")
	_check("get_boss_defeat() returns real content", DialogueManager.get_boss_defeat() != "")
	_check("get_death_footer() returns real content", DialogueManager.get_death_footer() != "")
	_check("get_generic_rival_win() returns real content", DialogueManager.get_generic_rival_win() != "")
	_check("get_generic_rival_loss() returns real content", DialogueManager.get_generic_rival_loss() != "")
	_check("get_first_boss_intro() returns real content", DialogueManager.get_first_boss_intro() != "")
	_check("get_first_boss_defeat() returns real content", DialogueManager.get_first_boss_defeat() != "")
	_check("get_black_market_quip() returns real content", DialogueManager.get_black_market_quip() != "")
	_check("get_tournament_teaser() returns real content", DialogueManager.get_tournament_teaser() != "")
	_check("get_boss_rush_intro() returns real content", DialogueManager.get_boss_rush_intro() != "")
	_check("get_boss_rush_completion() returns real content", DialogueManager.get_boss_rush_completion() != "")

	# The bug this conversion caught: get_travelling_champion_data(), not
	# get_travelling_champion() (which doesn't exist on DialogueManager at all).
	var champ = DialogueManager.get_travelling_champion_data()
	_check("get_travelling_champion_data() exists and returns a Dictionary",
		champ is Dictionary)

	# Rival data lookup, used by SquadDirector via dialogue_data directly.
	var rivals = DialogueManager.dialogue_data.get("rivals", {})
	_check("dialogue_data has a non-empty rivals table (SquadDirector reads this directly)",
		rivals is Dictionary and not rivals.is_empty())
	var first_rival_name = rivals.keys()[0]
	var first_rival = DialogueManager.get_rival_data(first_rival_name)
	_check("get_rival_data() resolves a real rival entry", not first_rival.is_empty())

	# No leak: calling getters repeatedly must not create new nodes - it's
	# one autoload instance, not one-per-call like before.
	var node_count_before = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	for i in range(50):
		DialogueManager.get_intermission_quip()
		DialogueManager.get_boss_defeat()
	var node_count_after = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	_check("calling getters repeatedly creates no new Nodes (no more per-call leak)",
		node_count_after == node_count_before)

	if failures == 0:
		print("PASS: DialogueManager is a real autoload - loads once, no leak, all getters wired correctly")
	get_tree().quit(0 if failures == 0 else 1)
