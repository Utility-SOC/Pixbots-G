class_name ComponentLinkTile
extends HexTile

@export var target_slot: HexTile.BodySlot = HexTile.BodySlot.NONE
var is_fixed: bool = false # True for arms/legs/head, False for backpack/accessories
var pending_transfer_packets: Array[EnergyPacket] = []
var pending_packets: Array = [] # Used when acting as a weapon mount
var current_charge: float = 0.0 # Used by Mech to track accumulator charging
var damage_multiplier: float = 1.0


func _init(p_target: HexTile.BodySlot = HexTile.BodySlot.NONE, p_is_fixed: bool = false):
	tile_type = "Component Link"
	category = TileCategory.ROUTER
	target_slot = p_target
	is_fixed = p_is_fixed

	if is_fixed:
		base_color = Color(0.8, 0.4, 0.2) # Orange for fixed sinks
	else:
		base_color = Color(0.2, 0.8, 0.4) # Green for optional sinks

	# Determine slot name for description
	var slot_name = "Unknown"
	match target_slot:
		HexTile.BodySlot.ARM_L: slot_name = "Left Arm"
		HexTile.BodySlot.ARM_R: slot_name = "Right Arm"
		HexTile.BodySlot.LEG_L: slot_name = "Left Leg"
		HexTile.BodySlot.LEG_R: slot_name = "Right Leg"
		HexTile.BodySlot.HEAD: slot_name = "Head"
		HexTile.BodySlot.BACKPACK: slot_name = "Backpack"

	tile_type = slot_name + " Link"

var active_faces: Array[int] = [0] # Default exit face

func get_weight() -> float:
	return TileStatsRegistry.get_stat("ComponentLinkTile", "weight", 1.0) # just a connector/sink, basically weightless

func get_max_faces() -> int:
	return 3

func toggle_output(direction: int):
	if target_slot != HexTile.BodySlot.NONE: return # Only Accessory Return can toggle outputs
	if active_faces.has(direction):
		if active_faces.size() > 1:
			active_faces.erase(direction)
	else:
		if active_faces.size() < get_max_faces():
			active_faces.append(direction)
		else:
			active_faces.pop_front()
			active_faces.append(direction)

func get_exit_directions(entry_direction: int = 0) -> Array[int]:
	if target_slot == HexTile.BodySlot.NONE:
		return active_faces
	return []

func process_energy(packet: EnergyPacket, from_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	if is_disabled:
		return [packet] # Passes through if disabled

	var step = 0
	if "traversal_steps" in packet:
		step = packet.traversal_steps


	if target_slot == HexTile.BodySlot.NONE:
		# Acts like a splitter for returning energy!
		var packets: Array[EnergyPacket] = []
		var split_count = active_faces.size()
		if split_count == 0:
			return [packet]

		var ratio = 1.0 / split_count
		for i in range(split_count):
			var exit_dir = active_faces[i]
			var neighbor_pos = grid_position.neighbor(exit_dir) if grid_position else null

			var target_packet = packet
			if i < split_count - 1:
				target_packet = packet.split(ratio / (1.0 - ratio * i))

			target_packet.direction = exit_dir

			# If no tile exists in that direction, capture it as a weapon payload!
			if grid and neighbor_pos and not grid.has_tile(neighbor_pos):
				pending_packets.append({ "packet": target_packet.copy(), "step": step })
				target_packet.is_active = false
			else:
				packets.append(target_packet)

		return packets
	else:

		# Acts as a sink to transfer out of the grid
		pending_transfer_packets.append(packet)
		packet.is_active = false
		return [packet]

func get_pending_transfers() -> Array[EnergyPacket]:
	var result = pending_transfer_packets.duplicate()
	pending_transfer_packets.clear()
	return result

func clear_pending():
	pending_packets.clear()

# _fire_combined_projectile(), get_muzzle_position(), and _get_power_multiplier()
# now live on the HexTile base class (scripts/core/HexTile.gd) - see the
# comment there for why (this file, WeaponMountTile.gd, and a since-deleted
# orphaned ComponentLinkTile_methods.gd all had near-identical copies).
