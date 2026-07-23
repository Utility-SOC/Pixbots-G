class_name SquadDirector
extends Node

const SquadTemplateMutator = preload("res://scripts/ai/SquadTemplateMutator.gd")
const SolverProfile = preload("res://scripts/ai/SolverProfile.gd")
const BossProfile = preload("res://scripts/ai/BossProfile.gd")
const WarRoomNames = preload("res://scripts/ai/WarRoomNames.gd")
const TemplateEvolution = preload("res://scripts/ai/TemplateEvolution.gd")
const ProfileEvolution = preload("res://scripts/ai/ProfileEvolution.gd")
const BossEvolution = preload("res://scripts/ai/BossEvolution.gd")
const DroneBayTileScript = preload("res://scripts/tiles/DroneBayTile.gd")
const WarRoomSnapshotScript = preload("res://scripts/ai/WarRoomSnapshot.gd")

# --- AI evolution: three near-identical evolutionary subsystems (squad
# composition, loadout doctrine, boss kits), each mutate/crossover/cull/
# graduate/select for their own data type. Composed-RefCounted-helper
# pattern (same as Mech.gd's PlayerController/BossBrain/StatusEffectRunner)
# rather than three flat sets of functions interleaved in this file - see
# each helper's own header comment. Tuning constants live on their
# respective helper now (TemplateEvolution.MAX_EXPERIMENTAL_TEMPLATES etc.)
var template_evolution: TemplateEvolution
var profile_evolution: ProfileEvolution
var boss_evolution: BossEvolution

var solver_profiles: Array[SolverProfile] = []
var boss_profiles: Array[BossProfile] = []

var templates: Array[SquadTemplate] = []
var active_squads: Array[Squad] = []
var wild_bots: Array[Node] = []

# --- Learned-state persistence -------------------------------------------
# SquadProfileManager was fully written but never instantiated anywhere,
# which meant every template weight, fitness record, and evolved
# composition reset on every game restart. The director now owns one:
# learned state loads after Main registers the default templates (see
# load_learned_state, called from Main._start_wave) and saves after every
# squad defeat - the same moment fitness/culling/graduation happen, so
# what's on disk is always the post-evaluation state.
const LEARNED_STATE_NAME = "learned_state"
var profile_manager: SquadProfileManager = null

# --- Rival Round State ---
var current_round: int = 1
var rivals_fought_this_round: int = 0
var active_rival_pool: Array = []
var consecutive_rival_losses: int = 0
var all_rival_profiles: Dictionary = {}

func get_next_rival() -> String:
	if all_rival_profiles.is_empty(): return ""
	if active_rival_pool.is_empty():
		current_round += 1
		rivals_fought_this_round = 0
		active_rival_pool = all_rival_profiles.keys()
		
	# If Arthur is in the pool, restrict him until we've fought 10 rivals this round.
	var valid_candidates = []
	for r in active_rival_pool:
		if r == "Arthur" and (all_rival_profiles.size() - rivals_fought_this_round) > 5 and active_rival_pool.size() > 1:
			continue
		valid_candidates.append(r)
		
	var chosen = valid_candidates[randi() % valid_candidates.size()]
	active_rival_pool.erase(chosen)
	rivals_fought_this_round += 1
	save_learned_state()
	return chosen

func _ready():
	template_evolution = TemplateEvolution.new(self)
	profile_evolution = ProfileEvolution.new(self)
	boss_evolution = BossEvolution.new(self)

	profile_manager = SquadProfileManager.new()
	profile_manager.name = "ProfileManager"
	add_child(profile_manager)
	boss_evolution.register_defaults()

	# Load Rival profiles
	var factory = load("res://scripts/ai/RivalProfilesFactory.gd")
	if factory:
		all_rival_profiles = factory.create_profiles(DialogueManager.dialogue_data)
		# Initialize pool if empty
		if active_rival_pool.is_empty():
			active_rival_pool = all_rival_profiles.keys()

# Merge templates by template_name, solver profiles by profile_name, and
# boss profiles by profile_name: known entries get their learned stats
# restored in place, unknown ones (evolved/graduated compositions from past
# sessions, or an imported friend's profile) get registered fresh. Shared
# by disk-load and clipboard-import so both behave identically.
func _merge_learned(loaded_templates: Array, loaded_profiles: Array, loaded_boss_profiles: Array = []):
	for lt in loaded_templates:
		var existing: SquadTemplate = null
		for t in templates:
			if t.template_name == lt.template_name:
				existing = t
				break
		if existing:
			existing.from_dict(lt.to_dict())
		else:
			register_template(lt)

	for lp in loaded_profiles:
		var existing_p: SolverProfile = null
		for p in solver_profiles:
			if p.profile_name == lp.profile_name:
				existing_p = p
				break
		if existing_p:
			existing_p.from_dict(lp.to_dict())
		else:
			solver_profiles.append(lp)

	for lbp in loaded_boss_profiles:
		var existing_bp: BossProfile = null
		for bp in boss_profiles:
			if bp.profile_name == lbp.profile_name:
				existing_bp = bp
				break
		if existing_bp:
			existing_bp.from_dict(lbp.to_dict())
		else:
			boss_profiles.append(lbp)

# Merge path for a CROSS-PILOT clipboard import - see _merge_learned above
# for the same-pilot load/save-restore path, which stays overwrite-based
# ("resume where I left off" should update your own templates in place).
# The actual merge logic now lives on WarRoomSnapshot.merge_imported() -
# shared with the no-live-game War Room import path (see that class's own
# header on why export/import shouldn't need a live game at all) - this is
# a thin wrapper so the two can never drift apart.
func _merge_imported(loaded_templates: Array, loaded_profiles: Array, loaded_boss_profiles: Array = []):
	WarRoomSnapshotScript.merge_imported(templates, solver_profiles, boss_profiles, loaded_templates, loaded_profiles, loaded_boss_profiles)

