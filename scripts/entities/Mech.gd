class_name Mech
extends CharacterBody2D

const CoreTile = preload("res://scripts/tiles/CoreTile.gd")
const ComponentEquipment = preload("res://scripts/core/ComponentEquipment.gd")
const ComponentLinkTile = preload("res://scripts/tiles/ComponentLinkTile.gd")

var max_hp: float = 100.0
var hp: float = 100.0
var shield_hp: float = 0.0
var max_shield_hp: float = 0.0

var shield_recharge_delay: float = 3.0
var time_since_last_hit: float = 0.0
var shield_recharge_rate: float = 0.0
var has_shield_generator: bool = false

var current_move_speed: float = 200.0
var base_move_speed: float = 200.0
var combat_role: String = "melee"

var status_effects: Dictionary = {}
var stat_modifiers: Dictionary = {}
var jumpjet_rarity: int = -1
var jumpjet_energy = null

func apply_shield_energy(amount: float):
	max_shield_hp += amount # Max shield grows based on energy it processes!
	shield_hp = max_shield_hp

var is_player: bool = false
var is_firing_outward: bool = false
var last_aim_position: Vector2 = Vector2.ZERO

var current_jammer_debuff: float = 1.0 # 1.0 is no debuff. 0.1 is 90% power reduction



var fire_cooldown: float = 0.0
var fire_rate: float = 0.25 # 4 shots per second

var components: Dictionary = {} # Dict of HexTile.BodySlot -> ComponentEquipment
var is_grid_dirty: bool = true
var precalculated_weapons: Array = []

var is_drowning: bool = false
var drown_timer: float = 1.0

var current_path: PackedVector2Array = []
var path_update_timer: float = 0.0

# Advanced AI Tactics
var target: Node2D = null
var speed_modifier: float = 1.0
var engagement_distance: float = 200.0 # How close to get before strafing
var rotational_direction: float = 1.0 # 1.0 for clockwise, -1.0 for counter-clockwise
var base_speed: float = 150.0

var separate_arm_firing: bool = false
var base_rarity: int = 0 # HexTile.Rarity.COMMON
var is_boss: bool = false
var total_magnetic_power: float = 0.0
var visual_seed: int = 0

signal dealt_damage(amount: float)
signal died()
signal fled_to_wild(bot: Node)

var is_dead: bool = false


func apply_jammer_debuff(power_multiplier: float):
	# Take the most severe debuff if multiple jammers are present
	current_jammer_debuff = min(current_jammer_debuff, power_multiplier)

func _ready():
	# Build default body
	equip_component(ComponentEquipment.create_starter_torso(combat_role if not is_player else "", base_rarity))
	equip_component(ComponentEquipment.create_starter_arm(true, combat_role if not is_player else "", base_rarity))
	equip_component(ComponentEquipment.create_starter_arm(false, combat_role if not is_player else "", base_rarity))
	equip_component(ComponentEquipment.create_starter_leg(true, combat_role if not is_player else "", base_rarity))
	equip_component(ComponentEquipment.create_starter_leg(false, combat_role if not is_player else "", base_rarity))
	equip_component(ComponentEquipment.create_starter_head(combat_role if not is_player else "", base_rarity))
	equip_component(ComponentEquipment.create_starter_backpack(combat_role if not is_player else "", base_rarity))
	
	if not is_player:
		visual_seed = randi()
	
	if not is_player:
		build_loadout_for_role(combat_role)
	
	# Attach Visual Renderer
	var renderer = load("res://scripts/visuals/MechRenderer.gd").new()
	renderer.name = "MechRenderer"
	add_child(renderer)
	
	# Pass the full components dict so the renderer can draw each piece
	renderer.components = components
	renderer._rebuild_visuals()
	
	# Collision shape
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(40, 40)
	collision.shape = shape
	add_child(collision)
	
	if is_player:
		collision_layer = 8 # Layer 4 (Player)
		collision_mask = 1 | 2 | 4 | 16 # Env, Water, Enemy, Loot
	else:
		collision_layer = 4 # Layer 3 (Enemy)
		collision_mask = 1 | 2 | 8 # Env, Water, Player
	
