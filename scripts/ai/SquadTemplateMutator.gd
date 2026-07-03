class_name SquadTemplateMutator
extends RefCounted

# Procedural squad-composition generation for SquadDirector. Three sources
# of new templates:
#   mutate()               - nudge an existing template (role counts, role
#                             swaps, shield toggle)
#   random_template()      - a fresh random composition, for variety the
#                             mutator alone wouldn't reach
#   from_squad_composition - derive a template from a squad that just proved
#                             itself via a merge-linkup in combat
# All three come back flagged is_experimental so SquadDirector can track and
# cull them if they don't pull their weight (see SquadDirector.gd).

const ALL_ROLES = ["sniper", "brawler", "flamethrower", "ambusher", "scout", "jammer", "support"]

static func mutate(parent: SquadTemplate) -> SquadTemplate:
	var roles: Dictionary = parent.required_roles.duplicate()
	if roles.is_empty():
		roles[ALL_ROLES[randi() % ALL_ROLES.size()]] = 1

	var op = randi() % 4
	match op:
		0: # Bump a random role's count (capped so squads don't balloon)
			var keys = roles.keys()
			var k = keys[randi() % keys.size()]
			roles[k] = min(4, roles[k] + 1)
		1: # Drop a random role's count, removing it if it hits 0 (never empty the whole squad)
			if roles.size() > 1:
				var keys = roles.keys()
				var k = keys[randi() % keys.size()]
				roles[k] -= 1
				if roles[k] <= 0:
					roles.erase(k)
		2: # Swap a role for a different one, keeping its count
			var keys = roles.keys()
			var k = keys[randi() % keys.size()]
			var count = roles[k]
			roles.erase(k)
			var new_role = ALL_ROLES[randi() % ALL_ROLES.size()]
			roles[new_role] = roles.get(new_role, 0) + count
		3: # Add a brand new role into the mix
			var new_role = ALL_ROLES[randi() % ALL_ROLES.size()]
			roles[new_role] = roles.get(new_role, 0) + 1

	var mutant = SquadTemplate.new(parent.template_name + " Mk." + str(100 + randi() % 900), roles)
	mutant.has_shields = parent.has_shields if randf() < 0.7 else not parent.has_shields
	mutant.base_spawn_weight = 60.0 # experimental templates start modest, not at the 100 baseline
	mutant.spawn_weight = 60.0
	mutant.is_experimental = true
	return mutant

static func random_template() -> SquadTemplate:
	var roles: Dictionary = {}
	var role_count = 1 + randi() % 3
	for i in range(role_count):
		var r = ALL_ROLES[randi() % ALL_ROLES.size()]
		roles[r] = roles.get(r, 0) + 1 + (randi() % 2)

	var template = SquadTemplate.new("Experimental " + str(1000 + randi() % 9000), roles)
	template.has_shields = randf() < 0.3
	template.base_spawn_weight = 60.0
	template.spawn_weight = 60.0
	template.is_experimental = true
	return template

# `squad` here is the SURVIVING squad after a merge (squad_a in
# SquadDirector._merge_squads) - tallies whichever roles are actually alive
# in it right now and turns that into a candidate template, so the director
# can find out empirically whether that combined composition is worth
# spawning on purpose next time.
static func from_squad_composition(squad: Squad, name_hint: String = "Fused") -> SquadTemplate:
	var roles: Dictionary = {}
	for m in squad.members:
		if is_instance_valid(m) and not m.is_queued_for_deletion() and "combat_role" in m:
			var r = m.combat_role
			roles[r] = roles.get(r, 0) + 1
	if roles.is_empty():
		return null

	var template = SquadTemplate.new(name_hint + " " + str(100 + randi() % 900), roles)
	template.has_shields = squad.template.has_shields if squad.template else false
	template.base_spawn_weight = 70.0 # already proved something in combat, start a bit above baseline experimental
	template.spawn_weight = 70.0
	template.is_experimental = true
	return template
