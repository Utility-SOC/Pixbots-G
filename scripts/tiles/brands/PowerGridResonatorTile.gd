class_name PowerGridResonatorTile
extends ResonatorTile

# Corporate Sponsorships (task #17): Gridwork Distribution's SECOND tile
# (Status.md design note - "the only faction that offers two types of tile,"
# to bring their overall kit up to par with the denser combo tiles other
# brands got). An "enhanced Resonator": normal Resonator behavior (baseline
# amplify + Mythic Sync, unchanged - see ResonatorTile.process_energy) plus
# a flat extra amplify pass on top, same "base behavior + flat bonus" shape
# as PowerGridSplitterTile's own signature tile.
#
# tile_type stays "Resonator" (inherited, not overridden) - see
# PowerGridSplitterTile.gd's comment for why that matters (disable-priority
# scanning, fill-paint matching, etc. all key off the exact string).

const ENHANCED_AMPLIFY_BONUS = 0.35

func _init():
	super._init()

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	var result = super.process_energy(packet, entry_direction, grid, entry_coord)
	for p in result:
		p.amplify(1.0 + ENHANCED_AMPLIFY_BONUS)
	return result
