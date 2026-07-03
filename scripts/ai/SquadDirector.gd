class_name SquadDirector
extends Node

const SquadTemplateMutator = preload("res://scripts/ai/SquadTemplateMutator.gd")
const SolverProfile = preload("res://scripts/ai/SolverProfile.gd")

# --- AI squad evolution tuning ---
# How many "on trial" experimental templates can exist at once. Without a
# cap, mutation + merge-derived templates would accumulate forever (the
# "ten million failed squad types" problem).
const MAX_EXPERIMENTAL_TEMPLATES = 5
# An experimental template needs at least this many completed deployments
# before it's judged - one bad squad wipe shouldn't be a death sentence.
const MIN_TRIALS_BEFORE_CULL = 3
# Average fitness below this after MIN_TRIALS_BEFORE_CULL gets the template
# removed. 100 is "expected average" per SquadTemplate's own convention
# (see SquadTemplate.update_fitness), so this is "meaningfully worse than a
# typical squad", not "worse than the best squad".
const CULL_FITNESS_THRESHOLD = 60.0
# Average fitness above this promotes the template out of experimental
# status entirely - it's earned a permanent spot in the rotation.
const GRADUATE_FITNESS_THRESHOLD = 110.0

# --- Solver profile evolution tuning (mirrors the squad-template constants
# above - same shape, applied to AutoEquipSolver loadout profiles instead
# of squad compositions) ---
const MAX_EXPERIMENTAL_PROFILES = 5
const MIN_PROFILE_TRIALS_BEFORE_CULL = 3
const PROFILE_CULL_THRESHOLD = 60.0
const PROFILE_GRADUATE_THRESHOLD = 110.0

var solver_profiles: Array[SolverProfile] = []

var templates: Array[SquadTemplate] = []
var active_squads: Array[Squad] = []
var wild_bots: Array[Node] = []

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

func _count_experimental() -> int:
	var n = 0
	for t in templates:
		if t.is_experimental:
			n += 1
	return n

# Introduces one new experimental template, either by mutating an existing
# one or generating a fresh random composition - as long as there's room
# under MAX_EXPERIMENTAL_TEMPLATES. Call this periodically (Main.gd calls it
# every few waves) rather than on every squad spawn, so trials aren't
# constantly getting reset before they've proven anything.
func maybe_introduce_experimental_template():
	if templates.is_empty() or _count_experimental() >= MAX_EXPERIMENTAL_TEMPLATES:
		return

	var new_template: SquadTemplate = null
	if randf() < 0.5:
		var candidates = templates.filter(func(t): return not t.is_experimental)
		if candidates.is_empty():
			candidates = templates
		var parent = candidates[randi() % candidates.size()]
		new_template = SquadTemplateMutator.mutate(parent)
	else:
		new_template = SquadTemplateMutator.random_template()

	if new_template:
		register_template(new_template)
		print("[DIRECTOR] New experimental template on trial: '", new_template.template_name, "' roles=", new_template.required_roles)

func select_template_weighted() -> SquadTemplate:
	if templates.is_empty():
		return null
		
	# Weighted random selection
	var total_weight = 0.0
	for t in templates:
		total_weight += t.spawn_weight
		
	var roll = randf() * total_weight
	var current_weight = 0.0
	var selected_template: SquadTemplate = templates[0]
	
	for t in templates:
		current_weight += t.spawn_weight
		if roll <= current_weight:
			selected_template = t
			break
			
	return selected_template

func attempt_squad_assembly() -> Squad:
	var selected_template = select_template_weighted()
	if not selected_template:
		return null
	return _assemble_squad(selected_template)

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
		if randf() < 0.4 and _count_experimental() < MAX_EXPERIMENTAL_TEMPLATES:
			var derived = SquadTemplateMutator.from_squad_composition(squad_a, "Fused")
			if derived:
				register_template(derived)
				print("[DIRECTOR] Merged composition registered as new experimental template: '", derived.template_name, "' roles=", derived.required_roles)

var player_element_usage: Dictionary = {}
var total_damage_taken: float = 0.0

func log_player_damage(amount: float, element: String):
	if not player_element_usage.has(element):
		player_element_usage[element] = 0.0
	player_element_usage[element] += amount
	total_damage_taken += amount

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

func _element_string_to_synergy(element: String) -> int:
	match element:
		"FIRE": return EnergyPacket.SynergyType.FIRE
		"ICE": return EnergyPacket.SynergyType.ICE
		"LIGHTNING": return EnergyPacket.SynergyType.LIGHTNING
		"VORTEX": return EnergyPacket.SynergyType.VORTEX
		"POISON": return EnergyPacket.SynergyType.POISON
		"EXPLOSION": return EnergyPacket.SynergyType.EXPLOSION
		"KINETIC": return EnergyPacket.SynergyType.KINETIC
		"PIERCE": return EnergyPacket.SynergyType.PIERCE
		"VAMPIRIC": return EnergyPacket.SynergyType.VAMPIRIC
		_: return -1

