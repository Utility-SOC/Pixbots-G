class_name StockBuild
extends Resource

# The evolving, per-(squad template, role) enemy loadout - same evolving-
# record shape as SquadTemplate/SolverProfile/BossProfile (is_experimental/
# spawn_weight/parent_name/origin_pilot/to_dict/from_dict/update_fitness),
# but the "genome" here is a concrete solved hex-grid layout rather than an
# abstract set of priorities. Six different squad templates that all call
# for a sniper each get their OWN StockBuild for "sniper" - every sniper
# spawned under the SAME template reuses the SAME build (skipping
# AutoEquipSolver entirely, see StockBuildEvolution.get_stock_build), while a
# controlled fraction of spawns test a freshly-solved deviation whose fitness
# gets tracked and, at a checkpoint, promoted to replace this build if it's
# actually better (see StockBuildEvolution._flush). "Mutation" for this
# record type IS a fresh AutoEquipSolver.solve() call (see
# StockBuildMutator) - solve() already isn't deterministic call-to-call
# (see AutoEquipSolver.gd's own header), so there's no separate perturbation
# algorithm to invent.

@export var template_name: String = ""
@export var role: String = ""
# base_rarity tier this build was solved at (HexTile.Rarity) - part of the
# key alongside (template_name, role): base_rarity climbs with wave/
# difficulty progression (see SquadDirector._spawn_bot_for_role), so a
# build established early at COMMON must never get replayed onto a much
# later, much-higher-rarity spawn of the same role/template - that would
# silently freeze that (template, role)'s gear at whatever rarity it first
# happened to spawn at, defeating wave scaling entirely.
@export var rarity: int = 0
# Which same-role slot within a squad this build belongs to (0-based,
# capped at StockBuildEvolution.MAX_SUB_ARCHETYPE_SLOTS) - part of the key
# alongside (template_name, role, rarity) so squad-mates filling the SAME
# role can independently evolve toward different tactical niches (e.g. one
# brawler goes full-melee-speedy, another goes mid-range) instead of
# always sharing one shared build. See StockBuildEvolution.gd/SquadDirector.
# _assemble_squad for how this gets assigned at spawn time.
@export var sub_archetype_slot: int = 0
@export var is_experimental: bool = false
@export var base_spawn_weight: float = 100.0
@export var spawn_weight: float = 100.0
@export var parent_name: String = ""
@export var origin_pilot: String = ""
var times_used: int = 0
var total_fitness: float = 0.0
const FITNESS_HISTORY_CAP = 60
var fitness_history: Array = []

# BodySlot (int, e.g. HexTile.BodySlot.TORSO) -> SaveManager._serialize_
# component() dict - the actual payload. Reuses the exact serializer the
# player's own save file uses (see SaveManager.gd) rather than a new tile
# format.
@export var serialized_components: Dictionary = {}

# Runtime-only memoization of Mech._simulate_energy_flow's expensive
# packet-routing output (perf fix, 2026-08-10: that pass was costing
# 200ms+ per spawn on dense builds). Keyed by "<BodySlot>:<q>,<r>" ->
# Array of {"packet": EnergyPacket, "step": int}, the exact shape
# WeaponMountTile/MissileRackTile's own pending_packets already uses -
# see Mech._recalculate_grid_for_stock. Deliberately NOT @export'd: pure
# in-memory cache, safe to lose across saves/reloads (just repopulates on
# the next replay), and self-invalidating on promotion since
# StockBuildMutator.establish()/promote() always construct a brand-new
# StockBuild object rather than mutating serialized_components in place -
# a promoted build always starts with an empty cache.
var _simulation_cache: Dictionary = {}

func _init(_template_name: String = "", _role: String = "", _rarity: int = 0):
	template_name = _template_name
	role = _role
	rarity = _rarity

func get_average_fitness() -> float:
	if times_used == 0:
		return 0.0
	return total_fitness / float(times_used)

# Same RL step as SquadTemplate/SolverProfile/BossProfile - kept identical
# on purpose so all four evolving pools behave predictably the same way.
func update_fitness(fitness_score: float):
	times_used += 1
	total_fitness += fitness_score
	fitness_history.append(fitness_score)
	if fitness_history.size() > FITNESS_HISTORY_CAP:
		fitness_history.pop_front()

	var learning_rate = 0.2
	var target_weight = clamp(base_spawn_weight * (fitness_score / 100.0), 10.0, 1000.0)
	spawn_weight = lerp(spawn_weight, target_weight, learning_rate)

func to_dict() -> Dictionary:
	# Dictionary keys become strings through a JSON round trip regardless of
	# what they are on this side - stringify the BodySlot int keys explicitly
	# here so from_dict's int() conversion has a well-defined format to
	# reverse, rather than relying on JSON's own key coercion.
	var components_out = {}
	for slot in serialized_components:
		components_out[str(slot)] = serialized_components[slot]
	return {
		"template_name": template_name,
		"role": role,
		"rarity": rarity,
		"sub_archetype_slot": sub_archetype_slot,
		"is_experimental": is_experimental,
		"base_spawn_weight": base_spawn_weight,
		"spawn_weight": spawn_weight,
		"parent_name": parent_name,
		"origin_pilot": origin_pilot,
		"times_used": times_used,
		"total_fitness": total_fitness,
		"fitness_history": fitness_history,
		"serialized_components": components_out,
	}

func from_dict(data: Dictionary):
	if data.has("template_name"): template_name = str(data["template_name"])
	if data.has("role"): role = str(data["role"])
	if data.has("rarity"): rarity = int(data["rarity"])
	if data.has("sub_archetype_slot"): sub_archetype_slot = int(data["sub_archetype_slot"])
	if data.has("is_experimental"): is_experimental = bool(data["is_experimental"])
	if data.has("base_spawn_weight"): base_spawn_weight = float(data["base_spawn_weight"])
	if data.has("spawn_weight"): spawn_weight = float(data["spawn_weight"])
	if data.has("parent_name"): parent_name = str(data["parent_name"])
	if data.has("origin_pilot"): origin_pilot = str(data["origin_pilot"])
	if data.has("times_used"): times_used = int(data["times_used"])
	if data.has("total_fitness"): total_fitness = float(data["total_fitness"])
	if data.has("fitness_history"): fitness_history = data["fitness_history"].duplicate() if data["fitness_history"] is Array else []
	if data.has("serialized_components") and data["serialized_components"] is Dictionary:
		serialized_components = {}
		for slot_key in data["serialized_components"]:
			serialized_components[int(slot_key)] = data["serialized_components"][slot_key]
