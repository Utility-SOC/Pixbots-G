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

func setup(_template: SquadTemplate):
	template = _template

func _physics_process(delta: float):
	if active_members > 0:
		time_alive += delta

func add_member(mech: Node):
	members.append(mech)
	active_members += 1
	initial_members += 1
	
	# Listen for when the member dies (exits the tree)
	mech.tree_exiting.connect(_on_member_died)
	
	# Listen for when the member deals damage
	if mech.has_user_signal("dealt_damage") or mech.has_signal("dealt_damage"):
		mech.dealt_damage.connect(_on_member_dealt_damage)
	elif not mech.has_signal("dealt_damage"):
		mech.add_user_signal("dealt_damage", [{"name": "amount", "type": TYPE_FLOAT}])
		mech.connect("dealt_damage", _on_member_dealt_damage)

func _on_member_dealt_damage(amount: float):
	total_damage_dealt += amount

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

func check_combat_state(is_in_combat: bool):
	if not is_in_combat and active_members < initial_members:
		request_linkup.emit(self)

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
	
	# 2. Capped Survival Score (Max 60 seconds reward)
	# This prevents the AI from learning that hiding infinitely is the best strategy.
	var effective_survival = min(time_alive, 60.0)
	var survival_score = effective_survival * 2.0
	
	# 3. Engagement Requirement
	# If the squad dealt 0 damage, they get NO survival points (anti-ambush/hiding exploit)
	if total_damage_dealt <= 0.0:
		survival_score = 0.0
		
	var fitness = damage_score + survival_score
	return fitness
