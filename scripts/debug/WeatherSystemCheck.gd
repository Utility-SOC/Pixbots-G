extends Node

# WeatherSystem: a storm ramps up, holds and fades on schedule; sight shrinks with intensity and returns; blizzards are
# rarer than sandstorms; only Desert and Tundra maps get weather; the sight gate reads it.

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _run(kind: String, seed_v: int, seconds: float) -> WeatherSystem:
	SimRng.seed_all(seed_v)
	var w = WeatherSystem.new()
	w.kind = kind
	add_child(w)
	var t = 0.0
	while t < seconds:
		w.advance(0.25)
		t += 0.25
	return w

func _ready():
	_check("only Desert and Tundra have weather", WeatherSystem.KIND_BY_MAP.has("Desert") and WeatherSystem.KIND_BY_MAP.has("Tundra") and not WeatherSystem.KIND_BY_MAP.has("Forest"))
	_check("no weather node means no sight change", WeatherSystem.sight_mult(get_tree()) == 1.0)

	SimRng.seed_all(7)
	var w = WeatherSystem.new()
	w.kind = "sandstorm"
	add_child(w)
	_check("clear sky at the start", w.state == WeatherSystem.State.CLEAR and w.current_sight_mult() == 1.0)
	var saw_ramp = false
	var saw_hold = false
	var min_mult = 1.0
	var t = 0.0
	while t < 200.0 and not (saw_hold and w.state == WeatherSystem.State.CLEAR and w.storms_started > 0):
		w.advance(0.25)
		t += 0.25
		if w.state == WeatherSystem.State.RAMP_UP:
			saw_ramp = true
		if w.state == WeatherSystem.State.HOLD:
			saw_hold = true
		min_mult = minf(min_mult, w.current_sight_mult())
	_check("a sandstorm ramps, holds and ends within 200 s", saw_ramp and saw_hold and w.state == WeatherSystem.State.CLEAR and w.intensity == 0.0)
	_check("at its peak sight drops to the storm minimum (%.2f)" % min_mult, is_equal_approx(min_mult, WeatherSystem.KINDS["sandstorm"]["min_sight"]))
	_check("sight is back to normal after it passes", w.current_sight_mult() == 1.0)

	var sand = _run("sandstorm", 11, 1500.0)
	var blizz = _run("blizzard", 11, 1500.0)
	_check("blizzards are rarer than sandstorms (%d vs %d in 1500 s)" % [blizz.storms_started, sand.storms_started], blizz.storms_started < sand.storms_started and sand.storms_started >= 5)
	var again = _run("sandstorm", 11, 1500.0)
	_check("a seed reproduces the same weather", again.storms_started == sand.storms_started)

	# ebb and flow: sight rises and falls again within one held storm
	SimRng.seed_all(5)
	var e = WeatherSystem.new()
	e.kind = "sandstorm"
	add_child(e)
	while e.state != WeatherSystem.State.HOLD:
		e.advance(0.25)
	var lo = 1.0
	var hi = 0.0
	var flips = 0
	var last = e.intensity
	var dir = 0
	for i in range(int(10.0 / 0.25)):
		if e.state != WeatherSystem.State.HOLD:
			break
		e.advance(0.25)
		lo = minf(lo, e.intensity)
		hi = maxf(hi, e.intensity)
		var d = signi(int(sign(e.intensity - last) * 1.0))
		if d != 0 and d != dir:
			flips += 1
			dir = d
		last = e.intensity
	_check("a held storm thins and swells (%.2f..%.2f, %d turns)" % [lo, hi, flips], hi > lo + 0.3 and flips >= 2)
	e.remove_from_group("weather")
	for old in [w, sand, blizz, again]:
		old.remove_from_group("weather")
	var live = WeatherSystem.new()
	live.kind = "sandstorm"
	add_child(live)
	live.intensity = 1.0
	_check("the sight gate reads the live weather", is_equal_approx(WeatherSystem.sight_mult(get_tree()), 0.2))
	print("WeatherSystemCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
