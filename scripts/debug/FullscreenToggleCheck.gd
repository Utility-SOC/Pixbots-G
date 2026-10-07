extends Node

# Fullscreen toggle: F11 and Alt+Enter flip SaveManager.fullscreen, the signal fires, and (in a real window) the
# DisplayServer mode follows: FULLSCREEN when on, MAXIMIZED when off. Ends with fullscreen OFF.

var failures = 0
var _signals := 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _key(code: int, alt := false) -> InputEventKey:
	var e = InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.alt_pressed = alt
	return e

func _ready():
	var headless: bool = DisplayServer.get_name() == "headless"
	SaveManager.fullscreen_changed.connect(func(_on): _signals += 1)
	SaveManager.set_fullscreen(false, false)
	_signals = 0
	await get_tree().process_frame
	SaveManager._input(_key(KEY_F11))
	_check("F11 turns fullscreen on", SaveManager.fullscreen)
	_check("the change signal fired once", _signals == 1)
	if not headless:
		await get_tree().create_timer(0.6).timeout
		_check("window mode is FULLSCREEN", DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	SaveManager._input(_key(KEY_F11))
	_check("F11 again turns it off", not SaveManager.fullscreen)
	if not headless:
		await get_tree().create_timer(0.6).timeout
		_check("window mode is back to MAXIMIZED", DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED)
	SaveManager._input(_key(KEY_ENTER, true))
	_check("Alt+Enter turns it on", SaveManager.fullscreen)
	SaveManager._input(_key(KEY_ENTER, false))
	_check("plain Enter does nothing", SaveManager.fullscreen)
	SaveManager._input(_key(KEY_ENTER, true))
	_check("Alt+Enter turns it off again", not SaveManager.fullscreen)
	print("FullscreenToggleCheck (%s): %d failure(s)" % ["headless" if headless else "windowed", failures])
	get_tree().quit(1 if failures > 0 else 0)