func load_learned_state():
	if not profile_manager:
		return

	# 1. Moddable baseline pack from res://config/default_squads.json (or a
	# user override in user://ai_profiles/) - merged before learned state so
	# saved learning applied on top wins. This is what makes the config
	# folder a real modding surface (see MODDING.md).
	if profile_manager.has_profile("default_squads"):
		_merge_learned(
			profile_manager.load_profile("default_squads"),
			profile_manager.load_solver_profiles("default_squads"),
			profile_manager.load_boss_profiles("default_squads")
		)

	# 2. Learned state from previous sessions.
	if not profile_manager.has_profile(LEARNED_STATE_NAME):
		return # first boot - nothing learned yet
	var loaded_templates = profile_manager.load_profile(LEARNED_STATE_NAME)
	var loaded_profiles = profile_manager.load_solver_profiles(LEARNED_STATE_NAME)
	var loaded_boss_profiles = profile_manager.load_boss_profiles(LEARNED_STATE_NAME)
	_merge_learned(loaded_templates, loaded_profiles, loaded_boss_profiles)

	# Telemetry rides in the same file (v1.3): the counter-doctrine now
	# remembers the player's habits across sessions, same as the
	# template weights always did. Then re-evaluate immediately so a
	# known pierce-leaner meets the jam doctrine from wave 1.
	var telemetry = profile_manager.load_telemetry(LEARNED_STATE_NAME)
	if not telemetry.is_empty():
		if telemetry.get("player_element_usage") is Dictionary:
			player_element_usage = telemetry["player_element_usage"]
		total_damage_taken = float(telemetry.get("total_damage_taken", 0.0))
		if telemetry.get("bot_element_usage") is Dictionary:
			bot_element_usage = telemetry["bot_element_usage"]
		total_bot_damage_dealt = float(telemetry.get("total_bot_damage_dealt", 0.0))
		if telemetry.get("player_kill_methods") is Dictionary:
			player_kill_methods = telemetry["player_kill_methods"]
		total_player_kills = int(telemetry.get("total_player_kills", 0))
		_apply_kill_method_counter_pressure()
		
	var round_state = profile_manager.load_telemetry(LEARNED_STATE_NAME + "_rounds")
	if not round_state.is_empty():
		current_round = int(round_state.get("current_round", 1))
		rivals_fought_this_round = int(round_state.get("rivals_fought_this_round", 0))
		active_rival_pool = round_state.get("active_rival_pool", [])
		consecutive_rival_losses = int(round_state.get("consecutive_rival_losses", 0))

	var captures = profile_manager.load_telemetry(LEARNED_STATE_NAME + "_captures")
	if not captures.is_empty():
		captured_loadouts = captures

	print("[DIRECTOR] Learned AI state restored: ", loaded_templates.size(), " templates, ", loaded_profiles.size(), " solver profiles, ", loaded_boss_profiles.size(), " boss profiles")

func save_learned_state():
	if profile_manager:
		profile_manager.save_profile(LEARNED_STATE_NAME, templates, solver_profiles, boss_profiles, {
			"player_element_usage": player_element_usage,
			"total_damage_taken": total_damage_taken,
			"bot_element_usage": bot_element_usage,
			"total_bot_damage_dealt": total_bot_damage_dealt,
			"player_kill_methods": player_kill_methods,
			"total_player_kills": total_player_kills,
		})
		profile_manager.save_telemetry(LEARNED_STATE_NAME + "_rounds", {
			"current_round": current_round,
			"rivals_fought_this_round": rivals_fought_this_round,
			"active_rival_pool": active_rival_pool,
			"consecutive_rival_losses": consecutive_rival_losses
		})
		profile_manager.save_telemetry(LEARNED_STATE_NAME + "_captures", captured_loadouts)

func export_learned_state_to_clipboard():
	if profile_manager:
		profile_manager.export_to_clipboard(templates, solver_profiles, boss_profiles)

func import_learned_state_from_clipboard() -> bool:
	if not profile_manager:
		return false
	var data = profile_manager.import_from_clipboard()
	if data.is_empty():
		return false
	_merge_imported(data.get("templates", []), data.get("solver_profiles", []), data.get("boss_profiles", []))
	save_learned_state()
	print("[DIRECTOR] Imported AI profile from clipboard.")
	return true

func register_wild_bot(bot: Node):
	if not wild_bots.has(bot):
		wild_bots.append(bot)
		bot.tree_exiting.connect(_on_wild_bot_died.bind(bot))
		
		# If we have enough wild bots, maybe try to assemble a squad?
		if wild_bots.size() >= 3:
			attempt_squad_assembly()

func _on_wild_bot_died(bot: Node):
	wild_bots.erase(bot)

func register_template(template: SquadTemplate):
	templates.append(template)

# Thin wrapper - external callers (Main.gd) keep calling director.
# maybe_introduce_experimental_template() unchanged; the actual mutate/
# crossover/random logic lives on TemplateEvolution now.
func maybe_introduce_experimental_template():
	template_evolution.maybe_introduce_experimental_template()

func attempt_squad_assembly() -> Squad:
	var selected_template = template_evolution.select_template_weighted()
	if not selected_template:
		return null
	return _assemble_squad(selected_template)

# How much of the current map is water (0.0-1.0) - duck-typed off Main.map
# since SquadDirector doesn't hold its own map reference. Feeds
# TemplateEvolution.select_template_weighted()'s biome bias: templates with
# no water-capable ("diver") role are otherwise just as likely to spawn on a
# map that's half lake as on dry land, and their non-diver members drown
# chasing the player across it (see Mech._check_drowning) - a wasted squad,
# not a real fight.
func get_map_water_fraction() -> float:
	var main = get_tree().current_scene
	if main and "map" in main and main.map and "water_fraction" in main.map:
		return main.map.water_fraction
	return 0.0

