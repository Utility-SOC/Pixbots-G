extends CanvasLayer

# WAR ROOM v2 - full-screen menu (garage-style), TAB to toggle, Esc closes.
#
# Tabs:
#   Threat Board - the default view: top 6 most effective squad templates
#     against the player (highest average fitness among deployed), each with
#     an efficacy graph of its per-deployment fitness history.
#   Family Tree  - dendrogram of evolved squad lineages (mutation/fusion
#     parents from SquadTemplate.parent_name). Culled ancestors appear as
#     ghost nodes so successful lines still show their full history.
#   Doctrines    - complete template + solver-profile lists, clipboard
#     export/import of the AI's learned state.
#   Bosses       - every BossProfile (the 6 hand-authored originals plus any
#     experimental mutations on trial), click a row to drill into its full
#     kit: ability pool, enrage/position style, hp multiplier, lineage, and
#     an efficacy sparkline just like the Threat Board's squad graphs.

var root_panel: PanelContainer
var is_open: bool = false
var tabs: TabContainer
var threat_vbox: VBoxContainer
var tree_view: DendrogramView
var doctrine_vbox: VBoxContainer
var boss_vbox: VBoxContainer
var captures_vbox: VBoxContainer
var death_vbox: VBoxContainer
var status_label: Label

# profile_name -> bool, remembers which boss rows are expanded across a
# _refresh() (e.g. the periodic reopen) so drilling into a boss doesn't
# collapse the instant anything else changes.
var _boss_expanded: Dictionary = {}

const SYNERGY_NAMES = EnergyPacket.SYNERGY_NAMES # canonical table lives there
const SquadTemplateMutator = preload("res://scripts/ai/SquadTemplateMutator.gd")
const ChampionCard = preload("res://scripts/pvp/ChampionCard.gd")

const COL_TITLE = Color(1.0, 0.85, 0.4)
const COL_SECTION = Color(0.5, 0.9, 1.0)
const COL_CORE = Color(0.9, 0.9, 0.9)
const COL_TRIAL = Color(1.0, 0.8, 0.3)
const COL_GOOD = Color(0.4, 1.0, 0.5)
const COL_BAD = Color(1.0, 0.45, 0.4)
const COL_DIM = Color(0.65, 0.65, 0.7)
const COL_GHOST = Color(0.45, 0.45, 0.5)

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 99 # under the debug menu (100)

	# Register our own toggle action instead of relying on Main.gd to have
	# done it - this menu is ALSO instantiated directly by the Main Menu's
	# "War Room" button (MainMenu._on_war_room_pressed), where Main.gd's
	# registrations never ran, so Tab silently did nothing there while Esc
	# (built-in ui_cancel) still closed it. Registering here (idempotent,
	# same runtime-registered-action pattern as Main.gd's cloak/heal_pulse/
	# jam_pulse) makes Tab work in every context that can show this menu.
	if not InputMap.has_action("toggle_war_room"):
		InputMap.add_action("toggle_war_room")
		var war_room_key = InputEventKey.new()
		war_room_key.physical_keycode = KEY_TAB
		InputMap.action_add_event("toggle_war_room", war_room_key)

	root_panel = PanelContainer.new()
	root_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.11, 0.97)
	root_panel.add_theme_stylebox_override("panel", style)
	root_panel.hide()
	add_child(root_panel)

	var outer = VBoxContainer.new()
	root_panel.add_child(outer)

	# Header bar
	var header = HBoxContainer.new()
	outer.add_child(header)
	var title = Label.new()
	title.text = "  WAR ROOM - ENEMY DOCTRINE ANALYSIS"
	title.add_theme_font_size_override("font_size", 22)
	title.modulate = COL_TITLE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn = Button.new()
	close_btn.text = "Close (TAB)"
	close_btn.pressed.connect(_toggle)
	header.add_child(close_btn)

	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(tabs)

	# --- Tab: Threat Board -------------------------------------------------
	var threat_scroll = ScrollContainer.new()
	threat_scroll.name = "Threat Board"
	tabs.add_child(threat_scroll)
	threat_vbox = VBoxContainer.new()
	threat_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	threat_scroll.add_child(threat_vbox)

	# --- Tab: Family Tree ----------------------------------------------------
	var tree_scroll = ScrollContainer.new()
	tree_scroll.name = "Family Tree"
	tabs.add_child(tree_scroll)
	tree_view = DendrogramView.new()
	tree_scroll.add_child(tree_view)

	# --- Tab: Doctrines -------------------------------------------------------
	var doc_scroll = ScrollContainer.new()
	doc_scroll.name = "Doctrines"
	tabs.add_child(doc_scroll)
	doctrine_vbox = VBoxContainer.new()
	doctrine_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	doc_scroll.add_child(doctrine_vbox)

	# --- Tab: Bosses ------------------------------------------------------------
	var boss_scroll = ScrollContainer.new()
	boss_scroll.name = "Bosses"
	tabs.add_child(boss_scroll)
	boss_vbox = VBoxContainer.new()
	boss_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	boss_scroll.add_child(boss_vbox)

	# --- Tab: Captured Loadouts --------------------------------------------
	var captures_scroll = ScrollContainer.new()
	captures_scroll.name = "Captured Loadouts"
	tabs.add_child(captures_scroll)
	captures_vbox = VBoxContainer.new()
	captures_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	captures_scroll.add_child(captures_vbox)

	# --- Tab: Death Log (task #9) - player deaths only, not a kill log ----
	var death_scroll = ScrollContainer.new()
	death_scroll.name = "Death Log"
	tabs.add_child(death_scroll)
	death_vbox = VBoxContainer.new()
	death_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	death_scroll.add_child(death_vbox)

