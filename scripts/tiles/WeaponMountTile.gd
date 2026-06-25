class_name WeaponMountTile
extends HexTile

@export var damage_multiplier: float = 1.0

var pending_packets: Array = [] # Stores dictionary: { "packet": packet, "step": step }

func _init():
	tile_type = "Weapon Mount"
	category = TileCategory.OUTPUT

func clear_pending():
	pending_packets.clear()

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null) -> Array[EnergyPacket]:
	var step = 0
	if "traversal_steps" in packet:
		step = packet.traversal_steps
		
	# Add copy to pending list
	pending_packets.append({ "packet": packet.copy(), "step": step })
	
	packet.is_active = false
	packet.magnitude = 0.0
	return [packet]

func fire_pending(mech: Node2D):
	if pending_packets.is_empty():
		return
		
	var step_groups: Dictionary = {}
	for item in pending_packets:
		var step = item.step
		if not step_groups.has(step):
			step_groups[step] = []
		step_groups[step].append(item.packet)
		
	var sorted_steps = step_groups.keys()
	sorted_steps.sort()
	
	for step in sorted_steps:
		var group: Array = step_groups[step]
		if group.is_empty(): continue
		
		# Merge synced packets
		var merged_packet = group[0].copy()
		for i in range(1, group.size()):
			merged_packet.merge(group[i])
			
		_fire_combined_projectile(mech, merged_packet, step)
		
	pending_packets.clear()

func _fire_combined_projectile(mech: Node2D, packet: EnergyPacket, step: int):
	var ProjectileClass = load("res://scripts/entities/Projectile.gd")
	if not ProjectileClass: return
	
	var proj = ProjectileClass.new()
	var base_damage = packet.magnitude * damage_multiplier * _get_power_multiplier()
	
	proj.fired_by_player = mech.get("is_player") == true
	proj.source_mech = mech
	proj.damage = base_damage
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
	if body_slot == load("res://scripts/core/HexTile.gd").BodySlot.ARM_L:
		forward_dir = 3 # West
	elif body_slot == load("res://scripts/core/HexTile.gd").BodySlot.ARM_R:
		forward_dir = 0 # East
	elif body_slot == load("res://scripts/core/HexTile.gd").BodySlot.HEAD:
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
