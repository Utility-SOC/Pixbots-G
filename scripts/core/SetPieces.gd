class_name SetPieces
extends RefCounted

# The set-piece library: named building / structure kits that maps place as destructible multi-tile obstacles
# (MapGenerator.ruin_specs -> RuinObstacle, drawn by SetPieceArt). Each piece has a theme, a footprint range in tiles,
# and a weight. Tone: gothic and art-deco ruins, farm and agricultural buildings, military hardware, industrial yards -
# the clutter of a wargame table, in the spirit of FightShovel's tabletop look. Maps ask for pieces by theme(s) and the
# footprint they have room for; selection is a pure hash of the footprint's position, so it consumes no random numbers
# and never shifts a seeded map.
#
# Adding a piece: add its row here and its drawing in SetPieceArt (SetPiecesCheck fails until both exist).

const PIECES = {
	# name: {theme, min:[w,h], max:[w,h], weight, hardness (1.0 = normal hp per tile)}
	"gothic_chapel": {"theme": "gothic", "min": [3, 3], "max": [5, 4], "weight": 3, "hard": 1.0},
	"gothic_spire": {"theme": "gothic", "min": [2, 2], "max": [3, 3], "weight": 3, "hard": 1.0},
	"gothic_cathedral": {"theme": "gothic", "min": [8, 5], "max": [14, 8], "weight": 2, "hard": 1.2},
	"deco_tower": {"theme": "art_deco", "min": [2, 2], "max": [4, 4], "weight": 3, "hard": 1.1},
	"deco_hall": {"theme": "art_deco", "min": [6, 4], "max": [12, 7], "weight": 2, "hard": 1.2},
	"silo": {"theme": "agricultural", "min": [2, 2], "max": [3, 3], "weight": 3, "hard": 0.8},
	"granary": {"theme": "agricultural", "min": [3, 3], "max": [5, 4], "weight": 3, "hard": 0.8},
	"haystack": {"theme": "agricultural", "min": [2, 2], "max": [3, 2], "weight": 2, "hard": 0.4},
	"bunker": {"theme": "military", "min": [3, 2], "max": [5, 3], "weight": 3, "hard": 1.6},
	"watchtower": {"theme": "military", "min": [2, 2], "max": [2, 3], "weight": 2, "hard": 0.9},
	"hangar": {"theme": "military", "min": [6, 4], "max": [10, 6], "weight": 2, "hard": 1.0},
	"barracks": {"theme": "military", "min": [4, 2], "max": [7, 3], "weight": 3, "hard": 0.9},
	"smokestack_works": {"theme": "industrial", "min": [3, 3], "max": [5, 5], "weight": 3, "hard": 1.1},
	"fuel_tanks": {"theme": "industrial", "min": [3, 3], "max": [5, 4], "weight": 2, "hard": 0.8},
	"container_stack": {"theme": "industrial", "min": [3, 2], "max": [5, 3], "weight": 3, "hard": 0.9},
}

# Which themes each map type draws from. Maps not listed place no library pieces.
const THEMES_BY_MAP = {
	"Tabletop": ["gothic", "art_deco", "industrial", "military"],
	"FightShovel": ["agricultural"],
}

# Share of placements that keep the plain grey ruin shell (Tabletop's original look) so the table is not all new kits.
const PLAIN_RUIN_SHARE = 0.3

static func themes_for(map_type: String) -> Array:
	return THEMES_BY_MAP.get(map_type, [])

static func has_piece(name: String) -> bool:
	return PIECES.has(name)

static func names_for_theme(theme: String) -> Array:
	var out: Array = []
	for n in PIECES:
		if PIECES[n]["theme"] == theme:
			out.append(n)
	return out

# How far a w x h footprint is outside a piece's size range (0 = fits).
static func misfit(name: String, w: int, h: int) -> int:
	var p: Dictionary = PIECES[name]
	var mn: Array = p["min"]
	var mx: Array = p["max"]
	return maxi(0, int(mn[0]) - w) + maxi(0, w - int(mx[0])) + maxi(0, int(mn[1]) - h) + maxi(0, h - int(mx[1]))

# Stable 0..1 value from a footprint (position + size): no RNG involved.
static func hash01(x: int, y: int, w: int, h: int) -> float:
	return float(posmod(((x * 73856093) ^ (y * 19349663) ^ (w * 83492791) ^ (h * 2654435761)), 10007)) / 10007.0

# The style to build on a w x h footprint at (x, y) for `themes`, or "ruin" for the plain grey shell. Chooses among the
# pieces of those themes that fit best, weighted, by the footprint hash.
static func pick(themes: Array, x: int, y: int, w: int, h: int) -> String:
	if themes.is_empty():
		return "ruin"
	var h01 = hash01(x, y, w, h)
	if h01 < PLAIN_RUIN_SHARE:
		return "ruin"
	var best_gap = 1000
	for theme in themes:
		for n in names_for_theme(theme):
			best_gap = mini(best_gap, misfit(n, w, h))
	var pool: Array = []
	for theme in themes:
		for n in names_for_theme(theme):
			if misfit(n, w, h) == best_gap:
				for i in range(int(PIECES[n]["weight"])):
					pool.append(n)
	if pool.is_empty():
		return "ruin"
	var r = (h01 - PLAIN_RUIN_SHARE) / (1.0 - PLAIN_RUIN_SHARE)
	return pool[mini(pool.size() - 1, int(r * pool.size()))]

static func hardness(name: String) -> float:
	return float(PIECES[name]["hard"]) if PIECES.has(name) else 1.0
