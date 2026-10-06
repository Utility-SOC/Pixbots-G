extends RefCounted

# Run cards: a PNG that carries a reproducible run (seed, map type/layout,
# optionally a frozen AI gene snapshot and a result) in an iTXt chunk, same
# mechanism as the champion/style cards. Used for the daily seed and for
# sharing a run with friends.
#
# Everything read from a card is untrusted DATA: parse() allow-lists map
# types/layouts, clamps numbers and truncates strings; the embedded genes are
# only ever handed to the normal sanitizing gene import. Nothing from a card is
# ever loaded or evaluated.

const ChampionCard = preload("res://scripts/pvp/ChampionCard.gd")
const MapScript = preload("res://scripts/core/MapGenerator.gd")

const KEYWORD = "pixbots.runcard"
const FORMAT = "pixbots-runcard-v1"
const CARDS_DIR = "user://run_cards/"
const MAX_SEED = 2147483647
const DAILY_MAP_TYPES = ["Normal", "Open Field", "Desert", "Forest", "Tundra", "Volcano", "Dungeon"]
const MAX_FILE_BYTES = 8 * 1024 * 1024
const MODES = ["daily", "custom"]

# ---- daily seed -------------------------------------------------------------

# Stable 31-bit seed for a YYYY-MM-DD date (same on every machine and platform).
static func seed_for_date(date: String) -> int:
	var h = ("pixbots-daily-" + date).sha256_buffer()
	var v = (int(h[0]) << 24) | (int(h[1]) << 16) | (int(h[2]) << 8) | int(h[3])
	v = v & 0x7FFFFFFF
	return max(1, v)

static func today_string() -> String:
	var d = Time.get_date_dict_from_system(true) # UTC, so everyone shares the day
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]

static func valid_date(date: String) -> bool:
	var re = RegEx.new()
	re.compile("^\\d{4}-\\d{2}-\\d{2}$")
	if re.search(date) == null:
		return false
	var y = int(date.substr(0, 4))
	var m = int(date.substr(5, 2))
	var d = int(date.substr(8, 2))
	return y >= 2024 and y <= 2200 and m >= 1 and m <= 12 and d >= 1 and d <= 31

# Everything derived from the date alone, so two players agree without a server.
static func daily_params(date: String) -> Dictionary:
	var s = seed_for_date(date)
	var rng = RandomNumberGenerator.new()
	rng.seed = s
	var layouts = MapScript.LAYOUTS
	return {
		"mode": "daily", "date": date, "seed": s,
		"map_type": DAILY_MAP_TYPES[rng.randi() % DAILY_MAP_TYPES.size()],
		"layout": layouts[rng.randi() % layouts.size()],
	}

# ---- card data ----------------------------------------------------------------

static func build(params: Dictionary, pilot: String, genes: Dictionary = {}, result: Dictionary = {}) -> Dictionary:
	var out = {
		"format": FORMAT,
		"mode": str(params.get("mode", "custom")),
		"date": str(params.get("date", "")),
		"seed": int(params.get("seed", 1)),
		"map_type": str(params.get("map_type", "Normal")),
		"layout": str(params.get("layout", "none")),
		"pilot": pilot.substr(0, 40),
	}
	if not genes.is_empty():
		out["genes"] = genes
	if not result.is_empty():
		out["result"] = result
	return out

# Untrusted dict -> clean card dict, or {} if unusable.
static func parse(raw) -> Dictionary:
	if not (raw is Dictionary) or str(raw.get("format", "")) != FORMAT:
		return {}
	var mode = str(raw.get("mode", "custom"))
	if not MODES.has(mode):
		return {}
	var seed_v = int(raw.get("seed", 0))
	if seed_v < 1 or seed_v > MAX_SEED:
		return {}
	var map_type = str(raw.get("map_type", ""))
	if not DAILY_MAP_TYPES.has(map_type):
		return {}
	var layout = str(raw.get("layout", "none"))
	if not MapScript.LAYOUTS.has(layout):
		return {}
	var date = str(raw.get("date", ""))
	if mode == "daily":
		if not valid_date(date):
			return {}
	else:
		date = ""
	var card = {"format": FORMAT, "mode": mode, "date": date, "seed": seed_v, "map_type": map_type, "layout": layout, "pilot": str(raw.get("pilot", "")).substr(0, 40)}
	if raw.get("genes") is Dictionary:
		card["genes"] = raw["genes"] # sanitized by the gene import, never used directly
	if raw.get("result") is Dictionary:
		var r = raw["result"]
		card["result"] = {
			"wave": clampi(int(r.get("wave", 0)), 0, 100000),
			"seconds": clampi(int(r.get("seconds", 0)), 0, 10000000),
			"kills": clampi(int(r.get("kills", 0)), 0, 100000000),
		}
	return card