func _input(event):
	# Unify menu keys (Status.md HUD/UX backlog): routed through InputMap
	# actions like every other menu (ui_cancel, plus the same
	# runtime-registered-action pattern cloak/heal_pulse/jam_pulse use in
	# Main.gd) instead of raw physical_keycode checks, so War Room's keys
	# aren't the one menu's bindings the InputMap doesn't know about.
	if event.is_action_pressed("toggle_war_room"):
		if not is_open and get_tree().paused:
			return # don't fight other paused UIs
		_toggle()
	elif event.is_action_pressed("ui_cancel") and is_open:
		_toggle()
		get_viewport().set_input_as_handled()

func _toggle():
	is_open = not is_open
	root_panel.visible = is_open
	get_tree().paused = is_open
	if is_open:
		_refresh()

# --- Portraits (task #9: "a boss chunk, a squad chunk, and an individual
# unit chunk") -------------------------------------------------------------
# Reuses ChampionCard._render_sprite_portrait wholesale (the same real-mech-
# in-a-private-SubViewport renderer Champion Card exports already use)
# rather than building a second render path. Cached by a string key (role
# name, or "boss:"+profile_name) so the real cost - constructing a Mech,
# letting it build a role loadout, spinning up a SubViewport - is paid ONCE
# per distinct role/boss ever shown, not on every _refresh(). Rendering is
# async (SubViewport capture needs a frame), so _get_portrait returns null
# immediately on a cache miss, kicks off the render in the background, and
# the row just shows a blank swatch until the next _refresh() picks up the
# now-cached texture - _refresh() already runs cheaply and idempotently
# (it's a full-rebuild-from-data design, same as every other tab here).
var _portrait_cache: Dictionary = {} # cache_key (String) -> Texture2D
var _portrait_pending: Dictionary = {} # cache_key (String) -> true while a render is in flight
var _portrait_rig_parent: Node = null
const PORTRAIT_SIZE = 64

func _get_portrait(cache_key: String, role: String, rarity: int, boss_visual: bool) -> Texture2D:
	if _portrait_cache.has(cache_key):
		return _portrait_cache[cache_key]
	if not _portrait_pending.get(cache_key, false):
		_portrait_pending[cache_key] = true
		_render_portrait_async(cache_key, role, rarity, boss_visual)
	return null

func _render_portrait_async(cache_key: String, role: String, rarity: int, boss_visual: bool):
	# Kicked off synchronously from mid-_refresh() (building a boss/threat
	# row), which is itself often mid-add_child() further up the call stack
	# (e.g. this whole menu's own _ready()) - Godot rejects a nested
	# add_child() on a node that's still busy setting up children. One frame
	# of breathing room sidesteps that without changing the fire-and-forget
	# call site (_get_portrait never awaits this).
	await get_tree().process_frame

	if not _portrait_rig_parent or not is_instance_valid(_portrait_rig_parent):
		_portrait_rig_parent = Node.new()
		_portrait_rig_parent.name = "PortraitRigs"
		get_tree().root.add_child(_portrait_rig_parent)

	var rig = load("res://scripts/entities/Mech.gd").new()
	rig.is_player = false
	rig.combat_role = role
	rig.base_rarity = clamp(rarity, 0, 4)
	_portrait_rig_parent.add_child(rig) # _ready() fires here: builds a real role-appropriate loadout
	if boss_visual:
		rig.is_boss = true
		if rig.has_method("refresh_boss_visuals"):
			rig.refresh_boss_visuals()

	var img = await ChampionCard._render_sprite_portrait(rig)
	rig.queue_free()
	_portrait_pending.erase(cache_key)
	if img:
		var tex = ImageTexture.create_from_image(img)
		_portrait_cache[cache_key] = tex
		if is_open: # popped closed while we were rendering - don't fight a fresh _refresh()
			_refresh()

# Builds a small portrait swatch (blank until the async render above lands)
# for use inline in a boss/threat row.
func _portrait_rect(cache_key: String, role: String, rarity: int, boss_visual: bool) -> TextureRect:
	var rect = TextureRect.new()
	rect.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var tex = _get_portrait(cache_key, role, rarity, boss_visual)
	if tex:
		rect.texture = tex
	return rect

const WarRoomSnapshot = preload("res://scripts/ai/WarRoomSnapshot.gd")

func _get_director():
	var main = get_tree().current_scene
	if main and "world" in main and main.world:
		var live = main.world.get_node_or_null("SquadDirector")
		if live:
			return live
	# No live game running (e.g. opened straight from the Main Menu) - fall
	# back to a read-only snapshot of the last saved learned_state.json so
	# the War Room still shows real data instead of just "no data yet".
	return WarRoomSnapshot.load_from_disk()

# --- Shared row/label builders ---------------------------------------------

func _lbl(parent: Control, text: String, color: Color = COL_CORE, font_size: int = 13) -> Label:
	var l = Label.new()
	l.text = text
	l.modulate = color
	l.add_theme_font_size_override("font_size", font_size)
	parent.add_child(l)
	return l

func _clear(parent: Control):
	for c in parent.get_children():
		c.queue_free()

func _format_roles(roles: Dictionary) -> String:
	var parts: Array[String] = []
	for r in roles:
		parts.append(str(int(roles[r])) + "x " + str(r))
	return ", ".join(parts)