func equip_component(comp: ComponentEquipment):
	if comp.slot_type == HexTile.BodySlot.TORSO:
		var h0 = HexCoord.new(0, 0)
		var has_core = false
		if comp.hex_grid.has_tile(h0):
			var existing = comp.hex_grid.get_tile(h0)
			if existing and existing.tile_type == "Core Reactor":
				has_core = true
			else:
				comp.hex_grid.remove_tile(h0)
		if not has_core:
			var core_tile = load("res://scripts/tiles/CoreTile.gd").new()
			core_tile.body_slot = HexTile.BodySlot.TORSO
			comp.hex_grid.add_tile(h0, core_tile)
			
	components[comp.slot_type] = comp
	add_child(comp)
	is_grid_dirty = true
	
func unequip_component(slot: HexTile.BodySlot) -> ComponentEquipment:
	if components.has(slot):
		var comp = components[slot]
		components.erase(slot)
		remove_child(comp)
		is_grid_dirty = true
		return comp
	return null

func _physics_process(delta: float):
	current_jammer_debuff = 1.0 # Reset every frame, JammerMech will re-apply it before we shoot if near
	
	if is_drowning:
		drown_timer -= delta
		scale = Vector2.ONE * (drown_timer)
		modulate.a = drown_timer
		if drown_timer <= 0:
			die()
		return
		
	update_status_effects(delta)
	
	if fire_cooldown > 0:
		fire_cooldown -= delta
		
	time_since_last_hit += delta
	if has_shield_generator and max_shield_hp > 0 and time_since_last_hit >= shield_recharge_delay:
		if shield_hp < max_shield_hp:
			shield_hp = min(max_shield_hp, shield_hp + shield_recharge_rate * delta)
			
	if is_player:
		_handle_player_input(delta)
		move_and_slide()
		
		# Magnet Logic
		if total_magnetic_power > 0.0:
			var pull_radius = 150.0 + (total_magnetic_power * 10.0)
			var loot_nodes = get_tree().get_nodes_in_group("loot")
			for loot in loot_nodes:
				if loot.global_position.distance_to(global_position) < pull_radius:
					# Pull strength scales with power
					loot.pull_towards(global_position, delta * (0.5 + total_magnetic_power * 0.02))
		
		# Drowning check
		if not Input.is_action_pressed("ui_select"):
			_check_drowning()
		
		var renderer = get_node_or_null("MechRenderer")
		if renderer:
			renderer.rotate_arms(get_global_mouse_position(), global_position)
			renderer.animate_legs(velocity, Time.get_ticks_msec() / 1000.0)
	else:
		_execute_ai_tactics(delta)
		move_and_slide()
		
		var is_jumping = false
		if components.has(HexTile.BodySlot.BACKPACK):
			if components[HexTile.BodySlot.BACKPACK].component_name == "Jetpack":
				is_jumping = true
		if not is_jumping:
			_check_drowning()
		
		if target:
			var renderer = get_node_or_null("MechRenderer")
			if renderer:
				renderer.rotate_arms(target.global_position, global_position)
				renderer.animate_legs(velocity, Time.get_ticks_msec() / 1000.0)

func _check_drowning():
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = global_position
	query.collision_mask = 2 # Water layer
	var result = space_state.intersect_point(query)
	if result.size() > 0:
		is_drowning = true
		velocity = Vector2.ZERO

