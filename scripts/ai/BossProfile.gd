class_name BossProfile
extends Resource

# Evolvable boss "kit" - same reinforcement-learning shape as SquadTemplate/
# SolverProfile (see SquadDirector), applied to bosses instead of squads or
# loadout doctrine. A profile answers:
#   - What underlying role/stat-block is this built on? (base_role - still
#     drives HP/speed/engagement_distance/visuals via
#     SquadDirector._spawn_bot_for_role, same as before)
#   - Which signature move(s) can it use, and how tanky is it relative to
#     that role's baseline? (ability_pool, hp_mult)
#   - How does it rage, and how does it move? (enrage_style, position_style)
# Mutation can nudge any of these independently, which is what makes boss
# variety an evolving pool instead of 6 fixed, hand-picked archetypes.

const ALL_ABILITIES = ["shockwave", "railgun", "blink_strike", "fire_pool", "jam_burst", "rally"]
const ALL_ENRAGE_STYLES = ["berserker", "juggernaut", "vampiric", "unstable"]
const ALL_POSITION_STYLES = ["aggressive", "kiter", "circler"]
const ALL_ROLES = ["brawler", "sniper", "ambusher", "flamethrower", "jammer", "commander"]

@export var profile_name: String = "Warhulk"
@export var base_role: String = "brawler"
@export var ability_pool: Array = ["shockwave"]
@export var enrage_style: String = "berserker"
@export var position_style: String = "aggressive"
@export var hp_mult: float = 1.0

@export var is_experimental: bool = false
@export var base_spawn_weight: float = 100.0
@export var spawn_weight: float = 100.0

# Which profile this one mutated from - empty for the 6 hand-authored
# originals. Set by SquadDirector._mutate_boss_profile. Mirrors
# SquadTemplate.parent_name so the War Room can show boss lineage the same
# way it already shows squad lineage.
@export var parent_name: String = ""

var times_used: int = 0
var total_fitness: float = 0.0

# Per-deployment fitness history, same shape/cap as SquadTemplate's - drives
# the War Room's boss efficacy sparkline.
const FITNESS_HISTORY_CAP = 60
var fitness_history: Array = []

func _init(_name: String = "Warhulk", _base_role: String = "brawler"):
	profile_name = _name
	base_role = _base_role

func get_average_fitness() -> float:
	if times_used == 0:
		return 0.0
	return total_fitness / float(times_used)

# Same shape as SolverProfile.update_fitness - kept identical so all three
# evolutionary systems (squad templates, solver profiles, boss profiles)
# behave predictably the same way. 100 is "expected average" by convention
# (boss fitness is damage-dealt-to-player + hits + survival, the same
# formula shape as Squad._calculate_fitness, so it lands in a comparable
# range even though a boss is a solo "squad of one").
func update_fitness(fitness_score: float):
	times_used += 1
	total_fitness += fitness_score
	fitness_history.append(fitness_score)
	if fitness_history.size() > FITNESS_HISTORY_CAP:
		fitness_history.pop_front()

	var learning_rate = 0.2
	var target_weight = base_spawn_weight * (fitness_score / 100.0)
	target_weight = clamp(target_weight, 10.0, 1000.0)
	spawn_weight = lerp(spawn_weight, target_weight, learning_rate)

func to_dict() -> Dictionary:
	return {
		"profile_name": profile_name,
		"base_role": base_role,
		"ability_pool": ability_pool,
		"enrage_style": enrage_style,
		"position_style": position_style,
		"hp_mult": hp_mult,
		"is_experimental": is_experimental,
		"spawn_weight": spawn_weight,
		"base_spawn_weight": base_spawn_weight,
		"parent_name": parent_name,
		"times_used": times_used,
		"total_fitness": total_fitness,
		"fitness_history": fitness_history,
	}

func from_dict(data: Dictionary):
	if data.has("profile_name"): profile_name = data["profile_name"]
	if data.has("base_role"): base_role = data["base_role"]
	if data.has("ability_pool"):
		ability_pool = []
		for a in data["ability_pool"]:
			ability_pool.append(str(a))
	if data.has("enrage_style"): enrage_style = data["enrage_style"]
	if data.has("position_style"): position_style = data["position_style"]
	if data.has("hp_mult"): hp_mult = float(data["hp_mult"])
	if data.has("is_experimental"): is_experimental = bool(data["is_experimental"])
	if data.has("spawn_weight"): spawn_weight = float(data["spawn_weight"])
	if data.has("base_spawn_weight"): base_spawn_weight = float(data["base_spawn_weight"])
	if data.has("parent_name"): parent_name = str(data["parent_name"])
	if data.has("times_used"): times_used = int(data["times_used"])
	if data.has("total_fitness"): total_fitness = float(data["total_fitness"])
	if data.has("fitness_history"): fitness_history = data["fitness_history"].duplicate() if data["fitness_history"] is Array else []