# Builds a SolverProfile automatically from what the director has observed
# about the player: which element they lean on (so enemies build toward the
# element that counters the player's shield) and how much shield/HP they're
# packing (so a tanky player build gets answered with Pierce instead of
# just more raw damage). This is the "counters should start proportional to
# the player" default - get_active_solver_profile()/maybe_introduce_experimental_profile()
# below are what make it "evolvy" over time rather than static.
func build_reactive_profile() -> SolverProfile:
	var profile = SolverProfile.new("Reactive")

	if total_damage_taken > 200.0:
		var top_element = ""
		var top_ratio = 0.0
		for element in player_element_usage.keys():
			var ratio = player_element_usage[element] / total_damage_taken
			if ratio > top_ratio:
				top_ratio = ratio
				top_element = element

		if top_element != "" and SHIELD_COUNTER_WHEEL.has(top_element):
			profile.favored_synergy = _element_string_to_synergy(SHIELD_COUNTER_WHEEL[top_element])

	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		var p = players[0]
		var tankiness = 0.0
		if "max_shield_hp" in p:
			tankiness += p.max_shield_hp
		if "max_hp" in p:
			tankiness += max(0.0, p.max_hp - 100.0) # 100 is the baseline starting max_hp
		if tankiness > 100.0:
			profile.pierce_priority = clamp(0.3 + tankiness / 600.0, 0.3, 0.9)

	return profile

# Weighted pick between an always-fresh reactive baseline (recomputed from
# current telemetry every call, so it never goes stale) and whatever
# experimental profiles have been mutated in. This is what "evolvy" means
# for the solver: over time, mutated profiles that outperform the plain
# reactive baseline get selected more often (see update below), and
# underperformers get culled the same way experimental squad templates are.
func get_active_solver_profile() -> SolverProfile:
	var reactive = build_reactive_profile()
	reactive.spawn_weight = 100.0

	if solver_profiles.is_empty():
		return reactive

	var candidates: Array = solver_profiles.duplicate()
	candidates.append(reactive)

	var total_weight = 0.0
	for p in candidates: total_weight += p.spawn_weight
	var roll = randf() * total_weight
	var acc = 0.0
	for p in candidates:
		acc += p.spawn_weight
		if roll <= acc:
			return p
	return reactive

func _count_experimental_profiles() -> int:
	var n = 0
	for p in solver_profiles:
		if p.is_experimental:
			n += 1
	return n

func maybe_introduce_experimental_profile():
	if _count_experimental_profiles() >= MAX_EXPERIMENTAL_PROFILES:
		return
	var parent = solver_profiles[randi() % solver_profiles.size()] if not solver_profiles.is_empty() else build_reactive_profile()
	var mutant = _mutate_profile(parent)
	solver_profiles.append(mutant)
	print("[DIRECTOR] New experimental solver profile on trial: '", mutant.profile_name, "' favored=", mutant.favored_synergy, " pierce=", "%.2f" % mutant.pierce_priority)

func _mutate_profile(parent: SolverProfile) -> SolverProfile:
	var mutant = SolverProfile.new(parent.profile_name + " Mk." + str(100 + randi() % 900), parent.favored_synergy)
	mutant.pierce_priority = clamp(parent.pierce_priority + randf_range(-0.3, 0.3), 0.0, 1.0)
	mutant.amplify_priority = clamp(parent.amplify_priority + randf_range(-0.3, 0.3), 0.1, 2.0)
	if randf() < 0.3:
		mutant.favored_synergy = randi() % EnergyPacket.SynergyType.size()
	mutant.is_experimental = true
	mutant.base_spawn_weight = 60.0
	mutant.spawn_weight = 60.0
	return mutant

# Cull/graduate experimental profiles - called from _on_squad_defeated,
# same trigger point as the squad-template evolution.
func _evaluate_experimental_profile(p: SolverProfile):
	if not p.is_experimental or p.times_used < MIN_PROFILE_TRIALS_BEFORE_CULL:
		return
	var avg = p.get_average_fitness()
	if avg < PROFILE_CULL_THRESHOLD:
		solver_profiles.erase(p)
		print("[DIRECTOR] Experimental solver profile '", p.profile_name, "' culled (avg fitness %.1f < %.1f)" % [avg, PROFILE_CULL_THRESHOLD])
	elif avg >= PROFILE_GRADUATE_THRESHOLD:
		p.is_experimental = false
		print("[DIRECTOR] Experimental solver profile '", p.profile_name, "' graduated to permanent rotation! (avg fitness %.1f)" % avg)

func _all_roles_filled(roles: Dictionary) -> bool:
	for count in roles.values():
		if count > 0:
			return false
	return true

