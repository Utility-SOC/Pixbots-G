class_name SolverProfile
extends Resource

# Configures what AutoEquipSolver optimizes for, instead of the solver
# always doing the exact same fixed-priority tile placement regardless of
# who it's building for. A profile answers three questions:
#   - What element should this loadout lean into? (favored_synergy)
#   - How much should it prioritize Pierce (cracking high-shield/high-armor
#     builds) vs raw Amplify power?
#   - Is it still "on trial" for the evolutionary system, same as
#     SquadTemplate's is_experimental?

@export var profile_name: String = "Default"

# Which combat role this doctrine is tuned for ("sniper", "brawler", etc. -
# see SquadTemplateMutator.ALL_ROLES) - "" means role-agnostic (the always-
# fresh reactive baseline SquadDirector.build_reactive_profile() builds, or
# a legacy profile saved before role-scoping existed). Profiles used to be
# one flat pool shared by every role, which meant a sniper doctrine (should
# favor Pierce, long range) and a brawler doctrine (should favor Kinetic/
# Explosion, close range) directly competed for the same spawn-weight
# rotation and diluted each other. Selection/mutation/crossover now all
# stay within-role (see SquadDirector.get_active_solver_profile/
# maybe_introduce_experimental_profile) so each role grows its own lineage.
@export var role: String = ""

# EnergyPacket.SynergyType to build toward, or -1 for "no preference"
# (plain Amplifier/Catalyst priority, the old fixed behavior).
@export var favored_synergy: int = -1

# Relative weights the solver uses when both a Pierce-flavored option and an
# Amplify-flavored option are available at the same grid position. These
# don't need to sum to 1 - only their ratio matters.
@export var pierce_priority: float = 0.2
@export var amplify_priority: float = 1.0

@export var is_experimental: bool = false
@export var base_spawn_weight: float = 100.0
@export var spawn_weight: float = 100.0

# See SquadTemplate.origin_pilot's field comment - same attribution
# mechanism, shared across all three evolvable profile types.
@export var origin_pilot: String = ""

var times_used: int = 0
var total_fitness: float = 0.0

func _init(_name: String = "Default", _favored_synergy: int = -1):
	profile_name = _name
	favored_synergy = _favored_synergy

func get_average_fitness() -> float:
	if times_used == 0:
		return 0.0
	return total_fitness / float(times_used)

# Same reinforcement-learning shape as SquadTemplate.update_fitness - kept
# deliberately identical so the two evolutionary systems behave predictably
# the same way.
func update_fitness(fitness_score: float):
	times_used += 1
	total_fitness += fitness_score

	var learning_rate = 0.2
	var target_weight = base_spawn_weight * (fitness_score / 100.0)
	target_weight = clamp(target_weight, 10.0, 1000.0)
	spawn_weight = lerp(spawn_weight, target_weight, learning_rate)

func to_dict() -> Dictionary:
	return {
		"profile_name": profile_name,
		"role": role,
		"favored_synergy": favored_synergy,
		"pierce_priority": pierce_priority,
		"amplify_priority": amplify_priority,
		"is_experimental": is_experimental,
		"spawn_weight": spawn_weight,
		"base_spawn_weight": base_spawn_weight,
		"times_used": times_used,
		"total_fitness": total_fitness,
		"origin_pilot": origin_pilot,
	}

func from_dict(data: Dictionary):
	if data.has("profile_name"): profile_name = data["profile_name"]
	if data.has("role"): role = str(data["role"])
	if data.has("favored_synergy"): favored_synergy = int(data["favored_synergy"])
	if data.has("pierce_priority"): pierce_priority = float(data["pierce_priority"])
	if data.has("amplify_priority"): amplify_priority = float(data["amplify_priority"])
	if data.has("is_experimental"): is_experimental = bool(data["is_experimental"])
	if data.has("spawn_weight"): spawn_weight = float(data["spawn_weight"])
	if data.has("base_spawn_weight"): base_spawn_weight = float(data["base_spawn_weight"])
	if data.has("times_used"): times_used = int(data["times_used"])
	if data.has("total_fitness"): total_fitness = float(data["total_fitness"])
	if data.has("origin_pilot"): origin_pilot = str(data["origin_pilot"])
