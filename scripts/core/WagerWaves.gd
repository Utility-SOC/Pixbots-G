class_name WagerWaves
extends Node

# Wager Waves (owner idea): during the break before a wave you may stake some of your scrap on a harder wave. Pick one
# condition with the number keys 7-0 (7 Horde, 8 Ironclad, 9 Glass, 0 Feeble; the same key again cancels). The stake is paid
# up front; clear the wave and you get it back plus winnings, die in it and the Shopkeeper keeps it. It is the opt-in
# difficulty dial: more reward for more risk, and it never makes the game harder unless you ask. All numbers (tune).
#
#   horde     +60% enemies               pays 1.6x the stake
#   ironclad  enemies have +80% HP       pays 1.7x
#   glass     you take double damage     pays 1.8x
#   feeble    your weapons do 70%        pays 1.5x

const MIN_WAVE = 3
const STAKE_FRACTION = 0.15
const MIN_STAKE = 10
const MODIFIERS = {
	"horde": {"key": KEY_7, "label": "HORDE", "desc": "+60% enemies", "count_mult": 1.6, "payout": 1.6},
	"ironclad": {"key": KEY_8, "label": "IRONCLAD", "desc": "enemies have +80% HP", "hp_mult": 1.8, "payout": 1.7},
	"glass": {"key": KEY_9, "label": "GLASS", "desc": "you take double damage", "damage_taken_mult": 2.0, "payout": 1.8},
	"feeble": {"key": KEY_0, "label": "FEEBLE", "desc": "your weapons do 70%", "weapons_mult": 0.7, "payout": 1.5},
}

var main: Node = null
var window_open: bool = false
var chosen: String = "" # picked, not yet started
var active: String = "" # the wager the current wave runs under
var stake: int = 0
var results: Array = [] # [{wave, id, stake, won, delta}] (for tests and the debrief)
var _label: Label = null

static func stake_for(scrap: int) -> int:
	return maxi(0, mini(scrap, maxi(MIN_STAKE, int(float(scrap) * STAKE_FRACTION)))) if scrap >= MIN_STAKE else 0

static func payout_for(id: String, stake_amount: int) -> int:
	return int(round(float(stake_amount) * float(MODIFIERS[id]["payout"])))

func count_mult() -> float:
	return float(MODIFIERS[active].get("count_mult", 1.0)) if active != "" else 1.0

func hp_mult() -> float:
	return float(MODIFIERS[active].get("hp_mult", 1.0)) if active != "" else 1.0

func _ready():
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_constant_override("outline_size", 4)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_label.position = Vector2(20, 330)
	_label.visible = false
	add_child(_label)
	set_process_unhandled_key_input(true)

# The break before wave `wave` begins: offer the wager if the player can afford a stake.
func open_window(wave: int) -> void:
	chosen = ""
	window_open = wave >= MIN_WAVE and _scrap() >= MIN_STAKE
	_refresh_label()

func _scrap() -> int:
	return int(main.get("player_scrap")) if main != null and main.get("player_scrap") != null else 0

func choose(id: String) -> bool:
	if not window_open or not MODIFIERS.has(id):
		return false
	chosen = "" if chosen == id else id
	_refresh_label()
	return true

func _unhandled_key_input(event: InputEvent) -> void:
	if not window_open or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	for id in MODIFIERS:
		if event.keycode == int(MODIFIERS[id]["key"]):
			choose(id)
			get_viewport().set_input_as_handled()
			return

# The wave starts: pay the stake and apply the conditions.
func begin_wave() -> void:
	window_open = false
	active = chosen
	chosen = ""
	stake = 0
	if active != "":
		stake = stake_for(_scrap())
		if stake <= 0:
			active = ""
		else:
			main.player_scrap -= stake
			_apply_to_player(true)
			if main.has_method("show_dialogue"):
				main.show_dialogue("Shopkeeper", "%s wave. %d on the line. Don't make me regret the paperwork." % [MODIFIERS[active]["label"].capitalize(), stake], Color(1.0, 0.85, 0.3), 5.0)
	_refresh_label()

# The wave ended: win = it was cleared with the player alive; otherwise the stake is lost.
func resolve(won: bool) -> void:
	if active == "":
		return
	var delta = 0
	if won:
		var back = stake + payout_for(active, stake)
		main.player_scrap += back
		delta = back - stake
		if main.has_method("show_dialogue"):
			main.show_dialogue("Shopkeeper", "Wager paid: +%d scrap. Remarkable." % delta, Color(0.6, 1.0, 0.6), 5.0)
	else:
		delta = -stake
	results.append({"wave": int(main.get("current_wave")), "id": active, "stake": stake, "won": won, "delta": delta})
	_apply_to_player(false)
	active = ""
	stake = 0
	_refresh_label()

func _apply_to_player(on: bool) -> void:
	var p = main.get("player") if main != null else null
	if p == null or not is_instance_valid(p) or active == "":
		return
	var m: Dictionary = MODIFIERS[active]
	p.wager_damage_taken_mult = float(m.get("damage_taken_mult", 1.0)) if on else 1.0
	p.wager_weapons_mult = float(m.get("weapons_mult", 1.0)) if on else 1.0

func _refresh_label() -> void:
	if _label == null:
		return
	_label.visible = window_open or active != ""
	if window_open:
		var s = stake_for(_scrap())
		var lines: Array = ["WAGER WAVE (stake %d scrap)  press a key, again to cancel:" % s]
		for id in MODIFIERS:
			var m: Dictionary = MODIFIERS[id]
			var mark = ">" if chosen == id else " "
			lines.append("%s [%s] %s: %s, pays %.1fx" % [mark, OS.get_keycode_string(int(m["key"])), m["label"], m["desc"], float(m["payout"])])
		_label.text = "\n".join(lines)
	elif active != "":
		_label.text = "WAGER: %s (%d on the line)" % [MODIFIERS[active]["label"], stake]