func _handle_player_input(delta: float):
	# Simple WASD movement
	var input_dir = Vector2.ZERO
	input_dir.x = Input.get_axis("ui_left", "ui_right")
	input_dir.y = Input.get_axis("ui_up", "ui_down")
	
	if input_dir.length() > 0:
		input_dir = input_dir.normalized()
		
	var target_vel = input_dir * current_move_speed
	
	if Input.is_key_pressed(KEY_SHIFT):
		var sprint_mult = 1.5
		if jumpjet_energy and jumpjet_energy.magnitude > 0:
			sprint_mult += (jumpjet_energy.magnitude / 200.0) # Scale up sprint multiplier
			
			# Leave Elemental Trail
			if is_player and get_tree().get_frame() % 3 == 0:
				var p = CPUParticles2D.new()
				p.emitting = true
				p.amount = int(clamp(jumpjet_energy.magnitude / 10.0, 5, 20))
				p.lifetime = 0.5
				p.one_shot = true
				p.explosiveness = 0.8
				p.direction = -velocity.normalized()
				p.spread = 15.0
				p.initial_velocity_min = 50.0
				p.initial_velocity_max = 100.0
				p.scale_amount_min = 2.0
				p.scale_amount_max = 5.0
				p.color = EnergyPacket.get_color_blend(jumpjet_energy.synergies)
				p.global_position = global_position + Vector2(0, 10)
				get_parent().add_child(p)
				var t = get_tree().create_timer(p.lifetime)
				t.timeout.connect(p.queue_free)
				
		target_vel *= sprint_mult
		# Scale acceleration proportionally to the current move speed vs default base speed (150.0)
		var speed_scale = max(1.0, current_move_speed / 150.0)
		var rarity_bonus = max(0, jumpjet_rarity)
		var accel = (400.0 + (rarity_bonus * 400.0)) * speed_scale 
		if target_vel == Vector2.ZERO:
			velocity = velocity.move_toward(Vector2.ZERO, accel * delta)
		else:
			velocity = velocity.move_toward(target_vel, accel * delta)
	else:
		velocity = target_vel
	
	# JumpJets automatically hover over Water (Mask 2) and some obstacles
	if jumpjet_rarity >= 0:
		collision_mask = 1 | 4 | 16 # Only collide with walls/obstacles, Enemy, Loot
	else:
		collision_mask = 1 | 2 | 4 | 16 # Collide with water too
		
	# Mouse Aiming
	var mouse_pos = get_global_mouse_position()
	
	# Firing logic
	var is_left_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var is_right_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	
	var is_firing = false
	if is_left_pressed and is_right_pressed and not separate_arm_firing:
		_shoot(mouse_pos, true, true, delta)
		is_firing = true
	elif is_left_pressed:
		_shoot(mouse_pos, true, true, delta)
		is_firing = true
	elif is_right_pressed:
		if separate_arm_firing:
			_shoot(mouse_pos, true, false, delta)
		else:
			_shoot(mouse_pos, false, false, delta)
		is_firing = true
		
	if not is_firing:
		_shoot_release()

func _shoot(target_pos: Vector2, is_outward: bool, fire_left_arm: bool = true, delta: float = 0.0):
	last_aim_position = target_pos
	is_firing_outward = is_outward
	
	if is_grid_dirty:
		_recalculate_grid()
		
	for data in precalculated_weapons:
		if is_player and separate_arm_firing and data.slot_type != HexTile.BodySlot.BACKPACK:
			if fire_left_arm and data.slot_type == HexTile.BodySlot.ARM_R:
				continue
			if not fire_left_arm and data.slot_type == HexTile.BodySlot.ARM_L:
				continue
				
		var mount = data.mount
		var required_charge = data.packet.charge_required
		
		# Tick the charge upwards
		mount.current_charge += (delta / max(0.01, fire_rate))
		
		if mount.current_charge >= required_charge:
			# Fully charged, fire and loop remainder
			var packet_to_fire = data.packet.copy()
			packet_to_fire.magnitude *= current_jammer_debuff
			for k in packet_to_fire.synergies:
				packet_to_fire.synergies[k] *= current_jammer_debuff
			
			mount._fire_combined_projectile(self, packet_to_fire, data.step)
			mount.current_charge -= required_charge

