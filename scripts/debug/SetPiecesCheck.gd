extends Node

# The set-piece library: every catalogued piece has art and every art style has a catalogue row; art is deterministic,
# non-empty and stays inside the footprint at the smallest and largest sizes; style selection is a pure hash (it never
# touches the random number generators), respects themes and size, and keeps a share of plain ruins.

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	var art = SetPieceArt.all_styles()
	var cat = SetPieces.PIECES.keys()
	var missing_art = cat.filter(func(n): return not (n in art))
	var missing_row = art.filter(func(n): return not SetPieces.has_piece(n))
	_check("every piece has art (%s)" % str(missing_art), missing_art.is_empty())
	_check("every art style has a catalogue row (%s)" % str(missing_row), missing_row.is_empty())
	_check("the library is broad: at least 60 pieces over 10+ themes (%d / %d)" % [cat.size(), _themes().size()], cat.size() >= 60 and _themes().size() >= 10)

	var bad = []
	for n in cat:
		var p: Dictionary = SetPieces.PIECES[n]
		for sz in [p["min"], p["max"]]:
			var fp = Vector2(int(sz[0]) * 32, int(sz[1]) * 32)
			var rs = SetPieceArt.rects(n, fp, 12345)
			var again = SetPieceArt.rects(n, fp, 12345)
			if rs.size() < 5:
				bad.append(n + " too few rects")
			if rs.size() != again.size():
				bad.append(n + " not deterministic")
			for r in rs:
				var rc: Rect2 = r[0]
				if rc.position.x < 0.0 or rc.position.y < 0.0 or rc.end.x > fp.x + 0.01 or rc.end.y > fp.y + 0.01 or rc.size.x <= 0.0 or rc.size.y <= 0.0:
					bad.append("%s out of bounds %s in %s" % [n, str(rc), str(fp)])
					break
	_check("art is non-empty, deterministic and inside the footprint (%s)" % str(bad), bad.is_empty())

	var rng_before = SimRng.stream("combat").state
	var picks := {}
	var plain = 0
	var total = 0
	for x in range(3, 60, 3):
		for y in range(3, 30, 3):
			for sz in [[2, 2], [4, 3], [6, 4], [10, 6], [12, 7]]:
				var s = SetPieces.pick(["gothic", "art_deco", "industrial", "military"], x, y, sz[0], sz[1])
				picks[s] = true
				total += 1
				if s == "ruin":
					plain += 1
	_check("selection never touches the RNG streams", SimRng.stream("combat").state == rng_before)
	_check("selection is stable", SetPieces.pick(["gothic"], 7, 9, 5, 4) == SetPieces.pick(["gothic"], 7, 9, 5, 4))
	var share = float(plain) / float(total)
	_check("about a third of placements stay plain ruins (%.2f)" % share, share > 0.2 and share < 0.4)
	var tt = SetPieces.themes_for("Tabletop")
	var unreachable = []
	for n in cat:
		if not (SetPieces.PIECES[n]["theme"] in tt):
			continue
		var p2: Dictionary = SetPieces.PIECES[n]
		var seen = false
		for k in range(300):
			if SetPieces.pick(tt, 3 + k * 7, 5 + k * 3, int(p2["min"][0]), int(p2["min"][1])) == n:
				seen = true
				break
		if not seen:
			unreachable.append(n)
	_check("every Tabletop piece can be placed at its own size (%s)" % str(unreachable), unreachable.is_empty())
	_check("no themes means a plain ruin", SetPieces.pick([], 5, 5, 4, 4) == "ruin")
	var agri_ok = true
	for x in range(3, 40, 3):
		var s2 = SetPieces.pick(["agricultural"], x, 11, 4, 3)
		if s2 != "ruin" and SetPieces.PIECES[s2]["theme"] != "agricultural":
			agri_ok = false
	_check("agricultural maps only get agricultural pieces", agri_ok)
	_check("big footprints get the big kits", ["gothic_cathedral", "ruin"].has(SetPieces.pick(["gothic"], 10, 10, 12, 7)))
	_check("maps without a theme list place no library pieces", SetPieces.themes_for("Desert").is_empty() and not SetPieces.themes_for("Tabletop").is_empty())
	print("SetPiecesCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _themes() -> Array:
	var t := {}
	for n in SetPieces.PIECES:
		t[SetPieces.PIECES[n]["theme"]] = true
	return t.keys()
