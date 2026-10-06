extends Node

const Fx = preload("res://scripts/core/FxTier.gd")
var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	_check("headless runs are never flipped to safe by a stale marker", not Fx.safe() or OS.get_environment("PIXBOTS_SAFE_FX") == "1")
	# simulate the three states by hand
	Fx._auto_safe = true
	_check("auto-safe turns the tier on", Fx.safe())
	OS.set_environment("PIXBOTS_FULL_FX", "1")
	_check("PIXBOTS_FULL_FX overrides auto-safe", not Fx.safe())
	OS.set_environment("PIXBOTS_FULL_FX", "")
	Fx._auto_safe = false
	OS.set_environment("PIXBOTS_SAFE_FX", "1")
	_check("PIXBOTS_SAFE_FX turns it on", Fx.safe())
	OS.set_environment("PIXBOTS_SAFE_FX", "")
	_check("off again when nothing asks for it", not Fx.safe())
	# marker lifecycle
	var f = FileAccess.open(Fx.MARKER, FileAccess.WRITE)
	f.store_string("x")
	f.close()
	_check("marker exists", FileAccess.file_exists(Fx.MARKER))
	Fx.end_session()
	_check("a clean quit removes the marker", not FileAccess.file_exists(Fx.MARKER))
	print("fx tier check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
