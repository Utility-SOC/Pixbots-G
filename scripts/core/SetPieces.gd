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
	"bell_tower": {"theme": "gothic", "min": [2, 3], "max": [3, 4], "weight": 2, "hard": 1.1},
	"crypt": {"theme": "gothic", "min": [3, 2], "max": [4, 3], "weight": 2, "hard": 1.5},
	"ruined_arch": {"theme": "gothic", "min": [3, 2], "max": [5, 3], "weight": 2, "hard": 1.0},
	"graveyard": {"theme": "gothic", "min": [4, 3], "max": [6, 4], "weight": 2, "hard": 0.5},
	"cinema": {"theme": "art_deco", "min": [4, 3], "max": [6, 4], "weight": 2, "hard": 1.1},
	"hotel": {"theme": "art_deco", "min": [3, 4], "max": [5, 6], "weight": 2, "hard": 1.2},
	"deco_station": {"theme": "art_deco", "min": [3, 2], "max": [4, 3], "weight": 2, "hard": 0.9},
	"apartment_block": {"theme": "urban", "min": [4, 4], "max": [6, 6], "weight": 3, "hard": 1.2},
	"office_slab": {"theme": "urban", "min": [3, 5], "max": [5, 8], "weight": 2, "hard": 1.3},
	"shop_row": {"theme": "urban", "min": [5, 2], "max": [8, 3], "weight": 3, "hard": 0.8},
	"parking_garage": {"theme": "urban", "min": [5, 3], "max": [8, 4], "weight": 2, "hard": 1.4},
	"billboard": {"theme": "urban", "min": [3, 2], "max": [4, 3], "weight": 2, "hard": 0.6},
	"tenement": {"theme": "urban", "min": [3, 4], "max": [4, 6], "weight": 3, "hard": 1.0},
	"obelisk": {"theme": "monument", "min": [2, 3], "max": [2, 4], "weight": 2, "hard": 1.6},
	"war_memorial": {"theme": "monument", "min": [3, 3], "max": [4, 4], "weight": 2, "hard": 1.5},
	"fountain": {"theme": "monument", "min": [3, 3], "max": [4, 4], "weight": 2, "hard": 0.7},
	"mausoleum": {"theme": "monument", "min": [3, 3], "max": [4, 3], "weight": 2, "hard": 1.6},
	"shrine": {"theme": "monument", "min": [2, 2], "max": [3, 3], "weight": 2, "hard": 0.7},
	"statue": {"theme": "monument", "min": [2, 2], "max": [2, 3], "weight": 2, "hard": 1.4},
	"gatehouse": {"theme": "fortification", "min": [4, 3], "max": [6, 4], "weight": 2, "hard": 1.8},
	"wall_segment": {"theme": "fortification", "min": [5, 2], "max": [8, 2], "weight": 3, "hard": 2.0},
	"corner_tower": {"theme": "fortification", "min": [2, 2], "max": [3, 3], "weight": 2, "hard": 1.6},
	"pillbox": {"theme": "fortification", "min": [2, 2], "max": [3, 2], "weight": 3, "hard": 2.0},
	"tank_traps": {"theme": "fortification", "min": [3, 2], "max": [5, 2], "weight": 3, "hard": 1.5},
	"tent_cluster": {"theme": "camp", "min": [4, 3], "max": [6, 4], "weight": 3, "hard": 0.3},
	"field_hospital": {"theme": "camp", "min": [4, 3], "max": [6, 4], "weight": 2, "hard": 0.4},
	"supply_dump": {"theme": "camp", "min": [3, 2], "max": [5, 3], "weight": 3, "hard": 0.5},
	"radar_dish": {"theme": "camp", "min": [2, 2], "max": [3, 3], "weight": 2, "hard": 0.7},
	"antenna_mast": {"theme": "camp", "min": [2, 3], "max": [2, 4], "weight": 2, "hard": 0.6},
	"pylon": {"theme": "power", "min": [2, 3], "max": [3, 4], "weight": 3, "hard": 0.6},
	"substation": {"theme": "power", "min": [3, 3], "max": [5, 4], "weight": 2, "hard": 1.0},
	"wind_turbine": {"theme": "power", "min": [3, 4], "max": [4, 5], "weight": 2, "hard": 0.6},
	"solar_array": {"theme": "power", "min": [4, 3], "max": [6, 4], "weight": 2, "hard": 0.5},
	"wrecked_tank": {"theme": "wreck", "min": [3, 2], "max": [4, 3], "weight": 3, "hard": 1.4},
	"wrecked_truck": {"theme": "wreck", "min": [3, 2], "max": [4, 2], "weight": 3, "hard": 0.8},
	"downed_aircraft": {"theme": "wreck", "min": [5, 3], "max": [8, 5], "weight": 2, "hard": 0.9},
	"derelict_railcar": {"theme": "wreck", "min": [5, 2], "max": [8, 2], "weight": 2, "hard": 1.0},
	"windmill": {"theme": "agricultural", "min": [3, 3], "max": [4, 4], "weight": 2, "hard": 0.8},
	"greenhouse": {"theme": "agricultural", "min": [4, 3], "max": [6, 4], "weight": 2, "hard": 0.3},
	"water_tower": {"theme": "agricultural", "min": [2, 3], "max": [3, 4], "weight": 2, "hard": 0.8},
	"stable": {"theme": "agricultural", "min": [4, 3], "max": [6, 4], "weight": 2, "hard": 0.8},
	"corn_crib": {"theme": "agricultural", "min": [3, 2], "max": [4, 3], "weight": 2, "hard": 0.6},
	"crane": {"theme": "industrial", "min": [4, 4], "max": [6, 6], "weight": 2, "hard": 0.7},
	"refinery_tower": {"theme": "industrial", "min": [3, 4], "max": [5, 6], "weight": 2, "hard": 1.1},
	"warehouse": {"theme": "industrial", "min": [6, 3], "max": [10, 5], "weight": 3, "hard": 1.0},
	"gasometer": {"theme": "industrial", "min": [3, 3], "max": [5, 5], "weight": 2, "hard": 1.2},
	"temple": {"theme": "ancient", "min": [5, 4], "max": [8, 6], "weight": 2, "hard": 1.3},
	"column_ruin": {"theme": "ancient", "min": [3, 2], "max": [5, 3], "weight": 3, "hard": 1.3},
	"ziggurat": {"theme": "ancient", "min": [5, 4], "max": [8, 6], "weight": 2, "hard": 1.8},
	"sandstone_arch": {"theme": "ancient", "min": [4, 3], "max": [7, 5], "weight": 2, "hard": 2.0},
	# coast, stadium, swamp, range, cave and Oz pieces (SetPieceArtD)
	"lighthouse": {"theme": "coast", "min": [2, 4], "max": [3, 6], "weight": 2, "hard": 1.3},
	"beach_hut": {"theme": "coast", "min": [2, 2], "max": [3, 3], "weight": 3, "hard": 0.4},
	"umbrella_cluster": {"theme": "coast", "min": [3, 2], "max": [5, 3], "weight": 3, "hard": 0.2},
	"landing_craft": {"theme": "coast", "min": [4, 3], "max": [6, 4], "weight": 2, "hard": 1.2},
	"grandstand": {"theme": "stadium", "min": [6, 3], "max": [10, 5], "weight": 3, "hard": 1.4},
	"scoreboard": {"theme": "stadium", "min": [3, 3], "max": [5, 4], "weight": 2, "hard": 0.8},
	"floodlight_tower": {"theme": "stadium", "min": [2, 4], "max": [3, 6], "weight": 3, "hard": 0.7},
	"stilt_house": {"theme": "swamp", "min": [3, 3], "max": [5, 4], "weight": 3, "hard": 0.6},
	"emerald_tower": {"theme": "oz", "min": [3, 5], "max": [5, 8], "weight": 3, "hard": 1.2},
	"scarecrow": {"theme": "oz", "min": [2, 3], "max": [2, 4], "weight": 3, "hard": 0.3},
	"hoodoo": {"theme": "desert_rock", "min": [3, 3], "max": [5, 5], "weight": 3, "hard": 1.6},
	"stalagmites": {"theme": "cave", "min": [3, 2], "max": [5, 4], "weight": 3, "hard": 1.4},
	"crystal_cluster": {"theme": "cave", "min": [2, 2], "max": [4, 3], "weight": 2, "hard": 1.0},
	"giant_skeleton": {"theme": "apocalypse_relic", "min": [6, 3], "max": [10, 5], "weight": 2, "hard": 0.9},
	"cooling_tower": {"theme": "power", "min": [4, 5], "max": [6, 7], "weight": 2, "hard": 1.3},
	"missile_silo": {"theme": "military", "min": [3, 3], "max": [4, 4], "weight": 2, "hard": 1.8},
	"target_dummies": {"theme": "range", "min": [4, 2], "max": [7, 3], "weight": 3, "hard": 0.3},
	"observation_tower": {"theme": "range", "min": [2, 3], "max": [3, 5], "weight": 3, "hard": 0.8},
	"hangar_door_bunker": {"theme": "range", "min": [4, 3], "max": [6, 4], "weight": 2, "hard": 1.8},
	"colonnade": {"theme": "arena", "min": [4, 2], "max": [8, 3], "weight": 3, "hard": 1.3},
	"triumphal_arch": {"theme": "arena", "min": [4, 4], "max": [6, 6], "weight": 2, "hard": 1.6},
	"gate_arch": {"theme": "arena", "min": [4, 3], "max": [6, 5], "weight": 2, "hard": 1.8},
	"geyser_cone": {"theme": "hydrothermal", "min": [2, 3], "max": [3, 4], "weight": 3, "hard": 1.5},
	# sci-fi (hyperfuturistic terrain on the same table)
	"hab_dome": {"theme": "scifi", "min": [3, 3], "max": [5, 4], "weight": 3, "hard": 0.9},
	"reactor_tower": {"theme": "scifi", "min": [2, 3], "max": [4, 5], "weight": 2, "hard": 1.3},
	"landing_pad": {"theme": "scifi", "min": [4, 3], "max": [6, 5], "weight": 2, "hard": 0.3},
	"comms_spire": {"theme": "scifi", "min": [2, 3], "max": [3, 5], "weight": 2, "hard": 0.7},
	"cryo_tanks": {"theme": "scifi", "min": [3, 2], "max": [5, 3], "weight": 2, "hard": 0.8},
	"gantry_bay": {"theme": "scifi", "min": [5, 4], "max": [8, 6], "weight": 2, "hard": 1.1},
	"force_pylon": {"theme": "scifi", "min": [2, 2], "max": [3, 3], "weight": 2, "hard": 0.9},
	"data_monolith": {"theme": "scifi", "min": [2, 3], "max": [2, 4], "weight": 2, "hard": 1.5},
	"bio_dome": {"theme": "scifi", "min": [3, 3], "max": [5, 5], "weight": 2, "hard": 0.4},
	# dungeon furniture ("indoor", D&D vibes)
	"altar": {"theme": "dungeon", "min": [2, 2], "max": [3, 2], "weight": 2, "hard": 1.4},
	"sarcophagus": {"theme": "dungeon", "min": [3, 2], "max": [4, 2], "weight": 3, "hard": 1.3},
	"throne": {"theme": "dungeon", "min": [3, 3], "max": [4, 4], "weight": 1, "hard": 1.2},
	"pillar_cluster": {"theme": "dungeon", "min": [3, 3], "max": [5, 4], "weight": 3, "hard": 1.5},
	"brazier": {"theme": "dungeon", "min": [2, 2], "max": [2, 2], "weight": 3, "hard": 0.6},
	"treasure_hoard": {"theme": "dungeon", "min": [3, 2], "max": [4, 3], "weight": 2, "hard": 0.4},
	"bookshelves": {"theme": "dungeon", "min": [3, 2], "max": [5, 2], "weight": 3, "hard": 0.7},
	"torture_rack": {"theme": "dungeon", "min": [3, 2], "max": [4, 3], "weight": 1, "hard": 0.8},
	"summoning_circle": {"theme": "dungeon", "min": [3, 3], "max": [4, 4], "weight": 1, "hard": 0.2},
	"stone_well": {"theme": "dungeon", "min": [2, 2], "max": [3, 3], "weight": 2, "hard": 1.2},
	"hearth": {"theme": "dungeon", "min": [3, 2], "max": [4, 2], "weight": 2, "hard": 1.4},
	"banquet_table": {"theme": "dungeon", "min": [4, 2], "max": [6, 3], "weight": 3, "hard": 0.7},
	"iron_cage": {"theme": "dungeon", "min": [2, 2], "max": [3, 3], "weight": 2, "hard": 1.0},
	"gargoyle": {"theme": "dungeon", "min": [2, 2], "max": [3, 3], "weight": 2, "hard": 1.4},
	# surreal
	"floating_arch": {"theme": "surreal", "min": [4, 3], "max": [6, 5], "weight": 3, "hard": 1.0},
	"stair_to_nowhere": {"theme": "surreal", "min": [3, 3], "max": [5, 5], "weight": 3, "hard": 1.1},
	"eye_pillar": {"theme": "surreal", "min": [2, 3], "max": [3, 5], "weight": 3, "hard": 1.2},
	"melting_clock": {"theme": "surreal", "min": [3, 3], "max": [4, 5], "weight": 3, "hard": 0.8},
	"lone_door": {"theme": "surreal", "min": [2, 3], "max": [3, 4], "weight": 3, "hard": 1.0},
	"chess_tower": {"theme": "surreal", "min": [2, 3], "max": [3, 5], "weight": 2, "hard": 1.3},
	"balloon_house": {"theme": "surreal", "min": [3, 4], "max": [5, 6], "weight": 2, "hard": 0.6},
	"cloud_pedestal": {"theme": "surreal", "min": [3, 2], "max": [5, 3], "weight": 2, "hard": 0.3},
	"upside_down_spire": {"theme": "surreal", "min": [2, 2], "max": [3, 4], "weight": 3, "hard": 1.1},
	"mirror_chapel": {"theme": "surreal", "min": [3, 4], "max": [5, 6], "weight": 2, "hard": 1.1},
	"hourglass_tower": {"theme": "surreal", "min": [2, 4], "max": [4, 6], "weight": 3, "hard": 1.1},
	"inverted_cathedral": {"theme": "surreal", "min": [8, 5], "max": [12, 8], "weight": 1, "hard": 1.2},
	"twin_obelisks": {"theme": "surreal", "min": [4, 3], "max": [6, 5], "weight": 2, "hard": 1.4},
	"sky_fortress": {"theme": "surreal", "min": [4, 5], "max": [6, 7], "weight": 2, "hard": 1.2},
	# mixed-genre kitbashes (terrain from a dozen different games on one table)
	"keep_reactor": {"theme": "kitbash", "min": [3, 5], "max": [4, 7], "weight": 3, "hard": 1.3},
	"hab_chapel": {"theme": "kitbash", "min": [5, 3], "max": [7, 4], "weight": 3, "hard": 1.0},
	"dome_cathedral": {"theme": "kitbash", "min": [4, 5], "max": [6, 8], "weight": 2, "hard": 1.0},
	"castle_launchpad": {"theme": "kitbash", "min": [5, 4], "max": [8, 6], "weight": 3, "hard": 0.9},
	"fortress_works": {"theme": "kitbash", "min": [4, 4], "max": [6, 6], "weight": 2, "hard": 1.5},
	"tank_cathedral": {"theme": "kitbash", "min": [4, 4], "max": [6, 6], "weight": 2, "hard": 1.3},
	"deco_bunker": {"theme": "kitbash", "min": [3, 4], "max": [5, 5], "weight": 3, "hard": 1.6},
	"pylon_chapel": {"theme": "kitbash", "min": [5, 3], "max": [7, 4], "weight": 2, "hard": 1.0},
	"silo_monolith": {"theme": "kitbash", "min": [4, 3], "max": [6, 4], "weight": 2, "hard": 1.2},
	"cathedral_hangar": {"theme": "kitbash", "min": [8, 6], "max": [12, 9], "weight": 1, "hard": 1.2},
	"temple_reactor": {"theme": "kitbash", "min": [5, 6], "max": [8, 9], "weight": 1, "hard": 1.4},
	# evolved farm buildings: reached through SetPieces.evolved as a war drags on, never picked directly
	"gothic_silo": {"theme": "evolved", "min": [2, 3], "max": [3, 4], "weight": 0, "hard": 1.0},
	"deco_silo": {"theme": "evolved", "min": [2, 3], "max": [3, 4], "weight": 0, "hard": 1.0},
	"granary_chapel": {"theme": "evolved", "min": [3, 4], "max": [5, 5], "weight": 0, "hard": 1.0},
	"cathedral_barn": {"theme": "evolved", "min": [3, 3], "max": [7, 6], "weight": 0, "hard": 1.1},
	"windmill_spire": {"theme": "evolved", "min": [4, 3], "max": [6, 4], "weight": 0, "hard": 1.0},
	"haystack_shrine": {"theme": "evolved", "min": [2, 2], "max": [3, 3], "weight": 0, "hard": 0.8},
	"deco_stable": {"theme": "evolved", "min": [4, 3], "max": [6, 5], "weight": 0, "hard": 1.0},
}