func _fitness_color(avg: float, deployed: int) -> Color:
	if deployed == 0: return COL_DIM
	if avg >= 110.0: return COL_GOOD
	if avg < 60.0: return COL_BAD
	return COL_CORE

func _refresh():
	var director = _get_director()

	_clear(threat_vbox)
	_clear(doctrine_vbox)
	_clear(boss_vbox)
	_clear(captures_vbox)
	_clear(death_vbox)

	# Death log is pure SaveManager data, independent of a live SquadDirector -
	# builds even from the Main Menu (before any run/Director exists) or
	# right after a fresh death kicked the player back to the Garage.
	_build_death_log()

	if not director:
		_lbl(threat_vbox, "No combat data yet - the Director deploys with the first wave.", COL_DIM)
		tree_view.set_templates([])
		return

	_build_threat_board(director)
	tree_view.set_templates(director.templates)
	_build_doctrines(director)
	_build_bosses(director)
	_build_captures(director)

# --- Threat Board ------------------------------------------------------------

func _build_threat_board(director):
	_lbl(threat_vbox, "YOUR MECH: POWER ESTIMATE", COL_SECTION, 16)
	var player_power = director._estimate_player_power() if director.has_method("_estimate_player_power") else 700.0
	var player_rarity = director._player_dominant_rarity() if director.has_method("_player_dominant_rarity") else 0
	var rarity_names = ["Scrap", "Standard", "Advanced", "Legendary", "Mythic"]
	var r_name = rarity_names[clamp(player_rarity, 0, 4)]
	_lbl(threat_vbox, "  Power Score: %.0f" % player_power, COL_TITLE, 14)
	_lbl(threat_vbox, "  Dominant Tier: %s" % r_name, COL_TITLE, 14)
	_lbl(threat_vbox, "  (This is the baseline the AI uses to scale 'near-peer' squads against you)\n", COL_DIM, 11)

	_lbl(threat_vbox, "TOP THREATS - most effective squad doctrines against you", COL_SECTION, 16)
	_lbl(threat_vbox, "Efficacy graphs show per-deployment fitness (dashed line = expected average, 100).", COL_DIM, 11)

	var deployed: Array = director.templates.filter(func(t): return t.times_deployed > 0)
	deployed.sort_custom(func(a, b): return a.get_average_fitness() > b.get_average_fitness())

	if deployed.is_empty():
		_lbl(threat_vbox, "\nNo squads have completed a deployment yet.", COL_DIM)
	for i in range(min(6, deployed.size())):
		var t = deployed[i]
		var row = PanelContainer.new()
		var row_style = StyleBoxFlat.new()
		row_style.bg_color = Color(0.11, 0.12, 0.16)
		row_style.content_margin_left = 10
		row_style.content_margin_right = 10
		row_style.content_margin_top = 6
		row_style.content_margin_bottom = 6
		row.add_theme_stylebox_override("panel", row_style)
		threat_vbox.add_child(row)

		var row_vbox = VBoxContainer.new()
		row.add_child(row_vbox)

		var h = HBoxContainer.new()
		row_vbox.add_child(h)

		var info = VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		var avg = t.get_average_fitness()
		var status = "TRIAL" if t.is_experimental else "CORE"
		_lbl(info, "#%d  %s  [%s]" % [i + 1, t.template_name, status], COL_TRIAL if t.is_experimental else COL_TITLE, 16)
		_lbl(info, _format_roles(t.required_roles) + ("  |  shielded" if t.has_shields else ""), COL_DIM, 12)
		_lbl(info, "avg fitness %.0f  |  deployed %d  |  spawn weight %.0f" % [avg, t.times_deployed, t.spawn_weight], _fitness_color(avg, t.times_deployed), 12)
		if t.parent_name != "":
			_lbl(info, "lineage: " + t.parent_name, COL_GHOST, 11)

		var spark = Sparkline.new()
		spark.data = t.fitness_history.duplicate()
		spark.custom_minimum_size = Vector2(260, 64)
		h.add_child(spark)

		# Squad chunk / individual unit chunk: one portrait per distinct
		# role this template actually deploys, cached by role name (shared
		# across every template that uses the same role - a "sniper" looks
		# the same everywhere), labeled with the role's headcount in THIS
		# template.
		var units_row = HBoxContainer.new()
		row_vbox.add_child(units_row)
		for role in t.required_roles:
			var unit_col = VBoxContainer.new()
			unit_col.alignment = BoxContainer.ALIGNMENT_CENTER
			units_row.add_child(unit_col)
			unit_col.add_child(_portrait_rect("role:" + str(role), str(role), HexTile.Rarity.RARE, false))
			var count_lbl = _lbl(unit_col, "%dx %s" % [int(t.required_roles[role]), str(role).capitalize()], COL_DIM, 10)
			count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Intel + field status below the board
	_lbl(threat_vbox, "\nINTEL: YOUR OBSERVED DOCTRINE", COL_SECTION, 15)
	if director.total_damage_taken <= 0.0:
		_lbl(threat_vbox, "No damage telemetry logged yet.", COL_DIM, 12)
	else:
		var bias_graph = BiasGraph.new()
		bias_graph.player_data = director.player_element_usage.duplicate()
		bias_graph.bot_data = director.bot_element_usage.duplicate()
		bias_graph.total_player = director.total_damage_taken
		bias_graph.total_bot = director.total_bot_damage_dealt
		bias_graph.synergy_names = SYNERGY_NAMES
		bias_graph.custom_minimum_size = Vector2(260, 200)
		threat_vbox.add_child(bias_graph)

	if director.total_player_kills > 0:
		_lbl(threat_vbox, "\nKILL METHODS (what actually finishes enemies)", COL_SECTION, 13)
		var kills: Array = []
		for element in director.player_kill_methods:
			kills.append([element, director.player_kill_methods[element]])
		kills.sort_custom(func(a, b): return a[1] > b[1])
		for kv in kills:
			var share = float(kv[1]) / float(director.total_player_kills)
			# Any non-RAW synergy carrying >=50% of kills draws the
			# director's jammer counter-doctrine (see SquadDirector).
			var overuse = str(kv[0]) != "RAW" and share >= 0.5 and director.total_player_kills >= 15
			var warn_txt = "   << jammer counter-doctrine targeting this" if overuse else ""
			_lbl(threat_vbox, "  %s: %d (%.0f%%)%s" % [str(kv[0]), kv[1], share * 100.0, warn_txt], COL_BAD if overuse else COL_CORE, 12)

	_lbl(threat_vbox, "\nFIELD STATUS", COL_SECTION, 15)
	_lbl(threat_vbox, "  Active squads: %d  |  Unaffiliated bots: %d" % [director.active_squads.size(), director.wild_bots.size()], COL_CORE, 12)
	for squad in director.active_squads:
		if is_instance_valid(squad) and squad.template:
			_lbl(threat_vbox, "  > '%s': %d/%d members" % [squad.template.template_name, squad.active_members, squad.initial_members], COL_DIM, 12)

