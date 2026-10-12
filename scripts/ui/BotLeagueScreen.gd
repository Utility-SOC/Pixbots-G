extends Control

# Bot League spectator screen: bracket, odds, an optional wager (credits), then watch the match live (Space pause, 1/2/3 speed)
# or quick-sim it. Entirely separate from the main game: no player mech, no garage.

const VIEW_PAD = 24.0
var league: BotLeague
var sim: BotLeagueSim = null
var mode: String = "lobby" # lobby | watching | result
var speed: float = 1.0
var paused: bool = false
var stake_choice: int = 25
var pick: int = -1
var _last_result: String = ""
var _lobby: VBoxContainer
var _info: RichTextLabel

func _ready():
	league = BotLeague.new()
	league.credits = SaveManager.league_credits()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var bg = ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.12, 1.0)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)
	_lobby = VBoxContainer.new()
	_lobby.position = Vector2(40, 30)
	_lobby.custom_minimum_size = Vector2(700, 0)
	_lobby.add_theme_constant_override("separation", 8)
	add_child(_lobby)
	_build_lobby()

func _build_lobby() -> void:
	for c in _lobby.get_children():
		c.queue_free()
	var title = Label.new()
	title.text = "BOT LEAGUE   credits: %d" % league.credits
	title.add_theme_font_size_override("font_size", 30)
	_lobby.add_child(title)
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.fit_content = true
	_info.custom_minimum_size = Vector2(700, 0)
	_lobby.add_child(_info)
	_info.text = _bracket_text()
	if league.champion >= 0:
		var champ = Label.new()
		champ.text = "CHAMPIONS: %s" % league.teams[league.champion]["name"]
		champ.add_theme_font_size_override("font_size", 24)
		_lobby.add_child(champ)
		_button("New season", func():
			SaveManager.set_league_credits(league.credits)
			league = BotLeague.new()
			league.credits = SaveManager.league_credits()
			_build_lobby())
	else:
		var m = league.current_match()
		var a: Dictionary = league.teams[m["a"]]
		var b: Dictionary = league.teams[m["b"]]
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_lobby.add_child(row)
		var lab = Label.new()
		lab.text = "%s: %s (tier %d, %.0f%%)  vs  %s (tier %d, %.0f%%)" % [league.round_name(), a["name"], a["tier"], league.odds_a() * 100.0, b["name"], b["tier"], (1.0 - league.odds_a()) * 100.0]
		_lobby.add_child(lab)
		var wrow = HBoxContainer.new()
		_lobby.add_child(wrow)
		var wl = Label.new()
		wl.text = "Wager: "
		wrow.add_child(wl)
		for s in [10, 25, 50]:
			var sb = Button.new()
			sb.text = "%d" % s
			sb.toggle_mode = true
			sb.button_pressed = stake_choice == s
			sb.pressed.connect(func(): stake_choice = s; _build_lobby())
			wrow.add_child(sb)
		for p in [0, 1]:
			var pb = Button.new()
			var team_name = a["name"] if p == 0 else b["name"]
			var pay = league.payout_for(p, stake_choice)
			pb.text = "Back %s (pays %d)" % [team_name, pay]
			pb.toggle_mode = true
			pb.button_pressed = pick == p
			pb.disabled = stake_choice > league.credits
			pb.pressed.connect(func(): pick = (-1 if pick == p else p); _build_lobby())
			wrow.add_child(pb)
		_button("Watch the match", _watch)
		_button("Quick sim", func():
			_begin_wager()
			var w = league.quick_sim()
			_finish_match(league.teams[w]["name"]))
	if _last_result != "":
		var r = Label.new()
		r.text = _last_result
		_lobby.add_child(r)
	_button("Back to main menu", func():
		SaveManager.set_league_credits(league.credits)
		get_tree().change_scene_to_file("res://MainMenu.tscn"))

func _button(text: String, cb: Callable) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240, 36)
	b.pressed.connect(cb)
	_lobby.add_child(b)
	return b