# Which themes each map type draws from. Maps not listed place no library pieces.
const THEMES_BY_MAP = {
	"Tabletop": ["gothic", "art_deco", "industrial", "military", "urban", "monument", "fortification", "camp", "power", "wreck"],
	"FightShovel": ["agricultural", "power", "wreck", "camp"],
	# not placed yet: "ancient" (temple, column ruin, ziggurat, sandstone arch) is for the Desert-with-arches map.
}

# Share of placements that keep the plain grey ruin shell (Tabletop's original look) so the table is not all new kits.
const PLAIN_RUIN_SHARE = 0.3

# How buildings change as a war drags on: [prewar, skirmish, no_mans_land, apocalypse]. Farm buildings turn gothic or art
# deco, as if the land itself were mutating (owner: "some of the agricultural stuff should become more art deco/gothic as it
# progresses"). Styles not listed never change (the era's wear and tear still applies to them).
const EVOLUTION = {
	"silo": ["silo", "silo", "deco_silo", "gothic_silo"],
	"granary": ["granary", "granary", "granary_chapel", "cathedral_barn"],
	"windmill": ["windmill", "windmill", "windmill_spire", "windmill_spire"],
	"haystack": ["haystack", "haystack", "haystack", "haystack_shrine"],
	"stable": ["stable", "stable", "deco_stable", "deco_stable"],
	"barn": ["barn", "barn", "granary_chapel", "cathedral_barn"],
	"farmhouse": ["farmhouse", "farmhouse", "gothic_chapel", "gothic_chapel"],
	"water_tower": ["water_tower", "water_tower", "deco_tower", "gothic_spire"],
	"greenhouse": ["greenhouse", "greenhouse", "bio_dome", "dome_cathedral"],
}