# --- Doctrines ---------------------------------------------------------------

# times_used-weighted average across every profile in a role's pool (not a
# plain average of each profile's own average, which would let a single
# untested profile with one lucky deployment skew the role summary as much
# as a profile with 50 deployments). Returns -1.0 if the role has no
# deployments at all yet, so the caller can show "no data" instead of 0.
func _role_average_fitness(profiles: Array) -> float:
	var total_fitness = 0.0
	var total_used = 0
	for p in profiles:
		total_fitness += p.total_fitness
		total_used += p.times_used
	if total_used == 0:
		return -1.0
	return total_fitness / float(total_used)

func _build_doctrines(director):
	_lbl(doctrine_vbox, "ALL SQUAD DOCTRINES", COL_SECTION, 15)
	var sorted_templates: Array = director.templates.duplicate()
	sorted_templates.sort_custom(func(a, b): return a.spawn_weight > b.spawn_weight)
	for t in sorted_templates:
		var avg = t.get_average_fitness()
		var fit_str = ("%.0f" % avg) if t.times_deployed > 0 else "-"
		_lbl(doctrine_vbox, "%s  [%s]" % [t.template_name, "TRIAL" if t.is_experimental else "CORE"], COL_TRIAL if t.is_experimental else COL_CORE, 14)
		_lbl(doctrine_vbox, "   %s | weight %.0f | deployed %d | avg %s" % [_format_roles(t.required_roles), t.spawn_weight, t.times_deployed, fit_str], _fitness_color(avg, t.times_deployed), 12)

	_lbl(doctrine_vbox, "\nLOADOUT DOCTRINES (solver profiles, by role)", COL_SECTION, 15)
	_lbl(doctrine_vbox, "Each role evolves its own lineage - a sniper doctrine no longer competes with a brawler doctrine for the same rotation.", COL_DIM, 11)
	var by_role: Dictionary = {}
	for p in director.solver_profiles:
		var r = p.role if p.role != "" else "(unassigned/legacy)"
		if not by_role.has(r):
			by_role[r] = []
		by_role[r].append(p)

	if by_role.is_empty():
		_lbl(doctrine_vbox, "   (reactive baseline only - no mutations on trial yet)", COL_DIM, 12)

	var role_order: Array = SquadTemplateMutator.ALL_ROLES.duplicate()
	for r in by_role:
		if not role_order.has(r):
			role_order.append(r) # diver/legacy-unassigned etc.

	for role in role_order:
		if not by_role.has(role):
			continue
		var profiles: Array = by_role[role]
		profiles.sort_custom(func(a, b): return a.spawn_weight > b.spawn_weight)
		var role_avg = _role_average_fitness(profiles)
		var role_header = str(role).capitalize()
		role_header += (" - role avg fitness %.0f" % role_avg) if role_avg >= 0.0 else " - no deployments yet"
		_lbl(doctrine_vbox, "\n" + role_header, COL_SECTION, 13)
		for p in profiles:
			var avg = p.get_average_fitness()
			var syn = "none"
			if p.favored_synergy >= 0 and p.favored_synergy < SYNERGY_NAMES.size():
				syn = SYNERGY_NAMES[p.favored_synergy]
			var fit_str = ("%.0f" % avg) if p.times_used > 0 else "-"
			_lbl(doctrine_vbox, "  %s  [%s]" % [p.profile_name, "TRIAL" if p.is_experimental else "CORE"], COL_TRIAL if p.is_experimental else COL_CORE, 14)
			_lbl(doctrine_vbox, "     element %s | pierce %.2f / amp %.2f | weight %.0f | used %d | avg %s" % [syn, p.pierce_priority, p.amplify_priority, p.spawn_weight, p.times_used, fit_str], _fitness_color(avg, p.times_used), 12)

	var share_bar = HBoxContainer.new()
	doctrine_vbox.add_child(share_bar)
	var btn_export = Button.new()
	btn_export.text = "Export AI Profile to Clipboard"
	btn_export.pressed.connect(func():
		var d = _get_director()
		# AI profiles aren't tied to any save/session - a live SquadDirector
		# and a no-live-game WarRoomSnapshot (see that class) both implement
		# export/import against the exact same on-disk learned_state.json,
		# so this works identically whether a game is running or not.
		if d and d.has_method("export_learned_state_to_clipboard"):
			d.export_learned_state_to_clipboard()
			status_label.text = "Exported - paste anywhere to share."
		elif status_label:
			status_label.text = "Couldn't access AI profile data."
	)
	share_bar.add_child(btn_export)
	var btn_import = Button.new()
	btn_import.text = "Import AI Profile from Clipboard"
	btn_import.pressed.connect(func():
		var d = _get_director()
		if not (d and d.has_method("import_learned_state_from_clipboard")):
			if status_label:
				status_label.text = "Couldn't access AI profile data."
		elif d.import_learned_state_from_clipboard():
			_refresh()
			status_label.text = "Imported and merged."
		elif status_label:
			status_label.text = "Clipboard doesn't contain a valid profile."
	)
	share_bar.add_child(btn_import)

	# PvP Traveling Champions: share your MECH (not the AI) as a Champion
	# Card PNG - the full loadout rides inside the image (see
	# scripts/pvp/ChampionCard.gd). Import scans user://champion_cards/ for
	# card PNGs friends gave you and registers them as challengers.
	var champ_bar = HBoxContainer.new()
	doctrine_vbox.add_child(champ_bar)
	var btn_card = Button.new()
	btn_card.text = "Export Champion Card (PNG)"
	btn_card.pressed.connect(func():
		var players = get_tree().get_nodes_in_group("player")
		if players.is_empty():
			status_label.text = "Start a game to export your champion."
			return
		var path = await ChampionCard.export_card(players[0], SaveManager.pilot_name)
		if path != "":
			status_label.text = "Champion Card saved: %s (share the PNG!)" % ProjectSettings.globalize_path(path)
		else:
			status_label.text = "Card export failed - see log."
	)
	champ_bar.add_child(btn_card)
	var btn_card_import = Button.new()
	btn_card_import.text = "Import Champion Cards"
	btn_card_import.pressed.connect(func():
		var imported = ChampionCard.import_cards_from_dir()
		var total = ChampionCard.list_ghosts().size()
		if imported.is_empty():
			status_label.text = "No new cards in %s (drop card PNGs there). %d challenger(s) registered." % [ProjectSettings.globalize_path(ChampionCard.CARDS_DIR), total]
		else:
			var names = []
			for g in imported:
				names.append(g.get("pilot_name", "?"))
			status_label.text = "Imported: %s. %d challenger(s) may now appear in waves!" % [", ".join(names), total]
	)
	champ_bar.add_child(btn_card_import)
	status_label = _lbl(doctrine_vbox, "", COL_DIM, 11)