func _bracket_text() -> String:
	var out = ""
	for r in range(league.rounds.size()):
		out += "[b]%s[/b]\n" % BotLeague.ROUND_NAMES[mini(r, BotLeague.ROUND_NAMES.size() - 1)]
		for m in league.rounds[r]:
			var an = league.teams[m["a"]]["name"]
			var bn = league.teams[m["b"]]["name"]
			var w = m["winner"]
			out += "   %s%s  vs  %s%s\n" % [("[color=#8f8]" if w == m["a"] else ""), an + ("[/color]" if w == m["a"] else ""), ("[color=#8f8]" if w == m["b"] else ""), bn + ("[/color]" if w == m["b"] else "")]
	return out

func _begin_wager() -> void:
	if pick >= 0 and stake_choice <= league.credits:
		league.place_wager(pick, stake_choice)

func _watch() -> void:
	_begin_wager()
	var m = league.current_match()
	sim = BotLeagueSim.new()
	sim.setup(league.teams[m["a"]]["units"], league.teams[m["b"]]["units"], league.season_seed + league.round_index * 100 + league.match_index)
	mode = "watching"
	paused = false
	speed = 1.0
	_lobby.visible = false
	queue_redraw()

func _finish_match(winner_name: String) -> void:
	var delta = league.last_wager_delta
	_last_result = "%s win." % winner_name
	if delta != 0:
		_last_result += "  Wager %s%d credits." % ["+" if delta > 0 else "", delta]
	pick = -1
	SaveManager.set_league_credits(league.credits)
	mode = "lobby"
	sim = null
	_lobby.visible = true
	_build_lobby()
	queue_redraw()

func _process(delta: float) -> void:
	if mode != "watching" or sim == null:
		return
	if not paused:
		var steps = int(ceil(delta * speed / 0.05))
		for i in range(steps):
			sim.step(0.05)
	if sim.winner() != 0:
		var w = league.report(sim.winner())
		_finish_match(league.teams[w]["name"])
		return
	queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	if mode == "watching":
		match event.keycode:
			KEY_SPACE: paused = not paused
			KEY_1: speed = 1.0
			KEY_2: speed = 3.0
			KEY_3: speed = 8.0
			KEY_ESCAPE:
				var w = league.report(sim.run_to_end()) # skip to the result
				_finish_match(league.teams[w]["name"])

func _draw() -> void:
	if mode != "watching" or sim == null:
		return
	var avail = size - Vector2(VIEW_PAD * 2.0, VIEW_PAD * 2.0 + 40.0)
	var scale_f = minf(avail.x / sim.arena.x, avail.y / sim.arena.y)
	var origin = Vector2(VIEW_PAD, VIEW_PAD + 40.0)
	draw_rect(Rect2(origin, sim.arena * scale_f), Color(0.13, 0.15, 0.2))
	draw_rect(Rect2(origin, sim.arena * scale_f), Color(0.3, 0.35, 0.45), false, 2.0)
	for s in sim.shots:
		draw_line(origin + s[0] * scale_f, origin + s[1] * scale_f, s[2], 1.5)
	var font = ThemeDB.fallback_font
	for u in sim.units:
		var p = origin + u["pos"] * scale_f
		var col = Color(0.35, 0.65, 1.0) if u["team"] == 0 else Color(1.0, 0.45, 0.4)
		if not u["alive"]:
			draw_circle(p, 6.0, col.darkened(0.7))
			continue
		draw_circle(p, 11.0, col)
		draw_string(font, p + Vector2(-4, 5), str(u["role"]).left(1).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0, 0, 0))
		var bw = 28.0
		draw_rect(Rect2(p + Vector2(-bw / 2.0, -20), Vector2(bw, 3)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(p + Vector2(-bw / 2.0, -20), Vector2(bw * float(u["hp"]) / float(u["max_hp"]), 3)), Color(0.4, 1.0, 0.4))
		if float(u["max_shield"]) > 0.0:
			draw_rect(Rect2(p + Vector2(-bw / 2.0, -24), Vector2(bw * float(u["shield"]) / float(u["max_shield"]), 3)), BotLeagueSim._element_color(int(u["shield_el"])))
	var m = league.current_match()
	draw_string(font, Vector2(VIEW_PAD, 28), "%s: %s  vs  %s     %ds   speed x%d%s   [Space] pause  [1/2/3] speed  [Esc] skip" % [league.round_name(), league.teams[m["a"]]["name"], league.teams[m["b"]]["name"], int(sim.time), int(speed), "  PAUSED" if paused else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1))
