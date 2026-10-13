extends Node

# TableSettingScreen: the loading card draws over everything, keeps processing while paused, animates, and frees itself.
var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	var s = TableSettingScreen.show_over(self)
	await get_tree().process_frame
	_check("above other layers", s.layer >= 100)
	_check("always processes", s.process_mode == Node.PROCESS_MODE_ALWAYS)
	_check("has a label", s.get_child_count() >= 2)
	var lbl = s.get_child(s.get_child_count() - 1) as Label
	_check("label says something table-ish", lbl != null and lbl.text.length() > 4)
	s.finish()
	await get_tree().process_frame
	await get_tree().process_frame
	_check("frees itself", not is_instance_valid(s))
	var main_src = FileAccess.get_file_as_string("res://scripts/core/Main.gd")
	_check("rotation shows the card", main_src.contains("TableSettingScreen.show_over(self)"))
	print("TableSettingScreenCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
