class_name PhaseShifterTile
extends HexTile

# Mythic only. A powered Phase Shifter lets the wearer walk through EVERY terrain obstacle (rocks, trees, ruins, husks:
# the layer the Jumpjets fly over; map border, dungeon walls and water are untouched and are not counted). The price is
# a systemic drain: while the wearer is inside obstacles, all energy moving through the mech is cut by DRAIN_PER_PIECE
# for every obstacle piece touched, every physics tick (additive across pieces: three pieces = 15% per tick). The drain
# is PhaseDrain's `flow` multiplier; it recovers over RECOVER_SECONDS once clear. Numbers marked (tune).
#
# Terminal, like the Anchor: it absorbs what reaches it and needs some energy to work (an unfed shifter does nothing).

const DRAIN_PER_PIECE = 0.05
const RECOVER_SECONDS = 1.0 # (tune) time to come back from fully drained to full flow once clear of terrain

var stored_energy: float = 0.0

func _init():
	tile_type = "Phase Shifter"
	category = TileCategory.SPECIAL
	base_color = Color(0.45, 0.2, 0.7)

func get_weight() -> float:
	return TileStatsRegistry.get_stat("PhaseShifterTile", "weight", 6.0)

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	var p = packet.copy()
	stored_energy += p.magnitude
	p.is_active = false
	p.magnitude = 0.0
	return [p]

# Energy absorbed since the last read (MechGridSim reads it once per recalculation).
func take_phase_energy() -> float:
	var e = stored_energy
	stored_energy = 0.0
	return e

# True when this tile does anything: Mythic and fed.
func is_working(fed_energy: float) -> bool:
	return rarity == Rarity.MYTHIC and fed_energy > 0.0