# Whether the current map crosses MapGenerator.MOSTLY_WATER_THRESHOLD - used
# by _spawn_bot_for_role to grant every non-diver role real water safety
# (is_amphibious) instead of just the "diver" role. Delegates to the map's
# own is_mostly_water() rather than re-comparing get_map_water_fraction()
# against a duplicated threshold constant here.
func is_map_mostly_water() -> bool:
	var main = get_tree().current_scene
	if main and "map" in main and main.map and main.map.has_method("is_mostly_water"):
		return main.map.is_mostly_water()
	return false

# Same assembly logic attempt_squad_assembly() uses, but for a caller-chosen
# template instead of a weighted-random pick - used by the debug menu's
# "spawn specific squad" tool so testers can deliberately request any
# registered template (including mutated/evolved experimental ones) rather
# than hoping the weighted roll picks it.
func spawn_specific_squad(template: SquadTemplate, spawn_pos: Vector2) -> Squad:
	if not template:
		return null
	var squad = _assemble_squad(template)
	if not squad:
		return null

	var map = null
	var player = null
	var main = get_tree().current_scene
	if main and "map" in main:
		map = main.map
	if main and "player" in main:
		player = main.player

	# Deliberately NOT connecting died -> _on_enemy_died here: that would
	# decrement Main.active_enemies for mechs that were never counted as
	# part of the current wave in the first place, which could send the
	# counter negative and trigger a bogus premature wave-clear. This is a
	# debug/testing tool, not part of wave accounting.
	for mech in squad.members:
		if not is_instance_valid(mech):
			continue
		var pos = spawn_pos + Vector2(randf_range(-100, 100), randf_range(-100, 100))
		mech.global_position = map.get_valid_spawn_position(pos) if map else pos
		if player:
			mech.target = player
	return squad

func _assemble_squad(selected_template: SquadTemplate) -> Squad:
	var squad = Squad.new()
	squad.setup(selected_template)
	var roles_needed = selected_template.required_roles.duplicate()
	
	# 1. Try to recruit wild bots
	var bots_to_recruit = []
	for bot in wild_bots:
		if not is_instance_valid(bot) or bot.is_queued_for_deletion():
			continue
		var role = bot.combat_role if "combat_role" in bot else "melee"
		if roles_needed.has(role) and roles_needed[role] > 0:
			bots_to_recruit.append(bot)
			roles_needed[role] -= 1
			if _all_roles_filled(roles_needed):
				break
				
	for bot in bots_to_recruit:
		wild_bots.erase(bot)
		for conn in bot.tree_exiting.get_connections():
			if conn.callable.get_method() == "_on_wild_bot_died":
				bot.tree_exiting.disconnect(conn.callable)
		squad.add_member(bot)
		
	# 2. Fallback Spawning (if Director decides to fill the gaps)
	if not _all_roles_filled(roles_needed):
		for role in roles_needed:
			for i in range(roles_needed[role]):
				var bot = _spawn_bot_for_role(role, selected_template.has_shields)
				squad.add_member(bot)

	# Every squad gets at least one scout, regardless of what the template
	# actually called for - per the user: scouts run the frontier-exploration
	# search pattern (see Mech.gd's _execute_scout_search) that pushes the
	# squad's shared explored-cell memory outward, so a squad with zero
	# scouts would have nobody actually mapping new ground while everyone
	# else just re-sweeps the same last-known-position datum.
	var has_scout = false
	for m in squad.members:
		if is_instance_valid(m) and m.get("combat_role") == "scout":
			has_scout = true
			break
	if not has_scout:
		var scout = _spawn_bot_for_role("scout", selected_template.has_shields)
		squad.add_member(scout)

	add_child(squad)
	active_squads.append(squad)
	squad.squad_defeated.connect(_on_squad_defeated)
	squad.request_linkup.connect(_on_squad_request_linkup)
	return squad

func _on_squad_request_linkup(squad: Squad):
	# Find another squad that is also broken and nearby
	for other in active_squads:
		if other != squad and other.active_members < other.initial_members:
			# If they are within 1000 units of each other (arbitrary link-up distance)
			if squad.get_center_position().distance_to(other.get_center_position()) < 1000.0:
				_merge_squads(squad, other)
				break

func _merge_squads(squad_a: Squad, squad_b: Squad):
	# Max merged squad size is 12
	var max_cap = 12
	
	# Move members from B to A
	for mech in squad_b.members.duplicate():
		if squad_a.active_members >= max_cap:
			break # Squad A is full!
			
		if is_instance_valid(mech) and not mech.is_queued_for_deletion():
			# Disconnect from B
			if mech.tree_exiting.is_connected(squad_b._on_member_died):
				mech.tree_exiting.disconnect(squad_b._on_member_died)
			if mech.has_signal("dealt_damage") and mech.dealt_damage.is_connected(squad_b._on_member_dealt_damage):
				mech.dealt_damage.disconnect(squad_b._on_member_dealt_damage)
				
			# Add to A
			squad_a.add_member(mech)
			squad_b.members.erase(mech)
			
	if squad_b.active_members <= 0:
		# Squad B is now empty, calculate its partial fitness and remove it
		squad_b._on_squad_wiped()
		print("[DIRECTOR] Squads Linked Up! Merged broken squads into one.")

		# A merged squad is a live experiment in squad composition - let it
		# become a candidate template sometimes, so the director can find
		# out empirically whether combined squads like this one are
		# actually more effective than what's already in rotation.
		if randf() < 0.4 and template_evolution._count_experimental() < TemplateEvolution.MAX_EXPERIMENTAL_TEMPLATES:
			var derived = SquadTemplateMutator.from_squad_composition(squad_a, "Fused")
			if derived:
				register_template(derived)
				print("[DIRECTOR] Merged composition registered as new experimental template: '", derived.template_name, "' roles=", derived.required_roles)

var player_element_usage: Dictionary = {}
var total_damage_taken: float = 0.0
var bot_element_usage: Dictionary = {}
var total_bot_damage_dealt: float = 0.0

