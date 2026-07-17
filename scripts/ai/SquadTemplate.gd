class_name SquadTemplate
extends Resource

@export var template_name: String = "Unnamed Template"
# Dictionary mapping combat_role (String) to quantity (int)
# e.g., {"ranged": 2, "melee": 3}
@export var required_roles: Dictionary = {}

# The AI's learned weight. Higher = more likely to spawn.
@export var spawn_weight: float = 100.0
@export var base_spawn_weight: float = 100.0
@export var has_shields: bool = false

# Templates produced by mutation, random generation, or from a successful
# merged-squad composition start out "experimental": SquadDirector tracks
# them separately, caps how many can be on trial at once, and culls them if
# they underperform after a minimum number of trials (see SquadDirector's
# MAX_EXPERIMENTAL_TEMPLATES / MIN_TRIALS_BEFORE_CULL / CULL_FITNESS_THRESHOLD).
@export var is_experimental: bool = false

# Total number of times this squad has been deployed
var times_deployed: int = 0
# Cumulative fitness score (used for averaging)
var total_fitness: float = 0.0

# --- War Room graph data -------------------------------------------------
# Which template this one was mutated/derived from ("" for hand-authored or
# fully random templates). The parent may since have been culled - keep the
# name anyway so the family tree can show ghost ancestors.
@export var parent_name: String = ""

# Which pilot first bred this template - "" means locally bred on this
# install, never imported. Stamped at export time (see SquadProfileManager.
# export_to_clipboard) with the exporting pilot's SaveManager.pilot_name if
# it wasn't already set, so a re-shared template keeps crediting its actual
# originator through a chain of hand-offs. Used on import to disambiguate a
# name collision instead of silently overwriting local progress (see
# SquadDirector._merge_imported) and to bias crossover toward mixing
# lineages from different pilots (see maybe_introduce_experimental_template).
# Visible in the War Room, deliberately not surfaced anywhere more prominent.
@export var origin_pilot: String = ""
# Per-deployment fitness scores, newest last, capped so a long campaign
# doesn't grow saves unboundedly. Drives the War Room efficacy graph.
const FITNESS_HISTORY_CAP = 60
var fitness_history: Array = []

func _init(_name: String = "Unnamed", _roles: Dictionary = {}):
	template_name = _name
	required_roles = _roles

func get_average_fitness() -> float:
	if times_deployed == 0:
		return 0.0
	return total_fitness / float(times_deployed)

func update_fitness(fitness_score: float):
	times_deployed += 1
	total_fitness += fitness_score
	fitness_history.append(fitness_score)
	if fitness_history.size() > FITNESS_HISTORY_CAP:
		fitness_history.pop_front()

	# Simple Reinforcement Learning step:
	# Blend current weight with the new fitness score.
	# We use a learning rate (e.g. 0.2) so it adapts over time.
	var learning_rate = 0.2
	
	# Assume 100 is "average expected fitness". If it scores 200, it doubles its target weight.
	var target_weight = base_spawn_weight * (fitness_score / 100.0)
	
	# To prevent weights dropping to 0 or exploding to infinity:
	target_weight = clamp(target_weight, 10.0, 1000.0)
	
	spawn_weight = lerp(spawn_weight, target_weight, learning_rate)

func to_dict() -> Dictionary:
	return {
		"template_name": template_name,
		"required_roles": required_roles,
		"spawn_weight": spawn_weight,
		"base_spawn_weight": base_spawn_weight,
		"times_deployed": times_deployed,
		"total_fitness": total_fitness,
		"is_experimental": is_experimental,
		"parent_name": parent_name,
		"fitness_history": fitness_history,
		"origin_pilot": origin_pilot,
	}

func from_dict(data: Dictionary):
	if data.has("template_name"): template_name = data["template_name"]
	if data.has("required_roles"): required_roles = data["required_roles"]
	if data.has("spawn_weight"): spawn_weight = float(data["spawn_weight"])
	if data.has("base_spawn_weight"): base_spawn_weight = float(data["base_spawn_weight"])
	if data.has("times_deployed"): times_deployed = int(data["times_deployed"])
	if data.has("total_fitness"): total_fitness = float(data["total_fitness"])
	if data.has("is_experimental"): is_experimental = bool(data["is_experimental"])
	if data.has("parent_name"): parent_name = str(data["parent_name"])
	if data.has("fitness_history"): fitness_history = data["fitness_history"].duplicate() if data["fitness_history"] is Array else []
	if data.has("origin_pilot"): origin_pilot = str(data["origin_pilot"])