# --- Captured Loadouts -------------------------------------------------------
# Utility-SOC: "save the actual tile inventory/layout of the most effective
# individual enemies so I can see it in the war room." One entry per
# combat_role, replaced only when a new individual enemy beats the stored
# fitness high score for that role - see SquadDirector._maybe_capture_loadout.
# Text/summary cards (tile count + rarity breakdown), not a live mini
# hex-grid render - there's no lightweight preview widget to reuse yet
# (GarageGridRenderer is a heavyweight Garage-only Control wrapping a real
# HexGridComponent node).
const RARITY_NAMES = ["Common", "Uncommon", "Rare", "Legendary", "Mythic"]

func _build_captures(director):
	_lbl(captures_vbox, "CAPTURED ENEMY LOADOUTS", COL_SECTION, 15)
	_lbl(captures_vbox, "The single highest-fitness enemy build seen per role - a real snapshot of what actually worked against you.", COL_DIM, 11)

	var captured: Dictionary = director.get("captured_loadouts") if "captured_loadouts" in director else {}
	if captured.is_empty():
		_lbl(captures_vbox, "\n(no captures yet - defeat enemies to start building this list)", COL_DIM, 12)
		return

	var role_order: Array = SquadTemplateMutator.ALL_ROLES.duplicate()
	for r in captured:
		if not role_order.has(r):
			role_order.append(r)

	for role in role_order:
		if not captured.has(role):
			continue
		var entry = captured[role]
		var rarity_idx = clamp(int(entry.get("rarity", 0)), 0, RARITY_NAMES.size() - 1)
		var components: Dictionary = entry.get("components", {})

		var tile_count = 0
		var rarity_counts: Dictionary = {}
		for slot in components:
			var comp_data = components[slot]
			for tile_data in comp_data.get("tiles", []):
				tile_count += 1
				var tr = int(tile_data.get("rarity", 0))
				rarity_counts[tr] = rarity_counts.get(tr, 0) + 1

		var breakdown: Array[String] = []
		for tr in range(RARITY_NAMES.size() - 1, -1, -1):
			if rarity_counts.has(tr):
				breakdown.append("%dx %s" % [rarity_counts[tr], RARITY_NAMES[tr]])

		_lbl(captures_vbox, "\n%s  [%s]" % [str(role).capitalize(), RARITY_NAMES[rarity_idx]], COL_CORE, 14)
		_lbl(captures_vbox, "   fitness %.0f | %d components | %d tiles | %s" % [float(entry.get("fitness", 0.0)), components.size(), tile_count, ", ".join(breakdown)], COL_GOOD, 12)