# combat_role (String) -> {"fitness": float, "rarity": int, "components":
# Dictionary[BodySlot int -> serialized component]} - the actual hex-grid
# tile layout of the single highest-fitness enemy seen per role, not an
# abstract SolverProfile doctrine (Utility-SOC: "save the actual tile
# inventory/layout of the most effective individual enemies so I can see it
# in the war room"). Persisted alongside the rest of learned state - see
# save_learned_state/load_learned_state.
var captured_loadouts: Dictionary = {}

# Called from credit_bot_death() for EVERY non-player death, deliberately
# NOT gated behind the spawn_profile/solver_profiles checks that guard the
# rest of that function - every enemy is eligible to be captured, not just
# ones with an evolving profile. Replaces the stored entry for this role
# only if it's a new high score.
func _maybe_capture_loadout(mech: Node, fitness: float):
	if not ("combat_role" in mech) or not ("components" in mech):
		return
	var role = mech.combat_role
	if role == "":
		return
	var existing = captured_loadouts.get(role)
	if existing != null and float(existing.get("fitness", 0.0)) >= fitness:
		return

	var serialized_components: Dictionary = {}
	for slot in mech.components:
		serialized_components[slot] = SaveManager._serialize_component(mech.components[slot])

	captured_loadouts[role] = {
		"fitness": fitness,
		"rarity": int(mech.base_rarity) if "base_rarity" in mech else 0,
		"components": serialized_components,
	}
	print("[DIRECTOR] New high-fitness '", role, "' loadout captured (fitness %.1f)" % fitness)

func log_player_damage(amount: float, element: String):
	if not player_element_usage.has(element):
		player_element_usage[element] = 0.0
	player_element_usage[element] += amount
	total_damage_taken += amount

func log_bot_damage(amount: float, element: String):
	if not bot_element_usage.has(element):
		bot_element_usage[element] = 0.0
	bot_element_usage[element] += amount
	total_bot_damage_dealt += amount

# Jamming is not stealth - it's an announcement. The player's own active
# JammerField calls this (throttled, see Mech._tick_jammer_broadcast) to
# alert every live enemy on the map to its rough (laggy, off-true-position)
# location, regardless of squad or current sight state. Deliberately reaches
# every squad, not just the player's own (contrast _share_sight_with_squad's
# own-squad-only scoping) - each mech decides for itself whether to act on
# it (see Mech.receive_jammer_alert).
func broadcast_jammer_alert(approx_pos: Vector2):
	for squad in active_squads:
		if not is_instance_valid(squad):
			continue
		for m in squad.members:
			if is_instance_valid(m) and m.has_method("receive_jammer_alert"):
				m.receive_jammer_alert(approx_pos)

# --- Kill-method telemetry + over-reliance counter-pressure ----------------
# Damage telemetry (above) tracks what the player SPRAYS; this tracks what
# actually FINISHES enemies. Over-reliance on ANY synergy (RAW excepted -
# it's the baseline tool, not a crutch) gets answered on two fronts:
#   1. jammer/commander-bearing squads get sustained up-weighting
#   2. newly spawned Jammer Modules switch to SYNERGY-jam mode aimed at
#      the offending element (see _spawn_bot_for_role's ready callback)
# Pressure is gentle and continuous per kill, so diversifying lets the
# weights relax naturally through normal fitness learning. PIERCE-execution
# over-reliance gets a third, targeted front on top of the two above: any
# template with a "support" role slot (e.g. "Support Escort", registered in
# Main.gd) gets up-weighted harder specifically, since SupportMech's pierce-
# immunity aura (Mech._is_pierce_execution_exempt) is the actual counter to
# the execute build, not just a generic jammer/commander presence.
const KILL_OVERUSE_SHARE = 0.5
const KILL_OVERUSE_MIN_KILLS = 15

var player_kill_methods: Dictionary = {}
var total_player_kills: int = 0
var counter_jam_synergy: int = -1 # -1 = no over-reliance detected right now
var _counter_announced_element: String = ""

func log_player_kill(element: String):
	player_kill_methods[element] = player_kill_methods.get(element, 0) + 1
	total_player_kills += 1
	_apply_kill_method_counter_pressure()

func _apply_kill_method_counter_pressure():
	if total_player_kills < KILL_OVERUSE_MIN_KILLS:
		return

	var top_element := ""
	var top_share := 0.0
	for element in player_kill_methods:
		if element == "RAW":
			continue
		var share = float(player_kill_methods[element]) / float(total_player_kills)
		if share > top_share:
			top_share = share
			top_element = element

	if top_element == "" or top_share < KILL_OVERUSE_SHARE:
		counter_jam_synergy = -1
		_counter_announced_element = ""
		return

	counter_jam_synergy = _element_string_to_synergy(top_element)
	for t in templates:
		if t.required_roles.has("jammer") or t.required_roles.has("commander"):
			t.spawn_weight = min(250.0, t.spawn_weight * 1.06)
		# PIERCE cut-in-half executions specifically get answered with the
		# purpose-built counter (the Support role's execute-immunity aura),
		# up-weighted harder than the generic jammer bump above - per
		# FEATURE_ROADMAP.md §4: "over-reliance on the execute build gets
		# countered automatically" via templates containing this role.
		if top_element == "PIERCE" and t.required_roles.has("support"):
			t.spawn_weight = min(300.0, t.spawn_weight * 1.12)
	if _counter_announced_element != top_element:
		_counter_announced_element = top_element
		print("[DIRECTOR] Player %s-execution share %.0f%% - jammer counter-doctrine now targeting %s." % [top_element, top_share * 100.0, top_element])

# --- Director "tells" -------------------------------------------------------
# The learning loop is the game's most interesting system and it was
# invisible outside the War Room. These build short Frank-voiced lines from
# the REAL telemetry (never invented flavor): pre-wave intel when the
# counter-doctrine or resistance profiling is actually active, and an
# occasional post-wave debrief when the director just logged a lopsided
# kill pattern. Empty string = nothing worth saying (silence is the common
# case on purpose - a tell every wave would read as noise, not learning).