func _shoot_release():
	for data in precalculated_weapons:
		var mount = data.mount
		if mount.current_charge > 0.0:
			var required_charge = data.packet.charge_required
			var proportion = min(1.0, mount.current_charge / required_charge)
			
			if proportion > 0.1: # Only fire if at least 10% charged to prevent micro-spam
				var early_packet = data.packet.copy()
				var total_mod = proportion * current_jammer_debuff
				early_packet.magnitude *= total_mod
				for k in early_packet.synergies:
					early_packet.synergies[k] *= total_mod
				mount._fire_combined_projectile(self, early_packet, data.step)
			
			mount.current_charge = 0.0

func _recalculate_grid():
	precalculated_weapons.clear()
	max_shield_hp = 0.0 # Reset shield HP
	has_shield_generator = false
	shield_recharge_delay = 3.0
	shield_recharge_rate = 0.0
	base_move_speed = 150.0 # Reset base speed for Jumpjets to calculate
	jumpjet_rarity = -1
	
	if jumpjet_energy == null:
		jumpjet_energy = EnergyPacket.new(0.0, null)
	jumpjet_energy.magnitude = 0.0
	jumpjet_energy.synergies.clear()
	
	total_magnetic_power = 0.0
	stat_modifiers.clear()
	
	# Aggregate all component stat modifiers
	for comp in components.values():
		if comp.get("stat_modifiers"):
			for k in comp.stat_modifiers:
				if stat_modifiers.has(k):
					stat_modifiers[k] += comp.stat_modifiers[k] - 1.0 # Additive percentage bonuses
				else:
					stat_modifiers[k] = comp.stat_modifiers[k]
	
	if not components.has(HexTile.BodySlot.TORSO):
		return
		
	var torso = components[HexTile.BodySlot.TORSO]
	
	# Collect energy from ALL generators in the Torso
	var initial_packets: Array[EnergyPacket] = []
	for coord in torso.hex_grid.grid.keys():
		var t = torso.hex_grid.get_tile(coord)
		if t.has_method("generate_energy"):
			var pkts = t.generate_energy(torso.hex_grid)
			for p in pkts:
				p.position = HexCoord.new(coord.x, coord.y)
			initial_packets.append_array(pkts)
	
	# PHASE 1: Route through Torso grid
	_simulate_grid(torso.hex_grid, initial_packets)
	
	# PHASE 2: Collect transferred packets from Sinks and route into peripheral grids
	var peripheral_transfer = _collect_transfers(torso)
	# Simulate HEAD and BACKPACK first so they can return energy
	var return_pkts: Array[EnergyPacket] = []
	for accessory_slot in [HexTile.BodySlot.HEAD, HexTile.BodySlot.BACKPACK]:
		if peripheral_transfer.has(accessory_slot) and components.has(accessory_slot):
			var accessory_comp = components[accessory_slot]
			var a_pkts = peripheral_transfer[accessory_slot]
			_route_to_peripheral(a_pkts, accessory_comp)
			
			for coord in accessory_comp.hex_grid.grid.keys():
				var t = accessory_comp.hex_grid.get_tile(coord)
				if t.has_method("generate_energy"):
					var pkts = t.generate_energy(accessory_comp.hex_grid)
					for p in pkts:
						p.position = HexCoord.new(coord.x, coord.y)
					a_pkts.append_array(pkts)
					
			_simulate_grid(accessory_comp.hex_grid, a_pkts)
			
			# Collect return packets
			var accessory_return = _collect_transfers(accessory_comp)
			if accessory_return.has(HexTile.BodySlot.TORSO):
				return_pkts.append_array(accessory_return[HexTile.BodySlot.TORSO])

	if return_pkts.size() > 0:
		var return_pos = HexCoord.new(0, 0)
		var return_tile = null
		# Find the Accessory Return node
		for coord_v in torso.hex_grid.grid.keys():
			var t = torso.hex_grid.grid[coord_v]
			if t.tile_type == "Accessory Return":
				return_pos = HexCoord.new(coord_v.x, coord_v.y)
				return_tile = t
				break
		
		var final_return_pkts: Array[EnergyPacket] = []
		for pkt in return_pkts:
			if return_tile:
				# Process it through the Return Link
				var out = return_tile.process_energy(pkt, 0, torso.hex_grid)
				for p in out:
					p.position = return_pos
					p.is_active = true
					final_return_pkts.append(p)
			else:
				pkt.position = return_pos
				pkt.is_active = true
				final_return_pkts.append(pkt)
				
		# Re-simulate Torso with returned energy!
		_simulate_grid(torso.hex_grid, final_return_pkts)
		
		# Add any new transfers from Torso back into the peripheral pools
		var second_transfers = _collect_transfers(torso)
		for slot in second_transfers:
			if not peripheral_transfer.has(slot):
				peripheral_transfer[slot] = []
			peripheral_transfer[slot].append_array(second_transfers[slot])

	# Simulate remaining peripherals (Arms, Legs)
	for slot in components.keys():
		if slot == HexTile.BodySlot.HEAD or slot == HexTile.BodySlot.BACKPACK or slot == HexTile.BodySlot.TORSO: 
			continue # Already simulated
			
		var comp = components[slot]
		var pkts: Array[EnergyPacket] = []
		if peripheral_transfer.has(slot):
			pkts.append_array(peripheral_transfer[slot])
			_route_to_peripheral(pkts, comp)
			
		for coord in comp.hex_grid.grid.keys():
			var t = comp.hex_grid.get_tile(coord)
			if t.has_method("generate_energy"):
				var generated = t.generate_energy(comp.hex_grid)
				for p in generated:
					p.position = HexCoord.new(coord.x, coord.y)
				pkts.append_array(generated)
				
		_simulate_grid(comp.hex_grid, pkts)
			
	for comp in components.values():
		for tile in comp.hex_grid.get_all_tiles():
			if (tile.tile_type == "Weapon Mount" or tile.tile_type == "Accessory Return" or tile.tile_type == "Torso Return") and "pending_packets" in tile and tile.pending_packets.size() > 0:
				var step_groups = {}
				for item in tile.pending_packets:

					var step = item.step
					if not step_groups.has(step):
						step_groups[step] = item.packet.copy()
					else:
						step_groups[step].merge(item.packet)
						
				for step in step_groups:
					precalculated_weapons.append({
						"mount": tile,
						"packet": step_groups[step],
						"step": step,
						"slot_type": comp.slot_type
					})
				tile.clear_pending()
				
			if tile.has_method("get_speed_bonus"):
				base_move_speed += tile.get_speed_bonus()
				
			if tile.has_method("get_magnetic_power"):
				total_magnetic_power += tile.get_magnetic_power()
				
			if tile.tile_type == "Shield Generator" and tile.has_method("get_shield_energy"):
				has_shield_generator = true
				var shield_energy = tile.get_shield_energy()
				# Scale directly 1:1 with energy to allow tanking own hits
				max_shield_hp += shield_energy
				# Mythic takes .25s, Legendary takes 0.5s, Rare takes 1.0s, Uncommon 2.0s, Common 3.0s
				if tile.rarity == HexTile.Rarity.MYTHIC:
					shield_recharge_delay = min(shield_recharge_delay, 0.25)
				elif tile.rarity == HexTile.Rarity.LEGENDARY:
					shield_recharge_delay = min(shield_recharge_delay, 0.5)
				elif tile.rarity == HexTile.Rarity.RARE:
					shield_recharge_delay = min(shield_recharge_delay, 1.0)
				elif tile.rarity == HexTile.Rarity.UNCOMMON:
					shield_recharge_delay = min(shield_recharge_delay, 2.0)
				else:
					shield_recharge_delay = min(shield_recharge_delay, 3.0)
					
				# Rapidly recharge (e.g. fully recharge in 2 seconds)
				shield_recharge_rate += max_shield_hp * 0.5
				
	# Keep shield HP within bounds
	shield_hp = min(shield_hp, max_shield_hp)
	if not has_shield_generator:
		shield_hp = 0.0
		
	is_grid_dirty = false

