class_name Squad
extends Node

signal squad_defeated(squad, fitness_score)
signal request_linkup(squad)

var template: SquadTemplate
var members: Array[Node] = []
var active_members: int = 0
var initial_members: int = 0

var time_alive: float = 0.0
var total_damage_dealt: float = 0.0

# --- Additional fitness inputs (Natalia: "recommend additional axes of
# fitness... tracked/used") ------------------------------------------------
# Damage this squad's members actually took, mirroring total_damage_dealt -
# lets fitness reward FAVORABLE TRADES (dealt >> taken) instead of only ever
# looking at offense, which previously let a squad that "won" by trading
# evenly (or badly) score identically to one that stomped cleanly.
var total_damage_taken: float = 0.0
# Subset of the above specifically from a Mythic Magnet repel-mode bounce -
# the AI noticing "we're dying to our own reflected fire" and weighting
# speed/shield accordingly was an explicit ask, not just an offense/defense
# balance nicety.
var reflected_damage_taken: float = 0.0
# Hits landed while the attacking member itself had has_sight_of_player ==
# false (i.e. it was standing inside the player's own JammerField and
# denied precise targeting - see Mech._update_player_sight). Closes the
# loop on this session's Jammer redesign: nothing previously measured
# whether the AI actually adapted to being Blind, so it had no way to learn
# "keep pressing" vs. "back off and snipe" as separate viable strategies.
var blind_hits_landed: int = 0

# --- Fitness inputs added for the AI evolution system ---
# Raw hit count (not just damage total) so a template that lands lots of
# small hits isn't scored purely worse than one that lands one big hit.
var hits_landed: int = 0
# Survival is now measured from first engagement, not from spawn - a squad
# that spent 10s walking over before finding the player shouldn't get
# "survival" credit for that walk.
var first_engagement_time: float = -1.0
# How long it's been since this squad last landed a hit, once it has
# engaged at least once. Used to detect "gone quiet" (fleeing/hiding after
# initial contact) and penalize it - separate from the existing zero-damage
# anti-hiding rule, which only catches squads that NEVER engaged at all.
var time_since_last_hit_dealt: float = 0.0
var flee_penalty: float = 0.0

const FLEE_GRACE_PERIOD: float = 5.0 # seconds of silence (post-engagement) tolerated before penalizing
const FLEE_PENALTY_RATE: float = 1.5 # fitness points/sec subtracted beyond the grace period

# --- Shared search memory (Natalia: "everyone in the squad knows where
# everyone in the squad has looked") --------------------------------------
# Coarse grid of world-space cells the squad has collectively covered while
# searching (see Mech.gd's _execute_search/_execute_scout_search) - members
# mark cells as explored as they move through them, and deprioritize/skip
# past cells a squadmate already covered recently instead of dutifully
# re-walking the same ground. Keyed on `time_alive` (already ticked every
# physics frame below) rather than a wall-clock timestamp, since this only
# ever needs to compare against other times measured the same way.
const EXPLORE_CELL_SIZE = 160.0
const EXPLORE_STALE_AFTER = 25.0 # after this long a cell is fair game to re-search
var explored_cells: Dictionary = {} # Vector2i cell -> time_alive when last marked

func _explore_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(world_pos.x / EXPLORE_CELL_SIZE)), int(floor(world_pos.y / EXPLORE_CELL_SIZE)))

func mark_explored(world_pos: Vector2):
	explored_cells[_explore_cell(world_pos)] = time_alive

func is_recently_explored(world_pos: Vector2) -> bool:
	var cell = _explore_cell(world_pos)
	if not explored_cells.has(cell):
		return false
	return (time_alive - explored_cells[cell]) < EXPLORE_STALE_AFTER

func setup(_template: SquadTemplate):
	template = _template

func _physics_process(delta: float):
	if active_members > 0:
		time_alive += delta

		if first_engagement_time >= 0:
			time_since_last_hit_dealt += delta
			if time_since_last_hit_dealt > FLEE_GRACE_PERIOD:
				flee_penalty += FLEE_PENALTY_RATE * delta