# --- Death Log ---------------------------------------------------------------
# Player deaths only (deliberately not a kill log - the user's own scoping
# call). SaveManager.death_log is append-only, capped, oldest-first;
# reversed here so the most recent death reads first.
func _build_death_log():
	_lbl(death_vbox, "DEATH LOG", COL_SECTION, 16)
	_lbl(death_vbox, "Every time you've died on this save - wave reached, what got you, when.", COL_DIM, 11)

	var log: Array = SaveManager.death_log
	if log.is_empty():
		_lbl(death_vbox, "\n(no deaths recorded yet)", COL_DIM, 12)
		return

	for i in range(log.size() - 1, -1, -1):
		var entry = log[i]
		var row = PanelContainer.new()
		var row_style = StyleBoxFlat.new()
		row_style.bg_color = Color(0.11, 0.12, 0.16)
		row_style.content_margin_left = 10
		row_style.content_margin_right = 10
		row_style.content_margin_top = 4
		row_style.content_margin_bottom = 4
		row.add_theme_stylebox_override("panel", row_style)
		death_vbox.add_child(row)

		var h = HBoxContainer.new()
		row.add_child(h)
		_lbl(h, "Wave %s" % str(entry.get("wave", "?")), COL_TITLE, 13).custom_minimum_size = Vector2(80, 0)
		_lbl(h, "killed by " + str(entry.get("killed_by", "Unknown")), COL_BAD, 13).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_lbl(h, str(entry.get("timestamp", "")), COL_DIM, 11)

# --- Bosses ------------------------------------------------------------------
# Readable labels for BossProfile's raw ability/style id strings.
const ABILITY_LABELS = {
	"shockwave": "Shockwave (AoE knockback burst)",
	"railgun": "Railgun (locked piercing beam)",
	"blink_strike": "Blink Strike (teleport + free ambush shot)",
	"fire_pool": "Fire Pool (DoT hazard zone)",
	"jam_burst": "Jam Burst (vision blackout)",
	"rally": "Rally (self-heal + shield + speed burst)",
}
const ENRAGE_LABELS = {
	"berserker": "Berserker (fire rate + speed)",
	"juggernaut": "Juggernaut (tighter engagement, tankier push)",
	"vampiric": "Vampiric (heals on enrage, leans aggressive)",
	"unstable": "Unstable (erratic, biggest swings)",
}
const POSITION_LABELS = {
	"aggressive": "Aggressive (closes distance, no kiting)",
	"kiter": "Kiter (holds range, smart multi-angle retreat)",
	"circler": "Circler (orbits at range)",
}

func _build_bosses(director):
	_lbl(boss_vbox, "BOSS PROFILES - evolving kits, not just a scaled-up grunt", COL_SECTION, 16)
	_lbl(boss_vbox, "Click a boss to drill into its full kit and efficacy history. TRIAL profiles are experimental mutations still proving themselves.", COL_DIM, 11)

	if not ("boss_profiles" in director) or director.boss_profiles.is_empty():
		_lbl(boss_vbox, "\nNo boss profiles registered yet.", COL_DIM)
		return

	var sorted_bosses: Array = director.boss_profiles.duplicate()
	sorted_bosses.sort_custom(func(a, b): return a.spawn_weight > b.spawn_weight)

	for bp in sorted_bosses:
		_build_boss_row(bp)

func _build_boss_row(bp):
	var card = PanelContainer.new()
	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color(0.11, 0.12, 0.16)
	card_style.content_margin_left = 10
	card_style.content_margin_right = 10
	card_style.content_margin_top = 6
	card_style.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", card_style)
	boss_vbox.add_child(card)

	var card_h = HBoxContainer.new()
	card.add_child(card_h)
	# Boss chunk: one portrait per boss, cached by profile_name - visually
	# distinct bosses that share a base_role (e.g. two "brawler" bosses)
	# still each get rendered, since the cache key is the boss identity, not
	# just its role.
	card_h.add_child(_portrait_rect("boss:" + bp.profile_name, bp.base_role, HexTile.Rarity.LEGENDARY, true))

	var card_vbox = VBoxContainer.new()
	card_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_h.add_child(card_vbox)

	var avg = bp.get_average_fitness()
	var status = "TRIAL" if bp.is_experimental else "CORE"
	var header_btn = Button.new()
	header_btn.flat = true
	header_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var expanded = _boss_expanded.get(bp.profile_name, false)
	var arrow = "v " if expanded else "> "
	header_btn.text = "%s%s  [%s]  (%s)  avg %s  |  weight %.0f  |  used %d" % [
		arrow, bp.profile_name, status, bp.base_role.capitalize(),
		("%.0f" % avg) if bp.times_used > 0 else "-", bp.spawn_weight, bp.times_used
	]
	header_btn.add_theme_color_override("font_color", COL_TRIAL if bp.is_experimental else COL_TITLE)
	card_vbox.add_child(header_btn)

	var detail = VBoxContainer.new()
	detail.visible = expanded
	card_vbox.add_child(detail)

	header_btn.pressed.connect(func():
		var now_expanded = not detail.visible
		detail.visible = now_expanded
		_boss_expanded[bp.profile_name] = now_expanded
		header_btn.text = ("v " if now_expanded else "> ") + header_btn.text.substr(2)
	)

	# Always populate (not just when starting expanded) - the row's detail
	# panel is built once here and just toggles visibility afterward, rather
	# than trying to lazily build it on first expand.
	_populate_boss_detail(detail, bp, avg)

