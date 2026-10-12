class_name AutoScrap
extends RefCounted

# Trash converts to scrap on pickup (owner: "most of the loot you get is trash ... the huge volumes are not a problem, they just
# need to be converted to scrap"). Tiles and parts at or below the chosen rarity that you have already discovered turn into
# scrap the moment you walk over them, so the Garage inventory stays for things that matter. New tile types are never
# converted (you want to see them), and rarer drops are untouched. Setting: Settings > Visuals > Auto-scrap on pickup.

const MODE_NAMES = ["Off", "Common", "Common + Uncommon", "Up to Rare"]
const MODE_MAX_RARITY = [-1, 0, 1, 2]
const COMPONENT_SCRAP = [30, 75, 225, 750, 3000] # per part rarity: Common .. Mythic

static func max_rarity() -> int:
	return MODE_MAX_RARITY[clampi(SaveManager.auto_scrap_mode, 0, MODE_MAX_RARITY.size() - 1)]

static func tile_scrap_value(rarity: int) -> int:
	match rarity:
		1: return 25
		2: return 75
		3: return 250
		4: return 1000
	return 10 # mirrors GarageMenu.tile_scrap_value

static func should_scrap_tile(rarity: int, discovered: bool, mode_max: int) -> bool:
	return mode_max >= 0 and discovered and rarity <= mode_max

static func should_scrap_component(rarity: int, mode_max: int) -> bool:
	return mode_max >= 0 and rarity <= mode_max

static func component_value(rarity: int) -> int:
	return COMPONENT_SCRAP[clampi(rarity, 0, COMPONENT_SCRAP.size() - 1)]