func _collect_transfers(comp) -> Dictionary:
	var result = {}
	for t in comp.hex_grid.get_all_tiles():
		if t.tile_type.ends_with("Link") or t.tile_type == "Accessory Return" or t.tile_type == "Torso Return":
			if t.has_method("get_pending_transfers"):
				var transfer_pkts = t.get_pending_transfers()
				if transfer_pkts.size() > 0:
					if not result.has(t.target_slot):
						result[t.target_slot] = []
					result[t.target_slot].append_array(transfer_pkts)
	return result

func _route_to_peripheral(pkts: Array, comp):
	for pkt in pkts:
		var opp_dir = (pkt.direction + 3) % 6
		pkt.position = HexCoord.new(0, 0).neighbor(opp_dir)
		pkt.is_active = true

func _simulate_grid(grid: HexGridComponent, starting_packets: Array):
	var active_packets: Array[EnergyPacket] = []
	for pkt in starting_packets:
		if pkt.position == null:
			pkt.position = HexCoord.new(0, 0)
		pkt.traversal_steps = 0
		active_packets.append(pkt)
		
	var steps = 0
	# Max 100 routing steps to prevent infinite loops from closed circuits
	while active_packets.size() > 0 and steps < 100:
		steps += 1
		var next_packets: Array[EnergyPacket] = []
		
		for p in active_packets:
			if not p.is_active: continue
			var dir = p.direction
			var next_pos = p.position.neighbor(dir)
			
			if grid.has_tile(next_pos):
				var tile = grid.get_tile(next_pos)
				p.traversal_steps += 1
				if "sync_adjustment" in tile:
					p.traversal_steps += tile.sync_adjustment
					p.traversal_steps = max(0, p.traversal_steps)
					
				var out_pkts = tile.process_energy(p, (dir + 3) % 6, grid)
				for out in out_pkts:
					out.position = next_pos
					out.traversal_steps = p.traversal_steps
				next_packets.append_array(out_pkts)
			else:
				var comp = grid.get_parent()
				var is_valid_empty = false
				if comp and "valid_hexes" in comp:
					for h in comp.valid_hexes:
						if h.q == next_pos.q and h.r == next_pos.r:
							is_valid_empty = true
							break
							
				if is_valid_empty:
					# Pass straight through empty hex with 5% energy loss
					var pass_p = p.copy()
					pass_p.position = next_pos
					pass_p.traversal_steps += 1
					pass_p.magnitude *= 0.95
					for k in pass_p.synergies.keys():
						pass_p.synergies[k] *= 0.95
					next_packets.append(pass_p)
				else:
					# Edge bounce: reflect 180 degrees
					var bounce_p = p.copy()
					bounce_p.direction = (dir + 3) % 6
					bounce_p.position = p.position # Stay on the current tile
					bounce_p.traversal_steps = p.traversal_steps
					next_packets.append(bounce_p)
		
		var merged_packets = {}
		for p in next_packets:
			if not p.is_active: continue
			# Merge packets arriving at same tile with same direction
			var key = str(p.position.q) + "_" + str(p.position.r) + "_" + str(p.direction)
			if merged_packets.has(key):
				merged_packets[key].merge(p)
			else:
				merged_packets[key] = p
				
		active_packets.assign(merged_packets.values())