func _spawn_bot_for_role(role: String, has_shields: bool = false, p_rarity: int = 0) -> Node:
	var bot
	if role == "jammer":
		bot = load("res://scripts/entities/JammerMech.gd").new()
	else:
		bot = load("res://scripts/entities/Mech.gd").new()
		
	bot.combat_role = role
	bot.base_rarity = p_rarity
	if "spawn_profile" in bot:
		bot.spawn_profile = get_active_solver_profile()


	# Determine player's dominant shield to counter it
	var counter_element = -1
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		var p = players[0]
		if "dominant_shield_synergy" in p and p.dominant_shield_synergy != "":
			var syn_id = int(p.dominant_shield_synergy)
			match syn_id:
				1: counter_element = 4 # Kinetic gets countered by Lightning
				2: counter_element = 3 # Fire gets countered by Poison
				3: counter_element = 2 # Poison gets countered by Fire
				4: counter_element = 1 # Lightning gets countered by Kinetic
				5: counter_element = 6 # Vampiric gets countered by Vortex
				6: counter_element = 5 # Vortex gets countered by Vampiric
	
	# Reactive AI: Apply Resistance Traits based on player history
	var player_favored_element = -1
	if total_damage_taken > 500.0:
		for element in player_element_usage.keys():
			var ratio = player_element_usage[element] / total_damage_taken
			if ratio > 0.4:
				# Player relies heavily on this element, spawn resistant mechs
				bot.elemental_resistances[element] = 0.5 # Take 50% damage
				player_favored_element = int(element)
				
				# Special visual/gameplay traits
				if element == "4": # LIGHTNING
					bot.modulate = Color(0.8, 0.8, 0.5)
				elif element == "5": # VAMPIRIC
					bot.modulate = Color(0.9, 0.6, 0.6)
					
	# Apply generated synergies to bot's components
	bot.ready.connect(func():
		for comp in bot.components.values():
			for coord in comp.hex_grid.grid.keys():
				var tile = comp.hex_grid.grid[coord]
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
						if is_weapon_feeder and counter_element != -1:
							tile.set_face_output(d, counter_element)
						if is_shield_feeder and player_favored_element != -1:
							tile.set_face_output(d, player_favored_element)
		bot.is_grid_dirty = true
	)
	
	var wave_multiplier = 1.0
	# NOTE: was get_parent() - that broke when SquadDirector moved from being
	# a direct child of Main to a child of Main.world (the pixel-viewport
	# game world, see Main.gd's _setup_pixel_viewport()). current_scene
	# still correctly resolves to Main regardless of how deep world nesting
	# goes, so it's the more robust reference here.
	var main = get_tree().current_scene
	if main and "current_wave" in main:
		wave_multiplier = pow(1.10, max(0, main.current_wave - 1))
		
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
			base_hp = 130.0 # Squishier than a brawler - it's meant to hang back
			bot.base_speed = 110.0
			bot.engagement_distance = 500.0

	bot.max_hp = base_hp * wave_multiplier
	bot.hp = bot.max_hp
	
	if has_shields:
		bot.max_shield_hp = (base_hp * 0.5) * wave_multiplier
		bot.shield_hp = bot.max_shield_hp
		
	add_child(bot)
	return bot

func spawn_squad() -> Squad:
	return attempt_squad_assembly()

func _on_squad_defeated(squad: Squad, fitness_score: float):
	active_squads.erase(squad)

	# Credit every SolverProfile used to build this squad's loadouts with
	# the same fitness score the squad template gets - a profile that keeps
	# ending up in high-fitness squads is a good profile, same logic as
	# template evolution, just scoped to loadout quality instead of
	# squad composition.
	for p in squad.used_profiles:
		p.update_fitness(fitness_score)
		_evaluate_experimental_profile(p)

	var t = squad.template
	if not t:
		return
	t.update_fitness(fitness_score)
	# Using Godot's print for headless testing feedback
	print("[DIRECTOR] Squad Defeated! Template: '", t.template_name, "'")
	print("           Fitness: ", "%.1f" % fitness_score, " | New Weight: ", "%.1f" % t.spawn_weight)

	# Cull/graduate experimental templates once they've had a fair trial.
	# This is what keeps mutation + merge-derived templates from piling up
	# forever - underperformers get removed, standouts become permanent.
	if t.is_experimental and t.times_deployed >= MIN_TRIALS_BEFORE_CULL:
		var avg = t.get_average_fitness()
		if avg < CULL_FITNESS_THRESHOLD:
			templates.erase(t)
			print("[DIRECTOR] Experimental template '", t.template_name, "' culled (avg fitness %.1f < %.1f)" % [avg, CULL_FITNESS_THRESHOLD])
		elif avg >= GRADUATE_FITNESS_THRESHOLD:
			t.is_experimental = false
			print("[DIRECTOR] Experimental template '", t.template_name, "' graduated to permanent rotation! (avg fitness %.1f)" % avg)
