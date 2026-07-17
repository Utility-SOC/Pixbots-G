class_name PowerGridSplitterTile
extends SplitterTile

# Corporate Sponsorships (task #17): Gridwork Distribution's signature tile -
# every one of their Splitters doubles as a flat 0.5x amplifier
# ("all of their splitters are .5 amplifier" - locked design). Applied once to the incoming
# packet BEFORE delegating to SplitterTile.process_energy(), so every output
# branch (equal-split or Mythic ratio-weighted) inherits the boosted
# magnitude/synergies, same as if a real Amplifier tile had fed this one.

const POWER_GRID_AMPLIFY_BONUS = 0.5

# Deliberately does NOT override tile_type away from "Splitter" (inherited
# as-is) - a lot of code keys off that exact string (disable-priority
# scanning in HexTile.get_disable_risk()/Mech._find_disable_priority_tile(),
# fill-paint template matching in GarageInventoryPanel, grid rendering) and
# this tile needs to keep working as a real Splitter everywhere those checks
# happen. brand_id alone (set by BrandTileFactory) is what marks it as a
# Gridwork Distribution tile for rendering/loot purposes.
func _init():
	super._init()

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	packet.amplify(1.0 + POWER_GRID_AMPLIFY_BONUS)
	return super.process_energy(packet, entry_direction, grid, entry_coord)
