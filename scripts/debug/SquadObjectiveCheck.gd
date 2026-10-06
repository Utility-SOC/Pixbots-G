extends Node

const Tactics = preload("res://scripts/ai/SquadTactics.gd")
const ObjScript = preload("res://scripts/hazards/ZoneObjective.gd")

# Minimal squad stand-in: only what objective_focus touches.
class FakeSquad extends Node2D:
	func get_center_position() -> Vector2:
		return global_position

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _squad_with_id_mod(want: int) -> Node2D:
	for _i in range(60):
		var s = FakeSquad.new()
		add_child(s)
		if s.get_instance_id() % 3 == want:
			return s
		s.queue_free()
	return null

func _ready():
	var obj = ObjScript.new()
	obj.kind = "hold"
	obj.radius = 100.0
	obj.set_process(false)
	add_child(obj)
	obj.global_position = Vector2(1000, 0)
	var defender = _squad_with_id_mod(0)
	var other = _squad_with_id_mod(1)
	defender.global_position = Vector2(1000, 500)
	other.global_position = Vector2(1000, 500)
	var player = Vector2(-2000, 0)
	_check("no defence while the ring is untouched", Tactics.objective_focus(defender, player) == Vector2.INF)
	obj.progress = 0.6
	_check("a squad (id%3==0) defends a ring the player has started", Tactics.objective_focus(defender, player) == obj.global_position)
	_check("other squads keep chasing", Tactics.objective_focus(other, player) == Vector2.INF)
	_check("no defence while the player stands in the ring", Tactics.objective_focus(defender, Vector2(1010, 0)) == Vector2.INF)
	defender.global_position = Vector2(1000, 5000)
	_check("too far away to defend", Tactics.objective_focus(defender, player) == Vector2.INF)
	defender.global_position = Vector2(1000, 500)
	obj.done = true
	_check("a captured ring is not defended", Tactics.objective_focus(defender, player) == Vector2.INF)
	print("squad objective check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
