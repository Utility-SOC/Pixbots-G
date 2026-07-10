extends Node

# Exercises JammerField.gd standalone: a fake "owner" node moving in a
# straight line at speed, watching the field's anchor lag behind and the
# boundary wobble/drag over several ticks. Safe to delete once validated.

const JammerField = preload("res://scripts/visuals/JammerField.gd")

var owner_stub: Node2D
var field: JammerField
var _ticks := 0
const TOTAL_TICKS := 40
const DT := 1.0 / 30.0

func _ready():
	owner_stub = Node2D.new()
	owner_stub.global_position = Vector2(0, 0)
	owner_stub.set("is_player", true)
	add_child(owner_stub)

	field = JammerField.new()
	field.global_position = owner_stub.global_position
	field.setup(owner_stub, 300.0, -1.0)
	add_child(field)
	# Drive it manually at a fixed DT below for deterministic output instead
	# of letting the engine's own automatic _process call fight with that.
	field.set_process(false)

	print("owner_is_player: ", field.owner_is_player)
	set_process(true)

func _process(_delta):
	_ticks += 1
	# Move the owner fast in a straight line to exercise anchor lag + drag bias.
	owner_stub.global_position += Vector2(400.0, 0.0) * DT
	field._process(DT) # drive manually at a fixed DT for deterministic output

	if _ticks == TOTAL_TICKS:
		var gap = owner_stub.global_position.distance_to(field.global_position)
		var radii: Array = []
		for p in field.boundary_points:
			radii.append(p.length())
		var min_r = radii.min()
		var max_r = radii.max()
		print("After ", TOTAL_TICKS, " ticks moving at 400 u/s:")
		print("  owner pos: ", owner_stub.global_position, "  field anchor pos: ", field.global_position)
		print("  lag gap (owner vs anchor): ", gap)
		print("  boundary radius range: ", min_r, " - ", max_r, " (base_radius=", field.base_radius, ")")
		print("  boundary_points count: ", field.boundary_points.size())
		var inside_owner = field.is_point_inside(owner_stub.global_position)
		var inside_far = field.is_point_inside(owner_stub.global_position + Vector2(5000, 0))
		print("  is_point_inside(owner): ", inside_owner, "  is_point_inside(far away): ", inside_far)
		print("OK - no errors across ", TOTAL_TICKS, " manual ticks")
		get_tree().quit()
