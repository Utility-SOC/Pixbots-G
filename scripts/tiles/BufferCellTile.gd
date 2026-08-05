class_name BufferCellTile
extends HexTile

# Timing control, no power (Status.md backlog: "more transparent hex tiles").
# Holds exactly one packet, unchanged, releasing it only the NEXT time this
# tile activates - i.e. a one-step delay line, not a threshold/manual-trigger
# store like Accumulator/Capacitor. The packet that arrives THIS call is what
# comes back out NEXT call; nothing is emitted the first time a Buffer Cell
# is ever hit (empty on placement), matching a real delay element rather
# than "instant pass-through with extra bookkeeping."

var _stored_packet: EnergyPacket = null
# Entry direction the STORED packet itself arrived from - a Buffer Cell can
# be entered from more than one face across different calls (base HexTile's
# can_enter_from allows any direction), so the release direction has to be
# computed from whichever entry the held packet actually came in on, not
# whatever direction happens to trigger the release.
var _stored_entry_direction: int = 0

func _init():
	tile_type = "Buffer Cell"
	category = TileCategory.STORAGE
	base_color = Color(0.3, 0.5, 0.55) # cool, inert - reads as "holds," not "does"

func get_weight() -> float:
	return TileStatsRegistry.get_stat("BufferCellTile", "weight", 1.5) # a small hold-capacitor, heavier than a plain conduit but far lighter than a real Accumulator

func reset_simulation_state() -> void:
	super.reset_simulation_state()
	_stored_packet = null
	_stored_entry_direction = 0

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	if is_disabled:
		return [packet] # degraded: straight pass-through, same convention as HexTile's base case

	var to_release = _stored_packet
	var release_direction = _stored_entry_direction
	_stored_packet = packet
	_stored_entry_direction = entry_direction
	if not to_release:
		return [] # nothing was waiting yet - this call just fills the buffer

	to_release.direction = get_exit_direction(release_direction)
	return [to_release]