var _wave_start_kill_counts: Dictionary = {}
var _last_intel_line: String = ""

# --- Mortar counter-doctrine (playtest ruling: "more use of mortars means
# more use of cloaking and visual jammers") -------------------------------
# Indirect fire's weakness is target acquisition: cloaked ambushers give
# the telegraph nothing to aim at and vision jammers deny the aim point.
# Every reported mortar detonation past the grace threshold gently
# up-weights templates carrying those roles - same continuous-pressure
# pattern as the kill-method doctrine above.
const MORTAR_PRESSURE_MIN_SHOTS = 10

var player_mortar_shots: int = 0

func log_mortar_shot():
	player_mortar_shots += 1
	if player_mortar_shots < MORTAR_PRESSURE_MIN_SHOTS:
		return
	for t in templates:
		if t.required_roles.has("ambusher") or t.required_roles.has("jammer"):
			t.spawn_weight = min(250.0, t.spawn_weight * 1.03)

func note_wave_started():
	_wave_start_kill_counts = player_kill_methods.duplicate()

func get_intel_line(wave: int) -> String:
	if wave < 3:
		return "" # nothing learned yet - don't fake it
	var line = ""
	if counter_jam_synergy >= 0:
		var el = EnergyPacket.element_name(counter_jam_synergy).capitalize()
		line = "Heads up - the Director's fitted %s-jammers this round. Your favorite trick won't land clean." % el
	elif player_mortar_shots >= MORTAR_PRESSURE_MIN_SHOTS + 5:
		line = "All that artillery's been noticed - expect smoke, cloaks, and jammers on the table."
	elif total_damage_taken > 500.0:
		for element in player_element_usage:
			if player_element_usage[element] / total_damage_taken > 0.4:
				line = "It's been studying your %s matches - expect resistant plating out there." % str(element).capitalize()
				break
	if line == "" and wave % 4 == 0:
		var top_t = null
		for t in templates:
			if top_t == null or t.spawn_weight > top_t.spawn_weight:
				top_t = t
		if top_t and top_t.spawn_weight >= 150.0:
			line = "The Director keeps reaching for its '%s' lineup. Just saying." % top_t.template_name
	if line == _last_intel_line:
		return "" # don't repeat the same tell two waves running
	_last_intel_line = line
	return line

func get_debrief_line() -> String:
	var best_el = ""
	var best_delta = 0
	for element in player_kill_methods:
		var delta = player_kill_methods[element] - int(_wave_start_kill_counts.get(element, 0))
		if delta > best_delta:
			best_delta = delta
			best_el = element
	# Only when the pattern is genuinely lopsided, and not every time -
	# the debrief should feel like being noticed, not like a ticker.
	if best_el != "RAW" and best_el != "" and best_delta >= 8 and randf() < 0.4:
		return "It logged every one of those %d %s kills just now. It'll remember." % [best_delta, str(best_el).capitalize()]
	return ""

# Same counter pairing already used for shield bonus damage in
# Mech._apply_shield_mitigation (FIRE<->ICE, POISON<->VAMPIRIC,
# KINETIC<->LIGHTNING, VORTEX->KINETIC) - reused here rather than inventing
# a second, different counter wheel.
const SHIELD_COUNTER_WHEEL = {
	"FIRE": "ICE", "ICE": "FIRE",
	"POISON": "VAMPIRIC", "VAMPIRIC": "POISON",
	"KINETIC": "LIGHTNING", "LIGHTNING": "KINETIC",
	"VORTEX": "KINETIC",
}

# Playtest feedback: the counter-doctrine below used to apply
# deterministically to EVERY weapon/shield-feeding Microcore on EVERY bot -
# no wobble, no chance for the Director to stumble onto something that beats
# the "obvious" counter. This is the fraction of bots that actually commit to
# it; the rest keep whatever synergy the tile already rolled, giving genuine
# build variety a chance to compete with the deliberate counter-pick.
const COUNTER_BUILD_CHANCE = 0.7

# A bot whose weapon got deliberately Kinetic-countered otherwise can't
# leverage Kinetic's huge projectile-range bonus (Projectile.gd's
# KINETIC_RANGE_BONUS, up to +5600 units at full ratio) - it can't detect the
# player from anywhere near that far, so the range investment goes to waste.
# See Mech.kinetic_sight_bonus's own field comment.
const KINETIC_COUNTER_SIGHT_BONUS = 2000.0

# Thin wrapper over the canonical EnergyPacket.element_id() table, keeping
# this function's historical "RAW (or unknown) means -1 / not jammable"
# contract for its callers.
func _element_string_to_synergy(element: String) -> int:
	var id = EnergyPacket.element_id(element)
	return id if id > 0 else -1

# Thin wrappers - the actual reactive-baseline/role-scoped-selection/
# mutate/crossover/cull logic all lives on ProfileEvolution now (see that
# file's header comment). Kept here under the same names since
# _spawn_bot_for_role (below) and outside code call these on the director.
func build_reactive_profile(role: String = "") -> SolverProfile:
	return profile_evolution.build_reactive_profile(role)

func get_active_solver_profile(role: String = "") -> SolverProfile:
	return profile_evolution.get_active_solver_profile(role)

func maybe_introduce_experimental_profile():
	profile_evolution.maybe_introduce_experimental_profile()

# Thin wrappers - the actual seed/select/mutate/cull logic all lives on
# BossEvolution now (see that file's header comment). Kept here under the
# same names since Main.gd calls these on the director directly.
func get_active_boss_profile() -> BossProfile:
	return boss_evolution.get_active_boss_profile()

func maybe_introduce_experimental_boss_profile():
	boss_evolution.maybe_introduce_experimental_boss_profile()

# Called from Main._on_boss_died once the boss's own fitness is computed
# (see Mech.get_boss_fitness) - same trigger shape as _on_squad_defeated.
func _on_boss_defeated(profile: BossProfile, fitness_score: float):
	boss_evolution.on_boss_defeated(profile, fitness_score)