func _populate_boss_detail(detail: VBoxContainer, bp, avg: float):
	_lbl(detail, "hp multiplier: %.2fx" % bp.hp_mult, COL_CORE, 12)
	_lbl(detail, "enrage style: " + ENRAGE_LABELS.get(bp.enrage_style, bp.enrage_style), COL_CORE, 12)
	_lbl(detail, "position style: " + POSITION_LABELS.get(bp.position_style, bp.position_style), COL_CORE, 12)

	_lbl(detail, "ability pool:", COL_CORE, 12)
	if bp.ability_pool.is_empty():
		_lbl(detail, "   (none)", COL_DIM, 11)
	for a in bp.ability_pool:
		_lbl(detail, "   - " + ABILITY_LABELS.get(a, str(a)), COL_DIM, 11)
	if bp.ability_pool.size() >= 2:
		_lbl(detail, "   chains at enrage stage 2+ (below 20% HP)", COL_TRIAL, 11)

	if bp.parent_name != "":
		_lbl(detail, "lineage: mutated from " + bp.parent_name, COL_GHOST, 11)
	else:
		_lbl(detail, "lineage: original archetype", COL_GHOST, 11)

	var stats_row = HBoxContainer.new()
	detail.add_child(stats_row)
	var stats_info = VBoxContainer.new()
	stats_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_row.add_child(stats_info)
	_lbl(stats_info, "deployments: %d" % bp.times_used, COL_CORE, 12)
	_lbl(stats_info, "avg fitness: %s" % (("%.0f" % avg) if bp.times_used > 0 else "-"), _fitness_color(avg, bp.times_used), 12)
	_lbl(stats_info, "spawn weight: %.0f (base %.0f)" % [bp.spawn_weight, bp.base_spawn_weight], COL_DIM, 12)

	var spark = Sparkline.new()
	spark.data = bp.fitness_history.duplicate()
	spark.custom_minimum_size = Vector2(260, 64)
	stats_row.add_child(spark)

	_lbl(detail, "", COL_DIM, 4) # small gap before the next card

# =============================================================================
# Efficacy sparkline: per-deployment fitness, dashed baseline at 100.
class Sparkline:
	extends Control

	var data: Array = []

	func _draw():
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.08), true)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.3, 0.32, 0.38), false, 1.0)

		var pad = 6.0
		var lo = 0.0
		var hi = 150.0
		for v in data:
			hi = max(hi, float(v) + 10.0)

		var y_for = func(v: float) -> float:
			return size.y - pad - (clamp(v, lo, hi) - lo) / (hi - lo) * (size.y - pad * 2.0)

		# Baseline: fitness 100 = "expected average" per SquadTemplate's convention
		var base_y = y_for.call(100.0)
		draw_dashed_line(Vector2(pad, base_y), Vector2(size.x - pad, base_y), Color(0.5, 0.5, 0.55, 0.7), 1.0, 4.0)

		if data.size() == 0:
			draw_string(ThemeDB.fallback_font, Vector2(pad + 2, size.y / 2.0), "no deployments", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.5, 0.55))
			return

		var n = data.size()
		var pts = PackedVector2Array()
		for i in range(n):
			var x = pad + (float(i) / max(1, n - 1)) * (size.x - pad * 2.0)
			pts.append(Vector2(x, y_for.call(float(data[i]))))

		if n == 1:
			draw_circle(pts[0], 3.0, Color(0.4, 1.0, 0.5))
			return
		for i in range(n - 1):
			var seg_color = Color(0.4, 1.0, 0.5) if float(data[i + 1]) >= 100.0 else Color(1.0, 0.55, 0.4)
			draw_line(pts[i], pts[i + 1], seg_color, 1.5)
		draw_circle(pts[n - 1], 3.0, Color(1.0, 0.85, 0.4))

