class_name MissileRackTile
extends HexTile

# STUB - fourth-review ruling (task: remote-payload weapons): the full
# weapon-variety version of indirect fire will be a dedicated mount tile,
# not just the Mythic Weapon Mount's "Mortar" pattern (which shipped first
# and shares MortarShell.gd). Planned differences from a Weapon Mount:
#   - always indirect (no direct-fire mode), cheaper rarity entry
#   - salvo behavior: banks packets into N shells delivered as a spread
#     around the aim point instead of one big payload
#   - AI usage hint so the director can field artillery roles with it
# NOT registered in loot tables / Black Market / AutoEquipSolver yet -
# equipping is only possible via debug until the tile is finished.

func _init():
	tile_type = "Missile Rack"
	category = TileCategory.OUTPUT
	base_color = Color(0.45, 0.4, 0.28)

func get_weight() -> float:
	return 7.0

# Pass-through until the salvo model lands - see header.
func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null) -> Array[EnergyPacket]:
	return [packet]
