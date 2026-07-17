class_name ShieldGeneratorTile
extends HexTile

# MYTHIC toggle - see Mech.gd's shield_mythic_mode / _apply_shield_mitigation
# / _deflect_overflow. Aegis: hard per-hit damage cap while shields hold
# (pure tank). Deflector: overflow that would bleed through to HP instead
# ejects as an offensive burst in a random direction, fully absorbing the
# hit. Same UI/data pattern as every other Mythic toggle in the game.
@export_enum("Aegis", "Deflector") var mythic_mode: int = 0

func cycle_mythic_mode():
	mythic_mode = (mythic_mode + 1) % 2

func _init():
	super._init("Shield Generator", HexTile.TileCategory.OUTPUT)
	base_color = Color(0.1, 0.4, 0.8)

var stored_energy: float = 0.0
# Full-codebase audit finding: this tile shares tile_type "Shield Generator"
# with ShieldTile.gd (Mythic Shield backpack) but never tracked
# shield_synergies, so Mech.gd's `tile.has_method("get_shield_synergies")`
# duck-typed check (see the Shield Generator collection block) silently
# no-opped for it - a mech built from the Command Suite backpack (which
# uses THIS class) never contributed to shield_synergies/
# dominant_shield_synergy, meaning the entire "AI builds a counter to your
# shield's dominant element" system (SquadDirector.SHIELD_COUNTER_WHEEL)
# quietly never engaged for those players. Tracked at the same relative
# weight as this tile's own energy_storage_rarity_coeff multiplier, not
# ShieldTile's separate energy_mult_by_rarity curve - each tile keeps its
# own balance curve, only the missing capability is added.
var shield_synergies: Dictionary = {}

func get_weight() -> float:
	return TileStatsRegistry.get_stat("ShieldGeneratorTile", "weight", 6.5) # substantial shield-generation hardware

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	if packet.magnitude <= 0.0 or not packet.is_active: return []

	packet.is_active = false # Consume energy
	var mult = 1.0 + rarity * TileStatsRegistry.get_stat("ShieldGeneratorTile", "energy_storage_rarity_coeff", 0.5)
	stored_energy += packet.magnitude * mult
	for k in packet.synergies:
		shield_synergies[k] = shield_synergies.get(k, 0.0) + packet.synergies[k] * mult

	return []

func get_shield_energy() -> float:
	var e = stored_energy
	stored_energy = 0.0
	return e

func get_shield_synergies() -> Dictionary:
	var s = shield_synergies.duplicate()
	shield_synergies.clear()
	return s
