extends Node

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	const Scorch = preload("res://scripts/visuals/ScorchDecals.gd")
	# No world: mark() must be a harmless no-op.
	Scorch.mark(get_tree(), Vector2.ZERO, 50.0)
	_check("mark with no world does nothing", Scorch.marks_added() == 0)
	var d = Scorch.new()
	add_child(d)
	await get_tree().process_frame
	for i in range(Scorch.MAX_MARKS + 40):
		d.add_mark(Vector2(i * 10, 0), 40.0 + (i % 5) * 20.0, Color(0.05, 0.04, 0.04))
	_check("ring buffer caps visible instances at %d" % Scorch.MAX_MARKS, d.multimesh.visible_instance_count == Scorch.MAX_MARKS)
	_check("counter keeps counting past the cap", d._count == Scorch.MAX_MARKS + 40)
	_check("one multimesh = one draw (single instance node)", d.multimesh.instance_count == Scorch.MAX_MARKS)
	d._born[0] -= Scorch.LIFETIME * 2.0
	d._tick = 99.0
	d._process(0.0)
	_check("old marks fade to zero alpha", d._alpha[0] == 0.0)
	_check("fresh marks keep their alpha", d._alpha[1] > 0.3)
	print("scorch decal check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
