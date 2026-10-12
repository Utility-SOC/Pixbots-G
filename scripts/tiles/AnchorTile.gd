class_name AnchorTile
extends HexTile

# Anchors you to the ground against Vortex. Presence alone makes the wearer immune to its own side's Vortex pull. Energy fed
# into the Anchor (it is a terminal tile: it absorbs what reaches it, like the Shield Generator) additionally shields the
# wearer from ENEMY pull and softens Vortex damage, saturating: protection = E / (E + ANCHOR_REF_ENERGY), capped. An unfed
# Anchor behaves exactly as before. Mythic keeps its flat floors (see MechGridSim). Numbers marked (tune).

const ANCHOR_REF_ENERGY = 300.0 # (tune) fed energy that gives half of the maximum protection
const MAX_PULL_PROTECTION = 0.9 # (tune) enemy pull can never be reduced below 10%
const DAMAGE_REDUCTION_SHARE = 0.5 # (tune) vortex damage reduction = this x pull protection

var stored_energy: float = 0.0

func _init():
	tile_type = "Anchor"
	category = TileCategory.SPECIAL
	base_color = Color(0.2, 0.2, 0.25) # Dark, heavy grey

func get_weight() -> float:
	return TileStatsRegistry.get_stat("AnchorTile", "weight", 8.0)

# Terminal: whatever is fed in is absorbed (and read once by MechGridSim after the sim), nothing continues.
func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	var p = packet.copy()
	stored_energy += p.magnitude
	p.is_active = false
	p.magnitude = 0.0
	return [p]

func get_anchor_energy() -> float:
	var e = stored_energy
	stored_energy = 0.0
	return e

# Share of an enemy Vortex pull the wearer ignores, from the total energy fed into their Anchors.
static func protection_for(fed_energy: float) -> float:
	if fed_energy <= 0.0:
		return 0.0
	return MAX_PULL_PROTECTION * fed_energy / (fed_energy + ANCHOR_REF_ENERGY)

static func damage_reduction_for(fed_energy: float) -> float:
	return DAMAGE_REDUCTION_SHARE * protection_for(fed_energy)
