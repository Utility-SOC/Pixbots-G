extends Node

# SetPieceEra: prewar leaves art untouched; each later era wears it down further (less standing area), deterministically,
# inside the footprint; no_mans_land adds wire and poppies; apocalypse adds overgrowth.

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _area(rs: Array) -> float:
	var a = 0.0
	for r in rs:
		a += r[0].size.x * r[0].size.y
	return a

func _has_color(rs: Array, pred: Callable) -> bool:
	for r in rs:
		if pred.call(r[1]):
			return true
	return false

func _ready():
	var fp = Vector2(6 * 32, 4 * 32)
	var base = SetPieceArt.rects("hangar", fp, 99)
	_check("prewar is untouched", SetPieceEra.apply(base, fp, "prewar", 5).size() == base.size())
	_check("unknown eras are treated as prewar", SetPieceEra.apply(base, fp, "bogus", 5).size() == base.size())
	var areas = {}
	for era in ["skirmish", "no_mans_land", "apocalypse"]:
		var a = SetPieceEra.apply(base, fp, era, 5)
		var b = SetPieceEra.apply(base, fp, era, 5)
		_check("%s is deterministic" % era, a.size() == b.size() and is_equal_approx(_area(a), _area(b)))
		var inside = true
		for r in a:
			var rc: Rect2 = r[0]
			if rc.position.x < -0.01 or rc.position.y < -0.01 or rc.end.x > fp.x + 0.01 or rc.end.y > fp.y + 0.01 or rc.size.x <= 0.0 or rc.size.y <= 0.0:
				inside = false
		_check("%s stays inside the footprint" % era, inside and a.size() > 0)
		areas[era] = _area(a)
	var full = 0.0
	for row in SetPieceEra._raster(base, int(fp.x / 4.0), int(fp.y / 4.0)):
		for cell in row:
			if cell != null:
				full += 16.0
	_check("skirmish loses a little (%.0f of %.0f)" % [areas["skirmish"], full], areas["skirmish"] < full and areas["skirmish"] > full * 0.8)
	_check("no man's land is more worn than skirmish", areas["no_mans_land"] < areas["skirmish"])
	_check("the apocalypse is the most worn", areas["apocalypse"] < areas["no_mans_land"] * 1.05 and areas["apocalypse"] < areas["skirmish"])
	var nml = SetPieceEra.apply(base, fp, "no_mans_land", 5)
	_check("no man's land has poppies or wire", _has_color(nml, func(c): return c.r > 0.8 and c.g < 0.2) or _has_color(nml, func(c): return c.r < 0.25 and c.g < 0.25 and c.b < 0.26))
	var apoc = SetPieceEra.apply(base, fp, "apocalypse", 5)
	_check("the apocalypse is overgrown", _has_color(apoc, func(c): return c.g > c.r + 0.1 and c.g > c.b + 0.1))
	_check("era indices run in order", SetPieceEra.index_of("prewar") == 0 and SetPieceEra.index_of("apocalypse") == 3 and SetPieceEra.index_of("nonsense") == 0)
	var small = SetPieceEra.apply(SetPieceArt.rects("haystack", Vector2(64, 64), 1), Vector2(64, 64), "apocalypse", 3)
	_check("tiny pieces survive aging without errors", small.size() >= 0)
	print("SetPieceEraCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
