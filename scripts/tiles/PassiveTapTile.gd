class_name PassiveTapTile
extends HexTile

# "Copies a packet to a second direction at full magnitude" (Status.md
# backlog: "more transparent hex tiles") - deliberately NOT Splitter's
# ratio-based division. The main line passes through completely unchanged
# (straight any-direction pass-through, same as Directional Conduit); a full
# COPY also goes out a second, independently rotatable face - the main
# line's total energy is never reduced feeding the tap, unlike every real
# router tile in this game. A genuine duplication, not a conservation-of-
# energy routing tool - a deliberate low-commitment utility for feeding a
# second branch (a sensor tap, a secondary weapon feed) without taxing the
# primary line at all.

# Offset (in hex-direction steps) from the primary exit face to the tap
# face - independent of rotation_steps so the tap can point anywhere around
# the hex regardless of which way the main line is flowing. Default of 2
# keeps it clear of both the main exit and (usually) the entry face.
@export var tap_offset: int = 2

func _init():
	tile_type = "Passive Tap"
	category = TileCategory.ROUTER
	base_color = Color(0.55, 0.6, 0.3) # olive-brass, reads as "utility" not "power"

func get_weight() -> float:
	return TileStatsRegistry.get_stat("PassiveTapTile", "weight", 2.0) # a routing junction, same ballpark as Splitter/Reflector

func get_tap_direction(entry_direction: int) -> int:
	return (get_exit_direction(entry_direction) + tap_offset) % 6

func rotate(clockwise: bool = true):
	if clockwise:
		tap_offset = (tap_offset + 1) % 6
	else:
		tap_offset = (tap_offset - 1) % 6
		if tap_offset < 0:
			tap_offset += 6

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	if is_disabled:
		return [packet] # degraded: straight pass-through, same convention as HexTile's base case

	var main_exit = get_exit_direction(entry_direction)
	var tap_exit = get_tap_direction(entry_direction)
	if tap_exit == main_exit:
		# Never happens with the default offset, but a player-rotated tap
		# lining up exactly with the main exit should just behave as a
		# plain pass-through rather than silently doubling the main line.
		packet.direction = main_exit
		return [packet]

	var tap_packet = packet.copy()
	tap_packet.direction = tap_exit
	packet.direction = main_exit
	return [packet, tap_packet]