# =============================================================================
# Dendrogram of squad lineages, built from SquadTemplate.parent_name.
# Culled/unknown ancestors render as grey "ghost" nodes so surviving lines
# keep their full history visible.
class DendrogramView:
	extends Control

	const COL_W = 240.0
	const ROW_H = 44.0
	const MARGIN = 24.0
	const NODE_R = 6.0

	var _nodes: Dictionary = {}   # name -> {template, children: [names], depth, y}
	var _roots: Array = []

	func set_templates(templates: Array):
		_nodes.clear()
		_roots = []

		for t in templates:
			_nodes[t.template_name] = {"template": t, "children": [], "depth": 0, "y": 0.0}
		# Link children; materialize ghost ancestors for culled parents.
		for t in templates:
			if t.parent_name == "":
				continue
			if not _nodes.has(t.parent_name):
				_nodes[t.parent_name] = {"template": null, "children": [], "depth": 0, "y": 0.0}
			_nodes[t.parent_name]["children"].append(t.template_name)

		var has_parent := {}
		for name in _nodes:
			for c in _nodes[name]["children"]:
				has_parent[c] = true
		for name in _nodes:
			if not has_parent.has(name):
				_roots.append(name)
		_roots.sort()

		# Layout: depth-first; leaves get successive rows, parents center on
		# their children. Standard dendrogram shape.
		var next_row = [0]
		for r in _roots:
			_layout(r, 0, next_row)

		var max_depth = 0
		for name in _nodes:
			max_depth = max(max_depth, _nodes[name]["depth"])
		custom_minimum_size = Vector2(
			MARGIN * 2.0 + (max_depth + 1) * COL_W,
			MARGIN * 2.0 + next_row[0] * ROW_H
		)
		queue_redraw()

	func _layout(name: String, depth: int, next_row: Array) -> float:
		var node = _nodes[name]
		node["depth"] = depth
		var kids: Array = node["children"]
		if kids.is_empty():
			node["y"] = next_row[0] * ROW_H
			next_row[0] += 1
		else:
			var first_y = 0.0
			var last_y = 0.0
			for i in range(kids.size()):
				var ky = _layout(kids[i], depth + 1, next_row)
				if i == 0: first_y = ky
				last_y = ky
			node["y"] = (first_y + last_y) / 2.0
		return node["y"]

	func _node_pos(name: String) -> Vector2:
		var node = _nodes[name]
		return Vector2(MARGIN + node["depth"] * COL_W, MARGIN + node["y"] + ROW_H * 0.5)

	func _draw():
		if _nodes.is_empty():
			draw_string(ThemeDB.fallback_font, Vector2(20, 30), "No templates registered yet.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.6, 0.6))
			return

		# Elbow connectors first, so nodes draw on top
		for name in _nodes:
			var p = _node_pos(name)
			for c in _nodes[name]["children"]:
				var q = _node_pos(c)
				var mid_x = p.x + COL_W * 0.45
				var line_color = Color(0.4, 0.45, 0.55, 0.8)
				draw_line(p, Vector2(mid_x, p.y), line_color, 1.5)
				draw_line(Vector2(mid_x, p.y), Vector2(mid_x, q.y), line_color, 1.5)
				draw_line(Vector2(mid_x, q.y), q, line_color, 1.5)

		for name in _nodes:
			var node = _nodes[name]
			var p = _node_pos(name)
			var t = node["template"]
			var color: Color
			var label: String
			if t == null:
				color = Color(0.45, 0.45, 0.5) # ghost: culled or hand-authored ancestor no longer in rotation
				label = name + "  (culled)"
				draw_arc(p, NODE_R, 0, TAU, 16, color, 1.5)
			else:
				var avg = t.get_average_fitness()
				if t.is_experimental:
					color = Color(1.0, 0.8, 0.3)
				elif t.times_deployed > 0 and avg >= 110.0:
					color = Color(0.4, 1.0, 0.5)
				else:
					color = Color(0.9, 0.9, 0.9)
				var avg_str = (" %.0f" % avg) if t.times_deployed > 0 else ""
				label = name + avg_str
				draw_circle(p, NODE_R, color)
			draw_string(ThemeDB.fallback_font, p + Vector2(NODE_R + 4.0, 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, COL_W - NODE_R * 2.0 - 8.0, 12, color)

# =============================================================================
# Bar chart of Player vs Bot element biases.
class BiasGraph:
	extends Control

	var player_data: Dictionary = {}
	var bot_data: Dictionary = {}
	var total_player: float = 0.0
	var total_bot: float = 0.0
	var synergy_names: Array = []

	func _draw():
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.08), true)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.3, 0.32, 0.38), false, 1.0)
		
		if total_player <= 0.0 and total_bot <= 0.0:
			draw_string(ThemeDB.fallback_font, Vector2(10, 20), "No damage telemetry logged yet.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.5, 0.55))
			return
			
		var elements = []
		for e in player_data.keys():
			if not elements.has(e): elements.append(e)
		for e in bot_data.keys():
			if not elements.has(e): elements.append(e)
			
		elements.sort_custom(func(a, b): 
			var a_val = (player_data.get(a, 0.0) / max(1.0, total_player)) + (bot_data.get(a, 0.0) / max(1.0, total_bot))
			var b_val = (player_data.get(b, 0.0) / max(1.0, total_player)) + (bot_data.get(b, 0.0) / max(1.0, total_bot))
			return a_val > b_val
		)
		
		var y = 25.0
		var row_h = 24.0
		var bar_h = 8.0
		var max_bar_w = size.x - 160.0
		if max_bar_w < 50: max_bar_w = 50.0
		
		# Draw legend
		draw_string(ThemeDB.fallback_font, Vector2(size.x - 100, 15), "Player Bias", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.2, 0.8, 1.0))
		draw_string(ThemeDB.fallback_font, Vector2(size.x - 100, 25), "Bot Bias", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.4, 0.2))
		
		for e in elements:
			if y + row_h > size.y: break
			var el_name = str(e)
			var as_int = int(e) if str(e).is_valid_int() else -1
			if as_int >= 0 and as_int < synergy_names.size():
				el_name = synergy_names[as_int]
				
			var p_share = player_data.get(e, 0.0) / max(1.0, total_player)
			var b_share = bot_data.get(e, 0.0) / max(1.0, total_bot)
			
			if p_share < 0.01 and b_share < 0.01:
				continue
				
			var warn = "!" if p_share > 0.4 else ""
			var col = Color(1.0, 0.8, 0.3) if p_share > 0.4 else Color(0.8, 0.8, 0.8)
			draw_string(ThemeDB.fallback_font, Vector2(10, y + 12), el_name + warn, HORIZONTAL_ALIGNMENT_LEFT, 100, 11, col)
			
			# Player bar
			draw_rect(Rect2(110, y, max_bar_w * p_share, bar_h), Color(0.2, 0.8, 1.0))
			draw_string(ThemeDB.fallback_font, Vector2(115 + max_bar_w * p_share, y + 8), "%.0f%%" % (p_share * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.2, 0.8, 1.0))
			
			# Bot bar
			draw_rect(Rect2(110, y + bar_h + 1, max_bar_w * b_share, bar_h), Color(1.0, 0.4, 0.2))
			draw_string(ThemeDB.fallback_font, Vector2(115 + max_bar_w * b_share, y + bar_h + 9), "%.0f%%" % (b_share * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.4, 0.2))
			
			y += row_h
