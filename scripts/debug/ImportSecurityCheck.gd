extends Node

# Hostile-input regression for every import path: saves/loadouts/cards must
# never load arbitrary scripts, blow up on oversized data, or accept values
# of the wrong shape.

const ChampionCard = preload("res://scripts/pvp/ChampionCard.gd")
const GenePool = preload("res://scripts/ai/GenePool.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	var sm = SaveManager
	# --- script_path allow-list ---
	var good = ["res://scripts/tiles/CoreTile.gd", "res://scripts/tiles/AmplifierTile.gd", "res://scripts/core/HexTile.gd"]
	for p in good:
		_check("allows " + p, sm.is_allowed_tile_script(p))
	var bad = ["res://scripts/debug/BossAbilityCheck.gd", "res://scripts/core/Main.gd", "res://scripts/core/SaveManager.gd",
		"user://evil.gd", "/etc/passwd", "res://scripts/tiles/../core/Main.gd", "res://scripts/tiles/Nope.gd",
		"res://main.tscn", "res://scripts/tiles/CoreTile.tscn", "", "res://scripts/tiles/sub/Deep.gd", "http://x/y.gd", 42, null, ["a"], {"a": 1}]
	for p in bad:
		_check("refuses %s" % str(p).substr(0, 40), not sm.is_allowed_tile_script(p))
	_check("refuses non-tile script in tiles dir naming (not extending HexTile)", not sm.is_allowed_tile_script("res://scripts/tiles/../ai/GenePool.gd"))

	# every shipped tile script must remain loadable from saves
	var rejected: Array = []
	var stack = ["res://scripts/tiles/"]
	var checked = 0
	while not stack.is_empty():
		var d = stack.pop_back()
		var dir = DirAccess.open(d)
		for sub in dir.get_directories():
			stack.append(d + sub + "/")
		for f in dir.get_files():
			if f.ends_with(".gd"):
				checked += 1
				if not sm.is_allowed_tile_script(d + f):
					rejected.append(d + f)
	_check("walked tile scripts incl. subfolders (%d)" % checked, checked > 40)
	_check("all shipped tile scripts allowed (rejected: %s)" % str(rejected), rejected.is_empty())

	# --- tile deserialization ---
	_check("hostile script_path yields no tile", sm._deserialize_tile({"script_path": "res://scripts/core/Main.gd"}) == null)
	_check("user:// script yields no tile", sm._deserialize_tile({"script_path": "user://evil.gd"}) == null)
	var t = sm._deserialize_tile({"script_path": "res://scripts/tiles/CoreTile.gd", "tile_type": "Core Reactor", "rarity": 99, "active_faces": [0, 1, 2, 3, 4, 5, 6, 7, 8, 99, -4], "face_outputs": {"1": 3, "99": 4, "-5": 1}, "footprint_offsets": [{"x": 99999, "y": -99999}, "junk", 5]})
	_check("good tile still loads", t != null)
	if t != null:
		_check("rarity clamped", t.rarity >= 0 and t.rarity <= 4)
		_check("faces capped and clamped", t.active_faces.size() <= 6 and t.active_faces.all(func(f): return f >= 0 and f <= 5))
		_check("face_outputs keys clamped", t.face_outputs.keys().all(func(k): return k >= 0 and k <= 5))
		_check("footprint clamped, junk skipped", t.footprint_offsets.size() <= 1 and t.footprint_offsets.all(func(o): return abs(o.x) <= 8 and abs(o.y) <= 8))
	var tm = sm._deserialize_tile({"script_path": "res://scripts/tiles/AmplifierTile.gd", "tile_type": "Amplifier", "rarity": 1, "gate_every_n": {"evil": 1}, "output_ratios": "text"})
	_check("type-mismatched props ignored", tm != null)

	# --- component caps / shapes ---
	var many = []
	for i in range(3000):
		many.append({"script_path": "res://scripts/tiles/AmplifierTile.gd", "tile_type": "Amplifier", "q": i, "r": 0})
	var comp = sm._deserialize_component({"slot_type": 1, "rarity": 99, "tiles": many, "valid_hexes": [{"q": 1, "r": 1}, "junk", {"q": 1e12}, {"q": 5, "r": 5}], "fixed_sinks": [1, 2, {"q": 1, "r": 1}]})
	_check("component builds from hostile data", comp != null)
	if comp != null:
		_check("tile count capped (%d)" % comp.hex_grid.get_all_tiles().size(), comp.hex_grid.get_all_tiles().size() <= sm.MAX_TILES_PER_COMPONENT)
		_check("rarity clamped on component", comp.rarity >= 0 and comp.rarity <= 4)
	comp = sm._deserialize_component({"slot_type": "x", "tiles": "notalist", "valid_hexes": 5})
	_check("wrong-typed fields don't crash", comp != null)

	# drone bay recursion
	var nest = {"slot_type": 8, "tiles": []}
	for i in range(50):
		nest = {"slot_type": 8, "tiles": [{"script_path": "res://scripts/tiles/DroneBayTile.gd", "tile_type": "Drone Bay", "q": 0, "r": 0, "drone_loadout": nest}]}
	var deep = sm._deserialize_component(nest)
	_check("deeply nested drone loadouts bounded", deep != null and sm._deser_depth == 0)

	# --- champion card payload ---
	var raw = {"format": ChampionCard.PAYLOAD_FORMAT, "pilot_name": "A".repeat(300), "rank": 1e30, "max_wave": -9, "created_unix": 1e30,
		"components": {"1": {"slot_type": 1}, "99": {"x": 1}, "evil": {}, "2": "str"}, "extra": {"script": "res://x"}}
	var clean = ChampionCard.sanitize_payload(raw)
	_check("payload sanitized", not clean.is_empty() and clean["pilot_name"].length() <= 40 and clean["rank"] <= ChampionCard.MAX_RANK and clean["max_wave"] == 0)
	_check("only valid component slots kept", clean["components"].keys() == ["1"])
	_check("unknown keys dropped", not clean.has("extra"))
	_check("wrong format rejected", ChampionCard.sanitize_payload({"format": "x", "components": {"1": {}}}).is_empty())
	_check("no components rejected", ChampionCard.sanitize_payload({"format": ChampionCard.PAYLOAD_FORMAT, "components": {}}).is_empty())

	# --- PNG chunk reader ---
	var img = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	var png = img.save_png_to_buffer()
	var big_len = png.duplicate()
	big_len[8] = 0xFF
	big_len[9] = 0xFF
	big_len[10] = 0xFF
	big_len[11] = 0xFF
	_check("0xFFFFFFFF chunk length fails closed", ChampionCard.extract_payload(big_len).is_empty())
	var tiny = PackedByteArray([0x89, 0x50])
	_check("tiny buffer fails closed", ChampionCard.extract_payload(tiny).is_empty() and ChampionCard.extract_genes(PackedByteArray()).is_empty())
	var nested = ChampionCard.embed_chunk(png, ChampionCard.CHUNK_KEYWORD, {"format": ChampionCard.PAYLOAD_FORMAT, "components": {"1": {"slot_type": 1}}, "pilot_name": 5})
	_check("non-string pilot_name tolerated", not ChampionCard.sanitize_payload(ChampionCard.extract_payload(nested)).is_empty())

	# ghost id path safety
	ChampionCard.record_result("../../evil", true)
	_check("record_result refuses traversal ids", not FileAccess.file_exists("user://../evil.json"))

	print("import security check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
