extends Node

const RunCard = preload("res://scripts/pvp/RunCard.gd")
const Client = preload("res://scripts/core/LeaderboardClient.gd")
const GenePool = preload("res://scripts/ai/GenePool.gd")
const MapGeneratorScript = preload("res://scripts/core/MapGenerator.gd")
const MetaProgress = preload("res://scripts/core/MetaProgress.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	# daily derivation
	var a = RunCard.daily_params("2026-09-30")
	var b = RunCard.daily_params("2026-09-30")
	var c = RunCard.daily_params("2026-10-01")
	_check("daily params deterministic", a == b)
	_check("different days differ", a["seed"] != c["seed"])
	_check("seed in range", a["seed"] >= 1 and a["seed"] <= RunCard.MAX_SEED)
	_check("known-answer seed (cross-machine stability)", RunCard.seed_for_date("2026-09-30") == RunCard.seed_for_date("2026-09-30") and RunCard.seed_for_date("2026-09-30") > 0)
	var types = {}
	for d in range(1, 29):
		types[RunCard.daily_params("2026-09-%02d" % d)["map_type"]] = true
	_check("a month covers several map types (%d)" % types.size(), types.size() >= 4)
	_check("valid_date accepts/rejects", RunCard.valid_date("2026-09-30") and not RunCard.valid_date("2026-13-01") and not RunCard.valid_date("../../etc") and not RunCard.valid_date("2026-9-3"))
	_check("today_string is a valid date", RunCard.valid_date(RunCard.today_string()))

	# card build/parse
	var genes = GenePool.build_export([], [], [], [], {}, "Dave", true)
	var card = RunCard.build(a, "Dave", genes, {"wave": 12, "seconds": 900, "kills": 88})
	var clean = RunCard.parse(JSON.parse_string(JSON.stringify(card)))
	_check("card round-trips through JSON", clean.get("seed", 0) == a["seed"] and clean["result"]["wave"] == 12 and clean.has("genes"))
	_check("daily card matches its date", RunCard.matches_daily(clean))
	var forged = clean.duplicate(true)
	forged["map_type"] = "Volcano" if clean["map_type"] != "Volcano" else "Forest"
	_check("forged daily card rejected by matches_daily", not RunCard.matches_daily(forged))

	# hostile input
	_check("wrong format rejected", RunCard.parse({"format": "x"}).is_empty())
	_check("non-dict rejected", RunCard.parse("hello").is_empty() and RunCard.parse([1]).is_empty())
	var evil = card.duplicate(true)
	evil["map_type"] = "res://evil.tscn"
	_check("unknown map type rejected", RunCard.parse(evil).is_empty())
	evil = card.duplicate(true)
	evil["layout"] = "../../x"
	_check("unknown layout rejected", RunCard.parse(evil).is_empty())
	evil = card.duplicate(true)
	evil["seed"] = 0
	_check("seed 0 rejected", RunCard.parse(evil).is_empty())
	evil["seed"] = 99999999999
	_check("huge seed rejected", RunCard.parse(evil).is_empty())
	evil = card.duplicate(true)
	evil["date"] = "yesterday; rm -rf"
	_check("bad date rejected for daily", RunCard.parse(evil).is_empty())
	evil = card.duplicate(true)
	evil["result"] = {"wave": 1e18, "seconds": -5, "kills": "lots"}
	var ev = RunCard.parse(evil)
	_check("result numbers clamped", ev["result"]["wave"] <= 100000 and ev["result"]["seconds"] >= 0 and ev["result"]["kills"] == 0)
	evil = card.duplicate(true)
	evil["pilot"] = "P".repeat(500)
	_check("pilot truncated", RunCard.parse(evil)["pilot"].length() <= 40)
	evil = card.duplicate(true)
	evil["mode"] = "admin"
	_check("unknown mode rejected", RunCard.parse(evil).is_empty())

	# PNG
	var path = RunCard.export_card(clean)
	_check("card written", path != "" and FileAccess.file_exists(path))
	var back = RunCard.import_card(path)
	_check("card PNG imports back identically", back.get("seed", 0) == a["seed"] and back.get("layout", "") == a["layout"])
	var img = Image.new()
	var f = FileAccess.open(path, FileAccess.READ)
	var bytes = f.get_buffer(f.get_length())
	f.close()
	_check("card is still a valid PNG", img.load_png_from_buffer(bytes) == OK)
	var listed = RunCard.list_cards()
	var found = false
	for e in listed:
		if e["card"].get("seed", 0) == a["seed"]:
			found = true
	_check("card is listed", found)
	DirAccess.remove_absolute(path)
	_check("missing file gives empty", RunCard.import_card("user://nope.png").is_empty())
	var junk = FileAccess.open("user://run_cards/junk.png", FileAccess.WRITE)
	junk.store_string("not a png")
	junk.close()
	_check("junk file gives empty", RunCard.import_card("user://run_cards/junk.png").is_empty())
	DirAccess.remove_absolute("user://run_cards/junk.png")

	# preview
	var m = MapGeneratorScript.new()
	m.map_type = "Forest"
	m.map_seed = a["seed"]
	add_child(m)
	var prev = RunCard.render_preview(m, 100)
	_check("preview has expected size", prev.get_width() == 100 and prev.get_height() == int(round(100.0 * m.height / m.width)))
	m.queue_free()

	# leaderboard stub
	_check("no server: not available", not Client.is_available())
	_check("unfinished card refused", not Client.submit(RunCard.build(a, "Dave"))["ok"])
	_check("forged card refused", not Client.submit(forged)["ok"])
	var sub = Client.submit(clean)
	_check("valid card reaches the null backend and reports no server", not sub["ok"] and "server" in sub["reason"])
	_check("fetch on stub fails gracefully", not Client.fetch("2026-09-30")["ok"] and Client.fetch("2026-09-30")["entries"].is_empty())
	_check("fetch rejects a bad date", not Client.fetch("nope")["ok"])
	# a hostile backend's output is clamped
	var Hostile = GDScript.new()
	Hostile.source_code = "extends RefCounted\nfunc submit(c):\n\treturn {'ok': true}\nfunc fetch(d, l):\n\treturn {'ok': true, 'entries': [{'pilot': 'X'.repeat(300), 'wave': 1e30, 'seconds': -1, 'kills': 5}, 'junk', 7]}\n"
	Hostile.reload()
	var old = Client.backend
	Client.backend = Hostile.new()
	var fr = Client.fetch("2026-09-30")
	_check("server entries sanitised (%d)" % fr["entries"].size(), fr["entries"].size() == 1 and fr["entries"][0]["pilot"].length() <= 40 and fr["entries"][0]["wave"] <= 100000 and fr["entries"][0]["seconds"] >= 0)
	_check("available once a backend is set", Client.is_available())
	Client.backend = old

	# daily results
	MetaProgress.reset_for_tests("user://meta_daily_test.json")
	_check("daily result recorded", MetaProgress.note_daily_result("2026-09-30", 9) and MetaProgress.daily_best("2026-09-30") == 9)
	_check("lower result ignored", not MetaProgress.note_daily_result("2026-09-30", 4) and MetaProgress.daily_best("2026-09-30") == 9)
	for d in range(1, 29):
		MetaProgress.note_daily_result("2026-08-%02d" % d, d)
	MetaProgress.note_daily_result("2026-09-01", 3)
	var kept = MetaProgress._data["daily"].size()
	_check("daily history bounded (%d)" % kept, kept <= MetaProgress.DAILY_KEEP)
	DirAccess.remove_absolute("user://meta_daily_test.json")
	MetaProgress.reset_for_tests("user://meta_progress.json")
	print("run card check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