func _all_roles_filled(roles: Dictionary) -> bool:
	for count in roles.values():
		if count > 0:
			return false
	return true

# Roles that stay drown-vulnerable on mostly-water maps even though every
# other role gets is_amphibious there (see _spawn_bot_for_role below) -
# the user: keep water a real hazard for the standard rank-and-file (sniper's
# stationary/backline anyway; brawler is the plain melee rusher, i.e. the
# "grunt") rather than blanket-immunizing the whole roster.
const WATER_SAFETY_EXCLUDED_ROLES = ["sniper", "brawler"]

func _spawn_bot_for_role(role: String, has_shields: bool = false, p_rarity: int = 0) -> Node:
	var bot
	if role == "jammer":
		bot = load("res://scripts/entities/JammerMech.gd").new()
	elif role == "support":
		bot = load("res://scripts/entities/SupportMech.gd").new()
	else:
		bot = load("res://scripts/entities/Mech.gd").new()
		
	bot.combat_role = role
	bot.base_rarity = p_rarity
	if "spawn_profile" in bot:
		bot.spawn_profile = get_active_solver_profile(role)
		# Per-bot element jitter: ~35% of bots clone the profile with a
		# random favored element. Without this, early waves (before any
		# experimental profiles exist) are a monoculture of the reactive
		# baseline - every bot firing the same projectile type.
		if randf() < 0.35:
			var jittered = SolverProfile.new(bot.spawn_profile.profile_name + "*", randi() % EnergyPacket.SynergyType.size())
			jittered.role = role
			jittered.pierce_priority = bot.spawn_profile.pierce_priority
			jittered.amplify_priority = bot.spawn_profile.amplify_priority
			bot.spawn_profile = jittered
	if role == "diver":
		bot.is_amphibious = true
	elif is_map_mostly_water() and role not in WATER_SAFETY_EXCLUDED_ROLES:
		# Mostly-water levels give most roles real water safety, not just
		# "diver" - a squad chasing the player across a lake used to drown
		# on arrival regardless of composition (Mech._check_drowning /
		# _avoid_water_in_velocity only spare is_amphibious/jumpjet mechs).
		# sniper/brawler are deliberately excluded (WATER_SAFETY_EXCLUDED_
		# ROLES) so water stays a real hazard for the standard rank-and-file.
		# Tried routing this through build_loadout_for_role's tile solver
		# first (feed it a JumpjetTile like any other role tile) - didn't
		# hold up: JumpjetTile is an OUTPUT/terminal tile, and the solver's
		# generic "nothing matched, just place inventory[0]" fallback can
		# park an OUTPUT tile mid-tree, where it silently eats the packet
		# meant for whatever was downstream (an arm/leg link, the actual
		# Weapon Mount) instead of forwarding it - and even when placement
		# was harmless it usually never received a live packet at all.
		# is_amphibious is the same flag "diver" already relies on: it's
		# checked directly in code, not dependent on grid routing, so it
		# can't come up empty or corrupt an unrelated branch.
		bot.is_amphibious = true


	# Determine player's dominant shield to counter it
	var counter_element = -1
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		var p = players[0]
		if "dominant_shield_synergy" in p and p.dominant_shield_synergy != "":
			# dominant_shield_synergy is a stringified SynergyType id; pick
			# the attack element that beats that shield per the same
			# SHIELD_COUNTER_WHEEL Mech._apply_shield_mitigation uses.
			# LIGHTNING is the fallback for shields nothing specifically
			# beats (VORTEX/EXPLOSION/PIERCE/RAW) - it carries a flat 1.5x
			# vs all shields. (A previous hand-written table here used a
			# stale element numbering and countered the wrong shields.)
			var shield_name = EnergyPacket.element_name(int(p.dominant_shield_synergy))
			counter_element = EnergyPacket.element_id(SHIELD_COUNTER_WHEEL.get(shield_name, "LIGHTNING"))
	
	# Reactive AI: Apply Resistance Traits based on player history
	var player_favored_element = -1
	if total_damage_taken > 500.0:
		for element in player_element_usage.keys():
			var ratio = player_element_usage[element] / total_damage_taken
			if ratio > 0.4:
				# Player relies heavily on this element, spawn resistant mechs
				bot.elemental_resistances[element] = 0.5 # Take 50% damage
				# usage keys are element NAME strings (see log_player_damage) -
				# int("FIRE") was silently producing 0/RAW here, and the old
				# numeric-string comparisons below never matched anything.
				player_favored_element = EnergyPacket.element_id(element)

				# Special visual/gameplay traits
				if element == "LIGHTNING":
					bot.modulate = Color(0.8, 0.8, 0.5)
				elif element == "VAMPIRIC":
					bot.modulate = Color(0.9, 0.6, 0.6)
					
	# Wobble: roll once per bot rather than committing the counter-doctrine on
	# every qualifying tile deterministically - see COUNTER_BUILD_CHANCE.
	var commit_weapon_counter = randf() < COUNTER_BUILD_CHANCE
	var commit_shield_counter = randf() < COUNTER_BUILD_CHANCE

	# Apply generated synergies to bot's components
	bot.ready.connect(func():
		var counter_fitted = false
		for comp in bot.components.values():
			for coord in comp.hex_grid.grid.keys():
				var tile = comp.hex_grid.grid[coord]
				# Over-reliance counter (see _apply_kill_method_counter_pressure):
				# aim any jammer module at the synergy the player leans on
				# for kills, switching it to SYNERGY-jam mode.
				if counter_jam_synergy >= 0 and tile.tile_type == "Jammer Module":
					if "jam_mode" in tile:
						tile.jam_mode = 1
					if "target_synergy" in tile:
						tile.target_synergy = counter_jam_synergy
						counter_fitted = true
				if tile.tile_type == "Microcore":
					# If this core feeds a weapon, set it to the counter_element
					# If it feeds a shield, set it to the player_favored_element
					var is_weapon_feeder = false
					var is_shield_feeder = false
					for d in tile.active_faces:
						var n = HexCoord.new(coord.x, coord.y).neighbor(d)
						if comp.hex_grid.has_tile(n):
							var neighbor = comp.hex_grid.get_tile(n)
							if neighbor.tile_type == "Weapon Mount": is_weapon_feeder = true
							elif neighbor.tile_type == "Shield Generator": is_shield_feeder = true

					for d in tile.active_faces:
						if is_weapon_feeder and counter_element != -1 and commit_weapon_counter:
							tile.set_face_output(d, counter_element)
							if counter_element == EnergyPacket.SynergyType.KINETIC:
								bot.kinetic_sight_bonus = KINETIC_COUNTER_SIGHT_BONUS
						if is_shield_feeder and player_favored_element != -1 and commit_shield_counter:
							tile.set_face_output(d, player_favored_element)
		bot.is_grid_dirty = true
		# Director tell: a bot that was specifically kitted against the
		# player's kill pattern announces it - the counter-doctrine should
		# be visible on the battlefield, not just in the War Room.
		if counter_fitted and bot.has_method("_show_floating_text"):
			bot._show_floating_text("COUNTER-FIT", Color(0.8, 0.45, 1.0))
	)
	
	var wave_multiplier = 1.0
	# NOTE: was get_parent() - that broke when SquadDirector moved from being
	# a direct child of Main to a child of Main.world (the pixel-viewport
	# game world, see Main.gd's _setup_pixel_viewport()). current_scene
	# still correctly resolves to Main regardless of how deep world nesting
	# goes, so it's the more robust reference here.
	var difficulty = SaveManager.difficulty
	var main = get_tree().current_scene
	if main and "current_wave" in main:
		# Difficulty-driven growth with the post-knee linear tail - see
		# SaveManager.wave_hp_multiplier for the curve and its rationale.
		wave_multiplier = SaveManager.wave_hp_multiplier(difficulty, main.current_wave)

	# "Why would you do this to yourself?": enemies are near-peers with the
	# player's ACTUAL build power, always - clown-shoes full-Mythic builds
	# included. Also applies stat pressure on Hard, at a gentler exponent.
	if difficulty >= 2:
		var peer_exp = 0.85 if difficulty >= 3 else 0.5
		wave_multiplier *= max(1.0, pow(_estimate_player_power() / NEAR_PEER_BASELINE, peer_exp))

	# Gear parity: on Hard the bots' component rarity creeps up with waves;
	# on near-peer they simply build from the player's dominant tier.
	if difficulty == 2 and main and "current_wave" in main:
		bot.base_rarity = max(bot.base_rarity, min(HexTile.Rarity.RARE, int(main.current_wave / 8)))
	elif difficulty >= 3:
		bot.base_rarity = max(bot.base_rarity, _player_dominant_rarity())

	# Mythic seeding, independent of the difficulty-gated gear-parity above
	# (which on its own never reaches past RARE, or only mirrors the
	# player's own tier - neither ever introduces a FIRST Mythic on its
	# own). Per the user: as waves climb, the chance any given enemy is
	# built entirely at Mythic tier should steadily increase, tuned so a
	# player realistically sees their first Mythic-tier enemy (and, via
	# LootManager's matching wave-scaled drop chance, an actual Mythic
	# drop) by around wave/level 30 - not guaranteed, just increasingly
	# likely as more enemies get rolled against the chance.
	if main and "current_wave" in main:
		var mythic_seed_chance = clamp((float(main.current_wave) - 5.0) / 150.0, 0.0, 0.2)
		if randf() < mythic_seed_chance:
			bot.base_rarity = HexTile.Rarity.MYTHIC
		
	var base_hp = 100.0
	match role:
		"jammer":
			base_hp = 300.0 # High HP, moves slow, stays near backline
			bot.base_speed = 60.0
			bot.engagement_distance = 600.0
		"sniper":
			base_hp = 60.0
			bot.base_speed = 100.0
			bot.engagement_distance = 450.0
			bot.fire_rate = 1.5
		"brawler":
			base_hp = 150.0
			bot.base_speed = 130.0
			bot.engagement_distance = 100.0
		"scout":
			base_hp = 80.0
			bot.base_speed = 220.0
			bot.engagement_distance = 250.0
		"diver":
			# Amphibious scout-analogue - genuinely at home over water
			# (is_amphibious set above, gets a real speed bonus there
			# instead of merely surviving it - see Mech.update_status_effects).
			# Squishy like a scout, but leans into flanking through terrain
			# other roles have to route around entirely.
			base_hp = 85.0
			bot.base_speed = 200.0
			bot.engagement_distance = 260.0
		"ambusher":
			base_hp = 90.0
			bot.base_speed = 180.0
			bot.engagement_distance = 180.0
			bot.fire_rate = 0.15
		"flamethrower":
			base_hp = 120.0
			bot.base_speed = 140.0
			bot.engagement_distance = 150.0
		"support":
			# Raised from 130/110/500 - this role absorbed PiercingJammerMech's
			# job too (see SupportMech.gd), including its execute-immunity
			# aura, which only protects a squad if the unit survives long
			# enough to matter and is worth focusing down once its healing/
			# jamming/immunity are noticed.
			base_hp = 300.0
			bot.base_speed = 70.0
			bot.engagement_distance = 550.0
		"commander":
			# The squad's spine: slow, tough, deep backline, and its Command
			# Suite backpack stacks up to 5 support modules (heal/jammer/
			# shield/cloak - see ComponentEquipment.create_command_backpack).
			base_hp = 350.0
			bot.base_speed = 70.0
			bot.engagement_distance = 600.0

	bot.max_hp = base_hp * wave_multiplier
	bot.hp = bot.max_hp

	# Near-peer bots always deploy shielded - the player at that tier
	# certainly is, and "near peers, always" means matching the basics.
	if has_shields or role == "commander" or difficulty >= 3:
		bot.max_shield_hp = (base_hp * 0.5) * wave_multiplier
		bot.shield_hp = bot.max_shield_hp
		
	add_child(bot)

	# One-time visibility sync for the Blind mechanic (see Main.
	# _update_player_blind_state): that check only re-walks the "enemy"
	# group on an actual blind-state TRANSITION now (not every frame), so a
	# bot spawned while the player is ALREADY blind needs this explicit
	# correction rather than waiting on a transition that may not come for
	# a while.
	var main_ref = get_tree().current_scene
	if main_ref and "player_is_blind" in main_ref:
		bot.visible = not main_ref.player_is_blind

	# Companion Drone(s) - Commanders always come with one (see
	# ComponentEquipment.create_command_backpack), other roles have a modest
	# independent chance (see Mech._create_role_backpack). Fire-and-forget:
	# unlike the player's own drones (Main.gd's respawn-on-cooldown wrapper
	# around this same helper), an enemy mech never gets revived, so there's
	# nothing to respawn - the drone just dies alongside/after its owner via
	# Drone._physics_process's existing owner-validity check.
	DroneBayTileScript.spawn_drones_for(bot, self)

	return bot

