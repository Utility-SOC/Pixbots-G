class_name BrandTileFactory
extends RefCounted

# Corporate Sponsorships (task #17): maps brand_id -> the tile script
# path(s) that brand offers. Filled in incrementally as each brand's tile(s)
# get built (see BrandRegistry.gd's header for the full design) - an empty
# or missing entry means "not built yet," so callers (LootManager) treat a
# null return as "no drop this time" rather than erroring. This lets the
# sponsorship foundation (boss affiliation, drop hooks, save/load) land and
# be verified safely ahead of the actual tile content.
const BRAND_TILE_SCRIPTS = {
	"power": [
		"res://scripts/tiles/brands/PowerGridSplitterTile.gd",
		"res://scripts/tiles/brands/PowerGridResonatorTile.gd",
	],
	"sniper": [
		"res://scripts/tiles/brands/SniperMountTile.gd",
	],
	"efficiency": [
		"res://scripts/tiles/brands/PrimeCircuitTile.gd",
	],
	"cloak": [
		"res://scripts/tiles/brands/AllyCloakTile.gd",
	],
	"sensors": [
		"res://scripts/tiles/brands/CounterJammerTile.gd",
		"res://scripts/tiles/brands/CounterCloakTile.gd",
		"res://scripts/tiles/brands/CounterBothTile.gd",
	],
}

# Rolls one of `brand_id`'s tiles at Mythic rarity, tagged brand_id for the
# dark-blue/logo render override. Returns null if that brand has no tiles
# registered yet, or brand_id is unrecognized.
static func random_tile_for_brand(brand_id: String) -> HexTile:
	var scripts: Array = BRAND_TILE_SCRIPTS.get(brand_id, [])
	if scripts.is_empty():
		return null
	var path = scripts[randi() % scripts.size()]
	var tile: HexTile = load(path).new()
	tile.rarity = HexTile.Rarity.MYTHIC
	tile.brand_id = brand_id
	return tile
