extends Node

# UiFx.pop_in: starts transparent/shrunk, ends exactly at the resting alpha and scale (even if the tree is paused and
# even for a control with a non-1 resting alpha), and a re-open mid-fade does not lose the resting alpha.

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	var panel := Panel.new()
	panel.size = Vector2(200, 100)
	panel.modulate = Color(1, 1, 1, 0.8)
	add_child(panel)
	get_tree().paused = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	var tw := UiFx.pop_in(panel, 0.1)
	_check("tween created", tw != null)
	_check("starts transparent", panel.modulate.a == 0.0)
	_check("starts shrunk", panel.scale.x < 1.0)
	_check("pivot is centred", panel.pivot_offset == Vector2(100, 50))
	await get_tree().create_timer(0.05, true, false, true).timeout
	UiFx.pop_in(panel, 0.1) # reopened mid-fade
	await get_tree().create_timer(0.3, true, false, true).timeout
	_check("ends at the resting alpha while paused (%.3f)" % panel.modulate.a, is_equal_approx(panel.modulate.a, 0.8))
	_check("ends at the resting scale", panel.scale == Vector2.ONE)

	var layer := CanvasLayer.new()
	var inner := Control.new()
	layer.add_child(inner)
	add_child(layer)
	UiFx.pop_in_layer(layer, 0.05)
	_check("layer child fades", inner.modulate.a == 0.0 and inner.scale == Vector2.ONE)
	await get_tree().create_timer(0.2, true, false, true).timeout
	_check("layer child restored", is_equal_approx(inner.modulate.a, 1.0))
	_check("null control is ignored", UiFx.pop_in(null) == null)

	get_tree().paused = false
	print("UiFxCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
