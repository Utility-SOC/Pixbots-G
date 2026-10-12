class_name MapTypes
extends RefCounted

# Registry of the data-driven map types built by MapKits (Urban, Lakelands, Islands, Beach, Swamp, Poppy Fields, Colosseum,
# Sports Arena, Hydrothermal Park, Desert Arches, Dense Forest, Munitions Range, Military Base, Caves, Crypt, Keep, Dreamscape).
# The older hand-built types (Normal, Forest, Desert, Tabletop, FightShovel, ...) stay in MapGenerator.
#
# Every map also has a WAR ERA (see SetPieceEra): prewar (everything is great), skirmish (some decay), no_mans_land,
# apocalypse. The era ages the set pieces, tints the ground, and changes what is on the map (a resort beach before the
# war becomes a Normandy landing during it).

const ERAS = ["prewar", "skirmish", "no_mans_land", "apocalypse"]

# size: tiles; tint: ground colour multiplier; era_weights: chance of each era when none is forced; hazards: which
# MapGenerator hazard scatters apply ("oil", "vents"); music: the ProceduralMusic biome key to borrow.
const TYPES = {
	"Urban": {"size": Vector2i(400, 250), "tint": Color(0.92, 0.94, 1.0), "era_weights": [3, 3, 2, 1], "hazards": [], "music": "Normal"},
	"Lakelands": {"size": Vector2i(400, 250), "tint": Color(0.95, 1.0, 1.0), "era_weights": [4, 2, 1, 1], "hazards": [], "music": "Forest"},
	"Islands": {"size": Vector2i(400, 250), "tint": Color(0.95, 1.0, 1.0), "era_weights": [4, 2, 1, 1], "hazards": [], "music": "Water"},
	"Beach": {"size": Vector2i(400, 250), "tint": Color(1.0, 0.98, 0.94), "era_weights": [3, 1, 4, 1], "hazards": [], "music": "Desert"},
	"Swamp": {"size": Vector2i(400, 250), "tint": Color(0.8, 0.92, 0.75), "era_weights": [2, 2, 1, 3], "hazards": [], "music": "Forest"},
	"Poppy Fields": {"size": Vector2i(400, 250), "tint": Color(1.0, 0.98, 0.95), "era_weights": [3, 1, 4, 1], "hazards": [], "music": "FightShovel"},
	"Colosseum": {"size": Vector2i(220, 160), "tint": Color(1.0, 0.96, 0.9), "era_weights": [4, 2, 1, 2], "hazards": [], "music": "Dungeon"},
	"Sports Arena": {"size": Vector2i(260, 180), "tint": Color(0.95, 1.0, 0.95), "era_weights": [4, 2, 2, 2], "hazards": [], "music": "Normal"},
	"Hydrothermal Park": {"size": Vector2i(400, 250), "tint": Color(1.0, 1.0, 0.97), "era_weights": [4, 1, 1, 2], "hazards": [], "music": "Tundra"},
	"Desert Arches": {"size": Vector2i(400, 250), "tint": Color(1.0, 0.94, 0.88), "era_weights": [4, 1, 1, 3], "hazards": [], "music": "Desert"},
	"Dense Forest": {"size": Vector2i(400, 250), "tint": Color(0.85, 0.95, 0.85), "era_weights": [4, 2, 2, 2], "hazards": [], "music": "Forest"},
	"Munitions Range": {"size": Vector2i(400, 250), "tint": Color(1.0, 0.97, 0.9), "era_weights": [1, 4, 3, 2], "hazards": [], "music": "Desert"},
	"Military Base": {"size": Vector2i(400, 250), "tint": Color(0.95, 0.97, 0.92), "era_weights": [3, 3, 2, 2], "hazards": [], "music": "Normal"},
	"Caves": {"size": Vector2i(300, 200), "tint": Color(0.7, 0.75, 0.95), "era_weights": [1, 1, 1, 1], "hazards": [], "music": "Dungeon"},
	"Crypt": {"size": Vector2i(300, 200), "tint": Color(0.75, 0.8, 0.85), "era_weights": [1, 1, 1, 1], "hazards": [], "music": "Dungeon"},
	"Keep": {"size": Vector2i(300, 200), "tint": Color(0.95, 0.88, 0.8), "era_weights": [3, 2, 1, 2], "hazards": [], "music": "Dungeon"},
	"Dreamscape": {"size": Vector2i(400, 250), "tint": Color(1.0, 0.9, 1.0), "era_weights": [1, 1, 1, 1], "hazards": [], "music": "Tundra"},
}

# Ground tint per era (multiplied with the map type's own tint).
const ERA_TINT = {
	"prewar": Color(1.0, 1.0, 1.0),
	"skirmish": Color(0.96, 0.94, 0.9),
	"no_mans_land": Color(0.84, 0.8, 0.72),
	"apocalypse": Color(0.74, 0.74, 0.66),
}

static func has(map_type: String) -> bool:
	return TYPES.has(map_type)

static func names() -> Array:
	return TYPES.keys()

static func size(map_type: String) -> Vector2i:
	return TYPES[map_type]["size"]

static func tint(map_type: String, era: String) -> Color:
	if not TYPES.has(map_type):
		return Color.WHITE
	return TYPES[map_type]["tint"] * ERA_TINT.get(era, Color.WHITE)

static func hazard_allowed(map_type: String, hazard: String) -> bool:
	if not TYPES.has(map_type):
		return true
	return hazard in TYPES[map_type]["hazards"]

# How fast fire spreads between trees on a map (see TreeObstacle): Dense Forest burns easily; dry and wet maps vary.
static func fire_spread(map_type: String) -> float:
	match map_type:
		"Dense Forest": return 1.4
		"Swamp", "Lakelands", "Islands", "Hydrothermal Park": return 0.5
		"Desert Arches": return 1.2
	return 1.0

static func music_key(map_type: String) -> String:
	return TYPES[map_type]["music"] if TYPES.has(map_type) else map_type

# Weighted era roll from a 0..1 random value (the caller supplies it from the seeded map stream).
static func roll_era(map_type: String, r01: float) -> String:
	var w: Array = TYPES[map_type]["era_weights"] if TYPES.has(map_type) else [1, 1, 1, 1]
	var total = 0.0
	for x in w:
		total += float(x)
	var acc = 0.0
	for i in range(w.size()):
		acc += float(w[i]) / total
		if r01 <= acc:
			return ERAS[i]
	return ERAS[ERAS.size() - 1]