# --- Near-peer scaling (difficulty 3, partial on 2) -------------------------
# A single scalar estimate of the player's build power: equipped tile
# values on the same rarity ladder scrap uses, plus tile levels, frame
# rarity, and infusion. Deliberately coarse - it only needs to move in the
# same direction the player's power does.
const NEAR_PEER_BASELINE = 700.0 # rough score of a fresh starter build
const RARITY_POWER_VALUES = [10.0, 25.0, 75.0, 250.0, 1000.0]

func _estimate_player_power() -> float:
	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return NEAR_PEER_BASELINE
	return _estimate_mech_power(players[0])

# Generalized version of the scoring above - works on ANY mech reference
# (duck-typed via "components", same as the player-only version used to be),
# so Rival Challenges (see Main._spawn_rival) can score a freshly-built
# rival mech against the player using the exact same yardstick, not a
# parallel/divergent formula that could quietly drift out of sync with it.
func _estimate_mech_power(mech) -> float:
	if not mech or not "components" in mech:
		return NEAR_PEER_BASELINE
	var score = 0.0
	for comp in mech.components.values():
		score += 20.0 * (1 + comp.rarity) # the frame itself
		score += comp.infusion_level * 50.0
		for tile in comp.hex_grid.get_all_tiles():
			score += RARITY_POWER_VALUES[clamp(tile.rarity, 0, 4)] * (1.0 + 0.1 * (tile.level - 1))
		# Chip/infusion stat modifiers are real power: a component sitting
		# at +50% dmg_mult must read stronger to near-peer scaling, or the
		# exact clown-shoes build WWYDTTY exists for gets underestimated.
		var mods = comp.get("stat_modifiers")
		if mods is Dictionary:
			for k in mods:
				score += 400.0 * max(0.0, float(mods[k]) - 1.0)
	return max(score, 1.0)

