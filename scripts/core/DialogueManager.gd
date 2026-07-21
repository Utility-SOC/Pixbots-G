extends Node

# Autoload (project.godot). Previously every call site did
# `load("res://scripts/core/DialogueManager.gd").new()` followed by a manual
# `dm._ready()` - re-parsing config/dialogue.json from disk on every single
# dialogue trigger, AND leaking the Node itself (extends Node, not
# RefCounted, and none of those ~14 call sites ever add_child()'d or freed
# it). As an autoload, _ready() runs exactly once at game startup and the
# parsed data is reused for the rest of the session.

var dialogue_data: Dictionary = {}

func _ready():
	var file = FileAccess.open("res://config/dialogue.json", FileAccess.READ)
	if file:
		var json = JSON.new()
		var error = json.parse(file.get_as_text())
		if error == OK:
			dialogue_data = json.data
		else:
			push_error("JSON Parse Error in dialogue.json: ", json.get_error_message())
		file.close()
	else:
		push_error("Could not open dialogue.json")

func get_intermission_quip() -> String:
	if dialogue_data.has("intermission_quips") and dialogue_data["intermission_quips"].size() > 0:
		var quips = dialogue_data["intermission_quips"]
		return quips[randi() % quips.size()]
	return ""

func get_boss_defeat() -> String:
	if dialogue_data.has("boss_defeats") and dialogue_data["boss_defeats"].size() > 0:
		var pool = dialogue_data["boss_defeats"]
		return pool[randi() % pool.size()]
	return ""

func get_death_footer() -> String:
	if dialogue_data.has("death_footers") and dialogue_data["death_footers"].size() > 0:
		var pool = dialogue_data["death_footers"]
		return pool[randi() % pool.size()]
	return ""

func get_game_over_3_loss() -> String:
	return dialogue_data.get("game_over_3_loss", "")

func get_rival_data(rival_name: String) -> Dictionary:
	if dialogue_data.has("rivals") and dialogue_data["rivals"].has(rival_name):
		return dialogue_data["rivals"][rival_name]
	return {}

func get_generic_rival_win() -> String:
	if dialogue_data.has("generic_rival_wins") and dialogue_data["generic_rival_wins"].size() > 0:
		var pool = dialogue_data["generic_rival_wins"]
		return pool[randi() % pool.size()]
	return ""

func get_generic_rival_loss() -> String:
	if dialogue_data.has("generic_rival_losses") and dialogue_data["generic_rival_losses"].size() > 0:
		var pool = dialogue_data["generic_rival_losses"]
		return pool[randi() % pool.size()]
	return ""

func get_travelling_champion_data() -> Dictionary:
	return dialogue_data.get("travelling_champion", {})
	
func get_first_boss_intro() -> String:
	return dialogue_data.get("first_boss_intro", "")
	
func get_first_boss_defeat() -> String:
	return dialogue_data.get("first_boss_defeat", "")
	
func get_black_market_quip() -> String:
	if dialogue_data.has("black_market") and dialogue_data["black_market"].size() > 0:
		var pool = dialogue_data["black_market"]
		return pool[randi() % pool.size()]
	return ""

func get_tournament_teaser() -> String:
	return dialogue_data.get("tournament_teaser", "")
	
func get_milestone_10_bosses() -> String:
	return dialogue_data.get("milestones", {}).get("10_bosses", "")

func get_milestone_level_100() -> String:
	return dialogue_data.get("milestones", {}).get("level_100", "")

func get_boss_rush_intro() -> String:
	return dialogue_data.get("boss_rush", {}).get("intro", "")

func get_boss_rush_completion() -> String:
	return dialogue_data.get("boss_rush", {}).get("completion", "")