# A daily card must match what the date itself produces - a hand-edited card
# can't claim "today's seed" with a different map.
static func matches_daily(card: Dictionary) -> bool:
	if card.get("mode", "") != "daily":
		return false
	var expect = daily_params(str(card["date"]))
	return int(card["seed"]) == int(expect["seed"]) and card["map_type"] == expect["map_type"] and card["layout"] == expect["layout"]

# ---- images ---------------------------------------------------------------------

# Deterministic badge from the seed (used when there is no map to preview).
static func render_badge(seed_v: int, size: int = 192) -> Image:
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_v
	var base = Color.from_hsv(rng.randf(), 0.55, 0.55)
	var accent = Color.from_hsv(fmod(base.h + 0.5, 1.0), 0.6, 0.9)
	img.fill(Color(0.08, 0.08, 0.12))
	var cells = 8
	var px = size / (cells * 2)
	for y in range(cells * 2):
		for x in range(cells):
			if rng.randf() < 0.5:
				var c = base if rng.randf() < 0.6 else accent
				img.fill_rect(Rect2i(x * px, y * px, px, px), c)
				img.fill_rect(Rect2i((cells * 2 - 1 - x) * px, y * px, px, px), c)
	return img

# Top-down preview of a generated MapGenerator (biome colours, obstacles dark).
static func render_preview(map, out_w: int = 200) -> Image:
	var out_h = int(round(float(out_w) * map.height / map.width))
	var img = Image.create(out_w, out_h, false, Image.FORMAT_RGBA8)
	var colors = {
		MapScript.BiomeType.GRASSLAND: Color(0.3, 0.55, 0.25), MapScript.BiomeType.WATER: Color(0.15, 0.3, 0.7),
		MapScript.BiomeType.DESERT: Color(0.78, 0.68, 0.4), MapScript.BiomeType.FOREST: Color(0.12, 0.38, 0.15),
		MapScript.BiomeType.TUNDRA: Color(0.82, 0.88, 0.92), MapScript.BiomeType.VOLCANO: Color(0.4, 0.2, 0.15),
		MapScript.BiomeType.DUNGEON: Color(0.3, 0.3, 0.34),
		MapScript.BiomeType.ROAD: Color(0.58, 0.47, 0.33), MapScript.BiomeType.FLOOR: Color(0.4, 0.37, 0.38), MapScript.BiomeType.SHALLOW: Color(0.45, 0.7, 0.9),
	}
	for oy in range(out_h):
		for ox in range(out_w):
			var tx = int(ox * map.width / out_w)
			var ty = int(oy * map.height / out_h)
			var c = colors.get(map.terrain[ty][tx], Color.MAGENTA)
			if map.obstacles.has(Vector2i(tx, ty)):
				c = c.darkened(0.6)
			img.set_pixel(ox, oy, c)
	return img

static func export_card(card: Dictionary, image: Image = null) -> String:
	var da = DirAccess.open("user://")
	if da and not da.dir_exists("run_cards"):
		da.make_dir("run_cards")
	var img = image if image != null else render_badge(int(card["seed"]))
	var png = img.save_png_to_buffer()
	var bytes = ChampionCard.embed_chunk(png, KEYWORD, card)
	var stamp = card["date"] if card["date"] != "" else str(card["seed"])
	var name = "%s_%s.png" % [card["mode"], stamp]
	var path = CARDS_DIR + name
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_buffer(bytes)
	f.close()
	return path

# Reads a card PNG; returns the parsed card or {}.
static func import_card(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > MAX_FILE_BYTES:
		return {}
	var bytes = f.get_buffer(f.get_length())
	f.close()
	return parse(ChampionCard.extract_chunk(bytes, KEYWORD, FORMAT))

static func list_cards(dir_path: String = CARDS_DIR) -> Array:
	var out: Array = []
	var dir = DirAccess.open(dir_path)
	if not dir:
		return out
	for file in dir.get_files():
		if file.to_lower().ends_with(".png"):
			var card = import_card(dir_path.path_join(file))
			if not card.is_empty():
				out.append({"file": file, "card": card})
	return out