# The player's median equipped tile rarity - what tier they're "really"
# playing at, robust against one lucky Mythic in a sea of Commons.
func _player_dominant_rarity() -> int:
	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return 0
	var p = players[0]
	if not "components" in p:
		return 0
	var rarities: Array = []
	for comp in p.components.values():
		for tile in comp.hex_grid.get_all_tiles():
			rarities.append(tile.rarity)
	if rarities.is_empty():
		return 0
	rarities.sort()
	return int(rarities[rarities.size() / 2])

func spawn_squad() -> Squad:
	return attempt_squad_assembly()

# Called from Mech.die() for every non-player mech, regardless of whether
# its squad ultimately wipes or wins - credits THAT bot's own spawn_profile
# with ITS OWN individual performance (see Mech.get_individual_fitness),
# not a shared squad-wide score. Previously all solver-profile crediting
# happened here in _on_squad_defeated using squad.used_profiles + the
# squad's aggregate fitness, which had two problems: every bot in a squad
# got credited identically regardless of its own actual contribution, and
# nothing was ever credited at all unless the WHOLE squad wiped - a squad
# that won a fight with survivors taught the director nothing.
func credit_bot_death(mech: Node):
	var fitness = mech.get_individual_fitness() if mech.has_method("get_individual_fitness") else 0.0
	# Loadout capture is deliberately NOT gated behind the spawn_profile
	# checks below - every enemy is eligible, not just ones with an
	# evolving profile (see _maybe_capture_loadout's own comment).
	_maybe_capture_loadout(mech, fitness)

	if not ("spawn_profile" in mech) or not mech.spawn_profile:
		return
	# Only credit profiles actually tracked in the evolving pool - the
	# always-fresh reactive baseline and per-bot jittered clones (see
	# _spawn_bot_for_role) are throwaway instances never added to
	# solver_profiles, so crediting them would just vanish with the bot.
	if not solver_profiles.has(mech.spawn_profile):
		return
	mech.spawn_profile.update_fitness(fitness)
	profile_evolution.evaluate_experimental_profile(mech.spawn_profile)

func _on_squad_defeated(squad: Squad, fitness_score: float):
	active_squads.erase(squad)

	var t = squad.template
	if t:
		t.update_fitness(fitness_score)
		# Using Godot's print for headless testing feedback
		print("[DIRECTOR] Squad Defeated! Template: '", t.template_name, "'")
		print("           Fitness: ", "%.1f" % fitness_score, " | New Weight: ", "%.1f" % t.spawn_weight)

		# Cull/graduate experimental templates once they've had a fair trial -
		# see TemplateEvolution.evaluate_experimental_template.
		template_evolution.evaluate_experimental_template(t)

	# Persist post-evaluation state (weights, fitness, culls, graduations,
	# profile credit) - this is what makes the evolutionary system actually
	# accumulate across sessions instead of relearning from scratch. Runs
	# even when squad.template is null, because the solver-profile credit
	# above still changed state.
	save_learned_state()
