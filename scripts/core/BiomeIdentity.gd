class_name BiomeIdentity
extends RefCounted

# What each biome does to the elements fought on it. Pure lookups (like TerrainEffects) so combat, the Synergy Codex and
# the tests read one table. Biome ints are MapGenerator.BiomeType:
#   GRASSLAND 0, WATER 1, DESERT 2, FOREST 3, TUNDRA 4, VOLCANO 5, DUNGEON 6, ROAD 7, FLOOR 8, SHALLOW 9
#
# CLIMATE scales how long Freeze and Burn last on a target standing in the biome (the ground under the victim): cold ground
# keeps ice, hot ground melts it, dry ground keeps a fire going, water douses it. It stacks with the Freeze/Stun/Shock
# Guard tiles. Beyond this table the biomes already carry: Forest + Fire burst, Water/Shallows + Lightning burst, Tundra
# traction, Volcano vents and ash, Desert oil slicks. A new map type is a mix of these pieces. All numbers (tune).
#
# VOLCANO also lets an Explosion set off a lava vent early (LavaVent.trigger): lure a squad onto a vent, then pop it.

const WATER = 1
const DESERT = 2
const FOREST = 3
const TUNDRA = 4
const VOLCANO = 5
const SHALLOW = 9

const CLIMATE = {
	TUNDRA: {"frozen": 1.5, "burning": 0.7},
	DESERT: {"frozen": 0.7, "burning": 1.2},
	VOLCANO: {"frozen": 0.6, "burning": 1.3},
	FOREST: {"burning": 1.25},
	WATER: {"burning": 0.4},
	SHALLOW: {"burning": 0.4},
}

# Statuses the climate touches (checked first so every other status skips the biome lookup).
const CLIMATE_STATUSES = ["frozen", "burning"]

static func status_mult(biome: int, status: String) -> float:
	var row = CLIMATE.get(biome)
	if row == null:
		return 1.0
	return float(row.get(status, 1.0))

# The biome under `node`, or -1 when there is no map (tests, menus).
static func biome_under(node: Node2D) -> int:
	var tree = node.get_tree() if node and node.is_inside_tree() else null
	if tree == null:
		return -1
	var maps = EntityCache.get_group("map_generator")
	if maps.size() > 0 and is_instance_valid(maps[0]) and maps[0].has_method("get_biome_at_world_pos"):
		return int(maps[0].get_biome_at_world_pos(node.global_position))
	return -1

# Duration of `status` after the ground under `node` has its say.
static func scaled_duration(node: Node2D, status: String, duration: float) -> float:
	if not (status in CLIMATE_STATUSES):
		return duration
	var biome = biome_under(node)
	return duration if biome < 0 else duration * status_mult(biome, status)
