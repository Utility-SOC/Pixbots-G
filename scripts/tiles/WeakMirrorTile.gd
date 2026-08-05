class_name WeakMirrorTile
extends HexTile

# "Stripped-down Reflector - redirect only, no damage/defense upside"
# (Status.md backlog: "more transparent hex tiles"). Identical redirect
# logic to ReflectorTile.gd - the "no upside" is entirely about NOT sharing
# Reflector's tile_type string: HexTile.get_disable_risk() matches on
# tile_type specifically ("Reflector"/"Resonator"/"Amplifier"/"Heal Beacon"
# -> 0.55, "Splitter" -> 1.0, everything else -> 0.2 by default) - a real
# Reflector is a valuable disable-roll target for that reason, a Weak
# Mirror deliberately isn't, just by having its own distinct name. No
# override needed here to get that; it falls out of the base class for free.

@export var rotation_steps: int = 1 # CCW steps

func _init():
	tile_type = "Weak Mirror"
	category = TileCategory.ROUTER
	base_color = Color(0.5, 0.55, 0.58) # dull, unpolished steel - reads as "cheap glass," not Reflector's real hardware

func get_weight() -> float:
	return TileStatsRegistry.get_stat("WeakMirrorTile", "weight", 1.5) # lighter than a real Reflector - no reinforced housing

func get_exit_direction(entry_direction: int) -> int:
	return (entry_direction + 3 + rotation_steps) % 6

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	# No is_disabled check - matches ReflectorTile.gd's own process_energy
	# exactly (redirect happens unconditionally there too), since the whole
	# point here is identical logic, just without the higher disable-risk
	# categorization.
	packet.direction = get_exit_direction(entry_direction)
	return [packet]

func rotate(clockwise: bool = true):
	if clockwise:
		rotation_steps = (rotation_steps + 1) % 6
	else:
		rotation_steps = (rotation_steps - 1) % 6
		if rotation_steps < 0:
			rotation_steps += 6
