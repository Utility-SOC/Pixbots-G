class_name ComponentLinkTile
extends HexTile

@export var target_slot: HexTile.BodySlot = HexTile.BodySlot.NONE
var is_fixed: bool = false # True for arms/legs/head, False for backpack/accessories
var pending_transfer_packets: Array[EnergyPacket] = []

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

func process_energy(packet: EnergyPacket, from_direction: int, grid: Node = null) -> Array[EnergyPacket]:
	if is_disabled:
		return [packet] # Passes through if disabled
		
	# Store packet for transfer to the target component's grid
	pending_transfer_packets.append(packet)
	
	# The packet leaves THIS grid
	packet.is_active = false 
	return [packet]

func get_pending_transfers() -> Array[EnergyPacket]:
	var result = pending_transfer_packets.duplicate()
	pending_transfer_packets.clear()
	return result
