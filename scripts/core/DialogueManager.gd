extends Node

# Autoload (project.godot). Previously every call site did
# `load("res://scripts/core/DialogueManager.gd").new()` followed by a manual
# `dm._ready()` - re-parsing config/dialogue.json from disk on every single
# dialogue trigger, AND leaking the Node itself (extends Node, not
# RefCounted, and none of those ~14 call sites ever add_child()'d or freed
# it). As an autoload, _ready() runs exactly once at game startup and the
# parsed data is reused for the rest of the session.

var dialogue_data: Dictionary = {}

# Shuffle-bag draw state, keyed per pool name (see _draw_no_repeat below).
var _shuffle_bags: Dictionary = {} # pool key -> Array (remaining draw order for the current cycle)
var _last_drawn: Dictionary = {} # pool key -> last line actually returned (survives across cycle boundaries)

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

# Per the user: "a pool as small as we have is going to look really
# repetitive" over thousands of waves - flat randi() % size can repeat the
# same line twice in a row even in a 300+ line pool, and gives no guarantee
# you won't hear a favorite again three waves later. Shuffle-bag technique
# instead (same idea as Tetris' piece randomizer): every line in the pool
# gets drawn exactly once before any line repeats. Also guards the RESHUFFLE
# SEAM - without this, the first draw of a freshly reshuffled bag could
# happen to be the exact line that just finished the previous bag, which
# would still read as a back-to-back repeat to the player even though
# technically two different "cycles" produced it.
func _draw_no_repeat(pool_key: String, pool: Array) -> String:
	if pool.is_empty():
		return ""
	if not _shuffle_bags.has(pool_key) or _shuffle_bags[pool_key].is_empty():
		var bag = pool.duplicate()
		bag.shuffle()
		if pool.size() > 1 and _last_drawn.has(pool_key) and bag[0] == _last_drawn[pool_key]:
			var swap_idx = 1 + (randi() % (bag.size() - 1))
			var tmp = bag[0]
			bag[0] = bag[swap_idx]
			bag[swap_idx] = tmp
		_shuffle_bags[pool_key] = bag
	var line = _shuffle_bags[pool_key].pop_front()
	_last_drawn[pool_key] = line
	return line

func get_intermission_quip() -> String:
	if dialogue_data.has("intermission_quips"):
		return _draw_no_repeat("intermission_quips", dialogue_data["intermission_quips"])
	return ""

func get_boss_defeat() -> String:
	if dialogue_data.has("boss_defeats"):
		return _draw_no_repeat("boss_defeats", dialogue_data["boss_defeats"])
	return ""

func get_death_footer() -> String:
	if dialogue_data.has("death_footers"):
		return _draw_no_repeat("death_footers", dialogue_data["death_footers"])
	return ""

func get_game_over_3_loss() -> String:
	return dialogue_data.get("game_over_3_loss", "")

func get_rival_data(rival_name: String) -> Dictionary:
	if dialogue_data.has("rivals") and dialogue_data["rivals"].has(rival_name):
		return dialogue_data["rivals"][rival_name]
	return {}

func get_generic_rival_win() -> String:
	if dialogue_data.has("generic_rival_wins"):
		return _draw_no_repeat("generic_rival_wins", dialogue_data["generic_rival_wins"])
	return ""

func get_generic_rival_loss() -> String:
	if dialogue_data.has("generic_rival_losses"):
		return _draw_no_repeat("generic_rival_losses", dialogue_data["generic_rival_losses"])
	return ""

func get_travelling_champion_data() -> Dictionary:
	return dialogue_data.get("travelling_champion", {})
	
func get_first_boss_intro() -> String:
	return dialogue_data.get("first_boss_intro", "")
	
func get_first_boss_defeat() -> String:
	return dialogue_data.get("first_boss_defeat", "")
	
func get_black_market_quip() -> String:
	if dialogue_data.has("black_market"):
		return _draw_no_repeat("black_market", dialogue_data["black_market"])
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