func _execute_ai_tactics(delta):
	if not target:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			target = players[0]
			
	if target:
		var dist = global_position.distance_to(target.global_position)
		var dir = global_position.direction_to(target.global_position)
		
		path_update_timer -= delta
		if path_update_timer <= 0:
			path_update_timer = 0.5 + randf_range(0, 0.2)
			var maps = get_tree().get_nodes_in_group("map_generator")
			if maps.size() > 0:
				var map = maps[0]
				var start_grid = Vector2i(
					clamp(floor(global_position.x / map.tile_size), 0, map.width - 1),
					clamp(floor(global_position.y / map.tile_size), 0, map.height - 1)
				)
				var end_grid = Vector2i(
					clamp(floor(target.global_position.x / map.tile_size), 0, map.width - 1),
					clamp(floor(target.global_position.y / map.tile_size), 0, map.height - 1)
				)
				if not map.astar_grid.is_point_solid(end_grid):
					current_path = map.astar_grid.get_id_path(start_grid, end_grid)
					for i in range(current_path.size()):
						var p = current_path[i]
						current_path[i] = Vector2(p.x * map.tile_size + map.tile_size/2.0, p.y * map.tile_size + map.tile_size/2.0)
		
		if current_path.size() > 1:
			var next_point = current_path[1]
			if global_position.distance_to(next_point) < 10.0:
				current_path.remove_at(0)
				if current_path.size() > 1:
					next_point = current_path[1]
					
			var path_dir = global_position.direction_to(next_point)
			
			if dist > engagement_distance:
				# Approach full speed
				velocity = path_dir * base_speed * speed_modifier
			else:
				# Reached engagement distance, strafe/orbit at half speed
				var tangent = Vector2(-dir.y, dir.x) * rotational_direction
				# Raycast to prevent strafing into walls
				var space_state = get_world_2d().direct_space_state
				var query = PhysicsRayQueryParameters2D.create(global_position, global_position + tangent * 50.0, 1)
				if space_state.intersect_ray(query):
					rotational_direction *= -1 # Reverse orbit
					tangent = Vector2(-dir.y, dir.x) * rotational_direction
					
				velocity = tangent * base_speed * (speed_modifier * 0.5)
		else:
			# Fallback if no path (or too close)
			if dist > engagement_distance:
				velocity = dir * base_speed * speed_modifier
			else:
				var tangent = Vector2(-dir.y, dir.x) * rotational_direction
				velocity = tangent * base_speed * (speed_modifier * 0.5)
			
		# AI combat shooting
		if dist < engagement_distance + 150.0:
			_shoot(target.global_position, true, true, delta)
		else:
			_shoot_release()
