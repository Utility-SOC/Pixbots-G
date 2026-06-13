class_name SquadDirector
extends Node

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
		
	var squad = Squad.new()
	squad.setup(selected_template)
	var roles_needed = selected_template.required_roles.duplicate()
	
	# 1. Try to recruit wild bots
	var bots_to_recruit = []
	for bot in wild_bots:
		var role = bot.combat_role if "combat_role" in bot else "melee"
		if roles_needed.has(role) and roles_needed[role] > 0:
			bots_to_recruit.append(bot)
			roles_needed[role] -= 1
			if _all_roles_filled(roles_needed):
				break
				
	for bot in bots_to_recruit:
		wild_bots.erase(bot)
		bot.tree_exiting.disconnect(_on_wild_bot_died)
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
	# Max merged squad size is 4
	var max_cap = 4
	
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

var player_element_usage: Dictionary = {}
var total_damage_taken: float = 0.0

func log_player_damage(amount: float, element: String):
	if not player_element_usage.has(element):
		player_element_usage[element] = 0.0
	player_element_usage[element] += amount
	total_damage_taken += amount

func _all_roles_filled(roles: Dictionary) -> bool:
	for count in roles.values():
		if count > 0:
			return false
	return true

func _spawn_bot_for_role(role: String, has_shields: bool = false, p_rarity: int = 0) -> Node:
	var bot = load("res://scripts/entities/Mech.gd").new()
	bot.combat_role = role
	bot.base_rarity = p_rarity
	
	# Reactive AI: Apply Resistance Traits based on player history
	if total_damage_taken > 500.0:
		for element in player_element_usage.keys():
			var ratio = player_element_usage[element] / total_damage_taken
			if ratio > 0.4:
				# Player relies heavily on this element, spawn resistant mechs
				bot.elemental_resistances[element] = 0.5 # Take 50% damage
				
				# Special visual/gameplay traits
				if element == "LIGHTNING":
					bot.modulate = Color(0.8, 0.8, 0.5) # "Grounded" yellowish tint
				elif element == "VAMPIRIC":
					# Anti-Heal dampener visual
					bot.modulate = Color(0.9, 0.6, 0.6)
	
	var wave_multiplier = 1.0
	var main = get_parent()
	if main and "current_wave" in main:
		wave_multiplier = pow(1.10, max(0, main.current_wave - 1))
		
	var base_hp = 100.0
	match role:
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
	squad.template.update_fitness(fitness_score)
	# Using Godot's print for headless testing feedback
	print("[DIRECTOR] Squad Defeated! Template: '", squad.template.template_name, "'")
	print("           Fitness: ", "%.1f" % fitness_score, " | New Weight: ", "%.1f" % squad.template.spawn_weight)