static func evolved(style: String, era: String) -> String:
	if not EVOLUTION.has(style):
		return style
	return EVOLUTION[style][SetPieceEra.index_of(era)]

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
static func pick(themes: Array, x: int, y: int, w: int, h: int, plain_share: float = PLAIN_RUIN_SHARE) -> String:
	if themes.is_empty():
		return "ruin"
	var h01 = hash01(x, y, w, h)
	if h01 < plain_share:
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
	var r = (h01 - plain_share) / maxf(0.0001, 1.0 - plain_share)
	return pool[mini(pool.size() - 1, int(r * pool.size()))]

# A weighted random piece from `themes` (r01 is the caller's 0..1 roll) and a random footprint inside its size range.
static func random_piece(themes: Array, r01: float) -> String:
	var pool: Array = []
	for theme in themes:
		for n in names_for_theme(theme):
			for i in range(int(PIECES[n]["weight"])):
				pool.append(n)
	if pool.is_empty():
		return "ruin"
	return pool[mini(pool.size() - 1, int(r01 * float(pool.size())))]

static func random_size(name: String, r1: float, r2: float) -> Vector2i:
	var p: Dictionary = PIECES[name]
	var mn: Array = p["min"]
	var mx: Array = p["max"]
	return Vector2i(int(mn[0]) + int(r1 * float(int(mx[0]) - int(mn[0]) + 1)), int(mn[1]) + int(r2 * float(int(mx[1]) - int(mn[1]) + 1)))

static func hardness(name: String) -> float:
	return float(PIECES[name]["hard"]) if PIECES.has(name) else 1.0
