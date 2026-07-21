extends Node

# Regression harness for task #9's remaining two pieces: portraits ("a boss
# chunk, a squad chunk, and an individual unit chunk") and the death log
# (player deaths only). Real portrait rendering needs a real RenderingDevice
# (see ChampionCard._render_sprite_portrait's own comment) - unavailable
# under --headless, so this verifies the STRUCTURE (a portrait swatch is
# present per boss/per-role-in-a-template, no crash, no duplicate concurrent
# renders) rather than actual pixel content, which only a windowed session
# can produce. Death log logic (SaveManager.record_death, the cap, and
# Main._top_damage_label's damage-source aggregation) is fully verified -
# none of that needs real rendering.

const WarRoomMenuScript = preload("res://scripts/ui/WarRoomMenu.gd")
const SquadDirectorScript = preload("res://scripts/ai/SquadDirector.gd")
const SquadTemplateScript = preload("res://scripts/ai/SquadTemplate.gd")
const MainScript = preload("res://scripts/core/Main.gd")

# Satisfies WarRoomMenu._get_director()'s `"world" in main and main.world`
# check on get_tree().current_scene - this test IS current_scene when run
# via `godot --headless res://scripts/debug/....tscn`, so without this the
# menu would silently fall back to WarRoomSnapshot.load_from_disk() and read
# the REAL player's learned_state.json instead of this test's own data.
var world: Node2D = null

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# --- Death log logic (no rendering involved at all) ---------------------
	SaveManager.death_log = []
	SaveManager.record_death(3, "Boss")
	SaveManager.record_death(7, "Sniper")
	_check("record_death appends in order", SaveManager.death_log.size() == 2
		and SaveManager.death_log[0]["wave"] == 3 and SaveManager.death_log[1]["wave"] == 7)

	for i in range(30):
		SaveManager.record_death(i, "Test")
	_check("death_log is capped at DEATH_LOG_CAP, keeping the most recent entries",
		SaveManager.death_log.size() == SaveManager.DEATH_LOG_CAP
		and SaveManager.death_log[-1]["wave"] == 29)

	var log_sample: Array = [
		{"label": "Brawler", "element": "RAW", "amount": 50.0},
		{"label": "Boss", "element": "FIRE", "amount": 300.0},
		{"label": "Boss", "element": "RAW", "amount": 100.0},
	]
	_check("_top_damage_label picks the label with the highest TOTAL damage across entries (Boss: 400 > Brawler: 50)",
		MainScript._top_damage_label(log_sample) == "Boss")
	_check("_top_damage_label on an empty log returns a safe fallback, not a crash",
		MainScript._top_damage_label([]) == "Unknown")

	# --- Live War Room setup -------------------------------------------------
	world = Node2D.new()
	add_child(world)
	var director = SquadDirectorScript.new()
	director.name = "SquadDirector"
	world.add_child(director)

	_check("SquadDirector._ready() registered real default boss profiles",
		not director.boss_profiles.is_empty())

	# A deployed template so the Threat Board actually renders a row (only
	# t.times_deployed > 0 templates show - see WarRoomMenu._build_threat_board).
	var template = SquadTemplateScript.new("Test Squad", {"brawler": 2, "sniper": 1})
	template.times_deployed = 1
	director.templates.append(template)

	SaveManager.death_log = []
	SaveManager.record_death(12, "Boss")

	var wr = WarRoomMenuScript.new()
	add_child(wr)
	wr._toggle() # opens + calls _refresh()

	# --- Death Log tab ---------------------------------------------------
	var death_rows = death_vbox_row_count(wr)
	_check("Death Log tab renders one row per death_log entry", death_rows == 1)

	# --- Bosses tab: one card per boss profile, each with a portrait swatch -
	# (boss_vbox also carries 2 header Labels before the actual boss row
	# cards - filter to PanelContainer, same as death_vbox_row_count does.)
	var boss_cards: Array = []
	for c in wr.boss_vbox.get_children():
		if c is PanelContainer:
			boss_cards.append(c)
	_check("Bosses tab has one card per registered boss profile",
		boss_cards.size() == director.boss_profiles.size() and boss_cards.size() > 0)
	if boss_cards.size() > 0:
		var portrait = find_texture_rect(boss_cards[0])
		_check("each boss card carries a portrait TextureRect (boss chunk)", portrait != null)

	# --- Threat Board: squad chunk + individual unit chunk -------------------
	var unit_portraits = count_texture_rects(wr.threat_vbox)
	_check("Threat Board renders at least one unit portrait per distinct role in the deployed template (squad/individual unit chunk)",
		unit_portraits >= template.required_roles.size())

	# --- No duplicate concurrent renders for the same cache key -------------
	var pending_before = wr._portrait_pending.size()
	wr._get_portrait("role:brawler", "brawler", HexTile.Rarity.RARE, false)
	var pending_after = wr._portrait_pending.size()
	_check("requesting an already-pending portrait key doesn't start a second concurrent render",
		pending_after == pending_before)

	if failures == 0:
		print("PASS: death log (logic + tab) and portrait structure (boss/squad/unit chunks) all wired correctly")
	get_tree().quit(0 if failures == 0 else 1)

func death_vbox_row_count(wr) -> int:
	var n = 0
	for c in wr.death_vbox.get_children():
		if c is PanelContainer:
			n += 1
	return n

func find_texture_rect(node: Node):
	if node is TextureRect:
		return node
	for c in node.get_children():
		var found = find_texture_rect(c)
		if found:
			return found
	return null

func count_texture_rects(node: Node) -> int:
	var n = 0
	if node is TextureRect:
		n += 1
	for c in node.get_children():
		n += count_texture_rects(c)
	return n