var elemental_resistances: Dictionary = {}

func apply_damage(amount: float, element: String = "RAW"):
	if elemental_resistances.has(element):
		amount *= elemental_resistances[element]
		
	if not is_player:
		var main = get_tree().current_scene
		if main and main.has_node("SquadDirector"):
			main.get_node("SquadDirector").log_player_damage(amount, element)
			
	if amount > 0:
		time_since_last_hit = 0.0
			
	if shield_hp > 0 and amount > 0:
		shield_hp -= amount
		if shield_hp < 0:
			amount = -shield_hp
			shield_hp = 0
		else:
			return # Shields absorbed all global damage
			
	hp -= amount
	if hp <= 0:
		die()

func apply_part_damage(slot: int, amount: float, element: String = "RAW"):
	if shield_hp > 0 and amount > 0:
		shield_hp -= amount
		if shield_hp < 0:
			amount = -shield_hp
			shield_hp = 0
		else:
			return # Shields absorbed all part damage
			
	if not components.has(slot): return
	var comp = components[slot]
	
	# Apply damage to a random tile in that component's grid
	var tiles = comp.hex_grid.get_all_tiles()
	if tiles.size() > 0:
		var hit_tile = tiles[randi() % tiles.size()]
		hit_tile.take_damage(amount)
		
	# Apply a small fraction of locational damage to global structure HP
	apply_damage(amount * 0.2, element)

func apply_status(effect_name: String, duration: float):
	status_effects[effect_name] = duration

func update_status_effects(delta: float):
	current_move_speed = base_move_speed
	
	var effects_to_remove = []
	for effect in status_effects:
		status_effects[effect] -= delta
		
		# Handle active effects
		if effect == "frozen":
			current_move_speed = base_move_speed * 0.4 # 60% slow
		elif effect == "burning":
			apply_damage(5.0 * delta) # 5 damage per second
			
		# Check if expired
		if status_effects[effect] <= 0:
			effects_to_remove.append(effect)
			
	for effect in effects_to_remove:
		status_effects.erase(effect)