func add_member(mech: Node):
	members.append(mech)
	active_members += 1
	initial_members += 1

	# Back-reference so the mech can broadcast "I see the player" to its
	# OWN squadmates only (see Mech.gd's _share_sight_with_squad) - never
	# globally, so other squads don't get that freebie.
	if "squad" in mech:
		mech.squad = self

	# A wild bot recruited back into service rejoins the fight - clears the
	# flee/wild loiter state (see Mech._update_flee_state).
	if mech.has_method("rejoin_from_wild"):
		mech.rejoin_from_wild()

	# Listen for when the member dies (exits the tree)
	mech.tree_exiting.connect(_on_member_died)

	# Listen for when the member deals damage
	if mech.has_user_signal("dealt_damage") or mech.has_signal("dealt_damage"):
		mech.dealt_damage.connect(_on_member_dealt_damage.bind(mech))
	elif not mech.has_signal("dealt_damage"):
		mech.add_user_signal("dealt_damage", [{"name": "amount", "type": TYPE_FLOAT}])
		mech.connect("dealt_damage", _on_member_dealt_damage.bind(mech))

	# Listen for when the member takes damage (see total_damage_taken's own
	# field comment) - a real declared signal on every Mech from the start,
	# so this doesn't need the has_user_signal fallback dance dealt_damage
	# above still carries for historical/defensive reasons.
	if mech.has_signal("took_damage"):
		mech.took_damage.connect(_on_member_took_damage)

func _on_member_dealt_damage(amount: float, mech: Node = null):
	total_damage_dealt += amount
	hits_landed += 1
	time_since_last_hit_dealt = 0.0
	if first_engagement_time < 0:
		first_engagement_time = time_alive
	if mech and is_instance_valid(mech) and "has_sight_of_player" in mech and not mech.has_sight_of_player:
		blind_hits_landed += 1

func _on_member_took_damage(amount: float, was_reflected: bool):
	total_damage_taken += amount
	if was_reflected:
		reflected_damage_taken += amount

func get_center_position() -> Vector2:
	if members.is_empty(): return Vector2.ZERO
	var center = Vector2.ZERO
	var valid_count = 0
	for m in members:
		if is_instance_valid(m) and m is Node2D:
			center += m.global_position
			valid_count += 1
	if valid_count == 0: return Vector2.ZERO
	return center / valid_count

func _on_member_died():
	active_members -= 1
	if active_members <= 0:
		_on_squad_wiped()
	else:
		# Evaluate link up when losing a member
		request_linkup.emit(self)

func _on_squad_wiped():
	var fitness = _calculate_fitness()
	squad_defeated.emit(self, fitness)
	queue_free()

func _calculate_fitness() -> float:
	# 1. Damage Score
	var damage_score = total_damage_dealt * 1.0

	# 2. Hit Score - rewards actually landing shots, independent of how
	# much damage each one did (keeps low-damage-but-aggressive roles like
	# scouts/ambushers from being undervalued next to a single hard-hitting
	# sniper shot).
	var hit_score = hits_landed * 3.0

	# 3. Capped Survival Score (Max 60 seconds reward), measured from FIRST
	# ENGAGEMENT rather than spawn time.
	var effective_survival = 0.0
	if first_engagement_time >= 0:
		effective_survival = min(time_alive - first_engagement_time, 60.0)
	var survival_score = effective_survival * 2.0

	# 4. Engagement Requirement - if the squad never landed a hit at all,
	# they get NO survival points (anti-ambush/hiding exploit).
	if hits_landed <= 0:
		survival_score = 0.0

	# 5. Flee Penalty - accumulated whenever the squad goes quiet for too
	# long after having engaged at least once (see _physics_process).

	# 6. Damage Trade Efficiency - rewards favorable trades (dealt >> taken)
	# and mildly punishes lopsided ones. Ratio-based (not raw magnitude) so
	# it stays meaningful regardless of how big damage numbers get late-game.
	# Clamped so one freak early trade (e.g. a single hit before any damage
	# taken yet) can't swing the whole score.
	var trade_ratio = damage_score / max(1.0, total_damage_taken)
	var trade_score = clamp((trade_ratio - 1.0) * 15.0, -40.0, 60.0)

	# 7. Reflection Punishment (Natalia: "AI will need to track if I am
	# doing something like using the mythic magnet - that should prompt
	# more speed to breach the magnet projectiles, and more shield than
	# weapon to survive shooting themselves"). Same magnitude scale as
	# damage_score so it's directly comparable, not a separate unit.
	var reflection_penalty = reflected_damage_taken * 0.5

	# 8. Blind Resilience - landing hits while denied precise sight (inside
	# the player's own JammerField) is a harder feat than a normal hit, so
	# it's worth slightly more than hit_score's per-hit rate (3.0).
	var blind_score = blind_hits_landed * 4.0

	var fitness = damage_score + hit_score + survival_score + trade_score + blind_score - flee_penalty - reflection_penalty
	return max(0.0, fitness)
