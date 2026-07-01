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

func process_energy(packet: EnergyPacket, from_direction: int, grid: Node = null) -> Array[EnergyPacket]:
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

func _fire_combined_projectile(mech: Node2D, packet: EnergyPacket, step: int):
	var ProjectileClass = load("res://scripts/entities/Projectile.gd")
	if not ProjectileClass: return
	
	var proj = ProjectileClass.new()
	var base_damage = packet.magnitude * damage_multiplier * _get_power_multiplier()
	
	var is_crit = (packet.magnitude >= 30000.0) or (randf() < 0.05)
	if is_crit:
		base_damage *= 2.0
		
	proj.fired_by_player = mech.get("is_player") == true
	proj.source_mech = mech
	proj.damage = base_damage
	proj.is_crit = is_crit
	proj.synergies = packet.synergies.duplicate()
	if "stat_modifiers" in mech:
		proj.stat_modifiers = mech.stat_modifiers.duplicate()
	proj.global_position = get_muzzle_position(mech)
	
	var aim_pos = mech.last_aim_position if "last_aim_position" in mech else mech.global_position + Vector2(0, -100)
	var muzzle_pos = get_muzzle_position(mech)
	
	var base_direction = (aim_pos - muzzle_pos).normalized()
	if base_direction == Vector2.ZERO:
		base_direction = Vector2(0, -1)
		
	if "target_direction" in proj:
		proj.target_direction = base_direction
	
	# Determine the "straight forward" direction based on which component we are in
	var forward_dir = 4 # Default South (Down) for Torso/Legs/Backpack
	if body_slot == HexTile.BodySlot.ARM_L:
		forward_dir = 3 # West
	elif body_slot == HexTile.BodySlot.ARM_R:
		forward_dir = 0 # East
	elif body_slot == HexTile.BodySlot.HEAD:
		forward_dir = 1 # Northeast (Up)
		
	var entry_dir = packet.direction
	var diff = (entry_dir - forward_dir + 6) % 6
	var angle_offset = 0.0
	
	if diff == 1: angle_offset = deg_to_rad(15)
	elif diff == 5: angle_offset = deg_to_rad(-15)
	elif diff == 2: angle_offset = deg_to_rad(35)
	elif diff == 4: angle_offset = deg_to_rad(-35)
	elif diff == 3: angle_offset = deg_to_rad(180)
	
	proj.direction = base_direction.rotated(angle_offset)
	
	if step > 0:
		var delay = (step * 0.05) # 50ms per step
		var timer = Timer.new()
		timer.wait_time = delay
		timer.one_shot = true
		timer.timeout.connect(func():
			if is_instance_valid(mech) and mech.get_parent():
				mech.get_parent().add_child(proj)
			elif is_instance_valid(proj):
				proj.queue_free()
			timer.queue_free()
		)
		mech.add_child(timer)
		timer.start()
	else:
		if mech.get_parent():
			mech.get_parent().add_child(proj)
		else:
			mech.add_child(proj)

func get_muzzle_position(mech: Node2D) -> Vector2:
	var renderer = mech.get_node_or_null("MechRenderer")
	if not renderer:
		return mech.global_position
		
	var is_left = (body_slot == HexTile.BodySlot.ARM_L)
	var is_right = (body_slot == HexTile.BodySlot.ARM_R)
	
	if is_left and renderer.drawn_parts.has("Arm_true"):
		var arm = renderer.drawn_parts["Arm_true"]
		var h = 28.0 * (1.0 + rarity * 0.15)
		return arm.global_position + Vector2(0, h).rotated(arm.global_rotation)
	elif is_right and renderer.drawn_parts.has("Arm_false"):
		var arm = renderer.drawn_parts["Arm_false"]
		var h = 28.0 * (1.0 + rarity * 0.15)
		return arm.global_position + Vector2(0, h).rotated(arm.global_rotation)
		
	return mech.global_position

func _get_power_multiplier() -> float:
	var mult = 1.0
	if rarity == Rarity.UNCOMMON: mult = 1.2
	elif rarity == Rarity.RARE: mult = 1.5
	elif rarity == Rarity.LEGENDARY: mult = 3.0
	return mult * (1.0 + (level - 1) * 0.1)