func die():
	if is_dead or is_queued_for_deletion():
		return
	is_dead = true

		
	var loot_manager = load("res://scripts/core/LootManager.gd").new()
	loot_manager.generate_loot_for_mech(self)
	loot_manager.queue_free()
	
	died.emit()
	
	var is_over_water = false
	var maps = get_tree().get_nodes_in_group("map_generator")
	if maps.size() > 0:
		var map = maps[0]
		var grid_pos = Vector2i(floor(global_position.x / map.tile_size), floor(global_position.y / map.tile_size))
		if grid_pos.x >= 0 and grid_pos.x < map.width and grid_pos.y >= 0 and grid_pos.y < map.height:
			if map.terrain[grid_pos.y][grid_pos.x] == map.BiomeType.WATER:
				is_over_water = true
				
	if is_over_water:
		collision_layer = 0
		collision_mask = 0
		set_physics_process(false)
		var tween = create_tween()
		tween.tween_property(self, "scale", Vector2(0.2, 0.2), 1.0).set_trans(Tween.TRANS_SINE)
		tween.parallel().tween_property(self, "global_position", global_position + Vector2(0, 20), 1.0)
		tween.parallel().tween_property(self, "modulate:a", 0.0, 1.0)
		tween.tween_callback(queue_free)
	else:
		queue_free()

func build_loadout_for_role(role_name: String):
	var inventory = []
	
	var add_tile = func(path, rarity, synergy=0):
		var tile = load(path).new()
		tile.rarity = rarity
		if synergy > 0 and "secondary_synergy" in tile:
			tile.secondary_synergy = synergy
		inventory.append(tile)
		
	match role_name:
		"sniper":
			add_tile.call("res://scripts/tiles/AmplifierTile.gd", HexTile.Rarity.RARE)
			add_tile.call("res://scripts/tiles/CatalystTile.gd", HexTile.Rarity.RARE)
			add_tile.call("res://scripts/tiles/DirectionalConduitTile.gd", HexTile.Rarity.COMMON)
		"brawler":
			add_tile.call("res://scripts/tiles/SplitterTile.gd", HexTile.Rarity.UNCOMMON)
			add_tile.call("res://scripts/tiles/SplitterTile.gd", HexTile.Rarity.UNCOMMON)
			add_tile.call("res://scripts/tiles/AmplifierTile.gd", HexTile.Rarity.UNCOMMON)
		"flamethrower":
			add_tile.call("res://scripts/tiles/InfuserTile.gd", HexTile.Rarity.RARE, 1) # FIRE
			add_tile.call("res://scripts/tiles/SplitterTile.gd", HexTile.Rarity.UNCOMMON)
			add_tile.call("res://scripts/tiles/SplitterTile.gd", HexTile.Rarity.COMMON)
		"ambusher":
			add_tile.call("res://scripts/tiles/InfuserTile.gd", HexTile.Rarity.RARE, 4) # KINETIC
			add_tile.call("res://scripts/tiles/AmplifierTile.gd", HexTile.Rarity.UNCOMMON)
		"scout":
			pass # Uses basic conduits if they were available, fallback empty solver handles it
			
	var solver = load("res://scripts/core/AutoEquipSolver.gd").new()
	
	if components.has(HexTile.BodySlot.TORSO):
		inventory = solver.solve(components[HexTile.BodySlot.TORSO], inventory)
	if components.has(HexTile.BodySlot.ARM_R):
		inventory = solver.solve(components[HexTile.BodySlot.ARM_R], inventory)
	if components.has(HexTile.BodySlot.ARM_L):
		inventory = solver.solve(components[HexTile.BodySlot.ARM_L], inventory)
		
	_recalculate_grid()

