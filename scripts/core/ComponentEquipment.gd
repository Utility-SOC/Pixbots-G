class_name ComponentEquipment
extends Node

const ComponentLinkTile = preload("res://scripts/tiles/ComponentLinkTile.gd")

var component_name: String = "Generic Component"
var slot_type: HexTile.BodySlot = HexTile.BodySlot.TORSO
var rarity: HexTile.Rarity = HexTile.Rarity.COMMON
var level: int = 1
var role_variant: String = ""

var grid_width: int = 3
var grid_height: int = 3

var hex_grid: HexGridComponent
var fixed_sinks: Array[HexCoord] = []
var valid_hexes: Array[HexCoord] = [] # Defines the irregular shape of the component

var infusion_level: int = 0
var infusion_xp: int = 0
var stat_modifiers: Dictionary = {}

func _init(p_slot: HexTile.BodySlot = HexTile.BodySlot.TORSO, p_rarity: HexTile.Rarity = HexTile.Rarity.COMMON):
	slot_type = p_slot
	rarity = p_rarity
	
	hex_grid = HexGridComponent.new()
	hex_grid.name = "HexGridComponent"
	add_child(hex_grid)
	
	_setup_grid_bounds()
	_setup_fixed_sinks()

func _setup_grid_bounds():
	match rarity:
		HexTile.Rarity.COMMON:
			grid_width = 3
			grid_height = 3
		HexTile.Rarity.UNCOMMON:
			grid_width = 4
			grid_height = 3
		HexTile.Rarity.RARE:
			grid_width = 4
			grid_height = 4
		HexTile.Rarity.LEGENDARY:
			grid_width = 5
			grid_height = 5

func _setup_fixed_sinks():
	pass

func generate_shape():
	valid_hexes.clear()
	
	var base_count = 0
	match rarity:
		HexTile.Rarity.COMMON: base_count = 10
		HexTile.Rarity.UNCOMMON: base_count = 18
		HexTile.Rarity.RARE: base_count = 28
		HexTile.Rarity.LEGENDARY: base_count = 48
		
	match slot_type:
		HexTile.BodySlot.HEAD:
			# Head expands upward, vertical zig-zag. Squat and wide.
			var head_len = 3
			if rarity >= HexTile.Rarity.UNCOMMON: head_len = 4
			if rarity >= HexTile.Rarity.RARE: head_len = 5
			if rarity >= HexTile.Rarity.LEGENDARY: head_len = 6
			
			for i in range(head_len):
				var q = i / 2
				valid_hexes.append(HexCoord.new(q, -i))
				
			# Add width for a squat shape
			if rarity >= HexTile.Rarity.UNCOMMON:
				for i in range(1, head_len):
					var q = i / 2
					valid_hexes.append(HexCoord.new(q - 1, -i))
					valid_hexes.append(HexCoord.new(q + 1, -i))
					
			if rarity >= HexTile.Rarity.LEGENDARY:
				for i in range(1, head_len - 1):
					var q = i / 2
					valid_hexes.append(HexCoord.new(q - 2, -i))
					valid_hexes.append(HexCoord.new(q + 2, -i))
					
		HexTile.BodySlot.BACKPACK:
			# Backpack is a wide horizontal cluster
			var pack_width = 3
			var pack_height = 2
			if rarity >= HexTile.Rarity.UNCOMMON: pack_width = 4; pack_height = 3
			if rarity >= HexTile.Rarity.RARE: pack_width = 5; pack_height = 4
			if rarity >= HexTile.Rarity.LEGENDARY: pack_width = 7; pack_height = 5
			
			for q in range(-pack_width/2, pack_width/2 + 1):
				for r in range(-pack_height/2, pack_height/2 + 1):
					valid_hexes.append(HexCoord.new(q, r))
			
		HexTile.BodySlot.TORSO:
			# Torso is symmetrical. Starts at 0,0 and grows outwards
			valid_hexes.append(HexCoord.new(0, 0)) # Core
			var radius = 1
			while valid_hexes.size() < base_count:
				# Add a ring
				for q in range(-radius, radius + 1):
					for r in range(-radius, radius + 1):
						if valid_hexes.size() >= base_count: break
						if abs(q + r) <= radius:
							# Role specific filtering
							if role_variant == "scout" and abs(q) > 1: continue # Thin scout torso
							if role_variant == "brawler" and abs(r) > 1: continue # Wide brawler torso
							
							var h = HexCoord.new(q, r)
							# In axial, symmetry across vertical axis (x=0) is: q -> -q-r, r -> r
							var h_sym = HexCoord.new(-q - r, r)
							
							var found_h = false
							for existing in valid_hexes:
								if existing.q == h.q and existing.r == h.r: found_h = true
							if not found_h:
								valid_hexes.append(h)
								
							if valid_hexes.size() < base_count:
								var found_sym = false
								for existing in valid_hexes:
									if existing.q == h_sym.q and existing.r == h_sym.r: found_sym = true
								if not found_sym:
									valid_hexes.append(h_sym)
				radius += 1
				
		HexTile.BodySlot.ARM_L, HexTile.BodySlot.ARM_R:
			# Arms are long and narrow. 
			var dir_q = -1 if slot_type == HexTile.BodySlot.ARM_L else 1
			var width = 2 if rarity <= HexTile.Rarity.UNCOMMON else 3
			
			if role_variant == "scout": width = 1
			if role_variant == "brawler": width = 3 if rarity <= HexTile.Rarity.UNCOMMON else 4
			
			var length = base_count / width
			
			if role_variant == "sniper" and slot_type == HexTile.BodySlot.ARM_R:
				width = 1
				length = base_count # Super long rifle arm
			
			for l in range(length):
				for w in range(width):
					if valid_hexes.size() >= base_count: break
					valid_hexes.append(HexCoord.new(dir_q * l, w - width/2))
					
		HexTile.BodySlot.LEG_L, HexTile.BodySlot.LEG_R:
			# Legs are bulky rectangles downwards, tilted outward
			var is_left = slot_type == HexTile.BodySlot.LEG_L
			var width = 3 if rarity <= HexTile.Rarity.UNCOMMON else 4
			
			if role_variant == "scout": width = 2
			if role_variant == "brawler": width = 4 if rarity <= HexTile.Rarity.UNCOMMON else 5
			
			var length = base_count / width
			for l in range(length):
				var tilt = l / 2
				if role_variant == "scout": tilt = l # more tilted/lithe
				var shift = -tilt # Make both legs look like the left leg
				for w in range(width):
					if valid_hexes.size() >= base_count: break
					valid_hexes.append(HexCoord.new(w - width/2 + shift, l))
					
		_:
			# Fallback generic shape
			for q in range(grid_width):
				for r in range(grid_height):
					valid_hexes.append(HexCoord.new(q, r))

func can_place_tile(coord: HexCoord) -> bool:
	var is_valid = false
	for h in valid_hexes:
		if h.q == coord.q and h.r == coord.r:
			is_valid = true
			break
	return is_valid

func add_infusion_xp(amount: int):
	infusion_xp += amount
	var needed = 500 + (infusion_level * 500)
	while infusion_xp >= needed:
		infusion_xp -= needed
		infusion_level += 1
		_roll_stat_modifier()
		needed = 500 + (infusion_level * 500)

func _roll_stat_modifier():
	if rarity < load("res://scripts/core/HexTile.gd").Rarity.LEGENDARY: return # Only legendary gear can be augmented
	
	var possible_stats = ["kin_mult", "fire_mult", "ice_mult", "vtx_mult", "ltg_mult", "psn_mult", "exp_mult", "prc_mult", "vmp_mult", "dmg_mult", "spd_mult"]
	var roll = possible_stats[randi() % possible_stats.size()]
	
	if stat_modifiers.has(roll):
		stat_modifiers[roll] += 0.05 # Add 5%
	else:
		stat_modifiers[roll] = 1.05 # Start at 105%

static func create_starter_torso(role: String = "", p_rarity: int = HexTile.Rarity.COMMON):
	var script = load("res://scripts/core/ComponentEquipment.gd")
	var torso = script.new(HexTile.BodySlot.TORSO, p_rarity)
	torso.component_name = "Torso"
	torso.role_variant = role
	torso.generate_shape() # Generates a shape
	
	# Add a Core at (0,0)
	var core_tile = load("res://scripts/tiles/CoreTile.gd").new()
	core_tile.body_slot = HexTile.BodySlot.TORSO
	torso.hex_grid.add_tile(HexCoord.new(0, 0), core_tile)
	torso.fixed_sinks.append(HexCoord.new(0, 0))
		
	# Find outermost Q for arms
	var min_q = 0
	var max_q = 0
	for h in torso.valid_hexes:
		if h.q < min_q: min_q = h.q
		if h.q > max_q: max_q = h.q
		
	# Add Sink for Left Arm
	var l_arm_sink = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.ARM_L, true)
	l_arm_sink.body_slot = HexTile.BodySlot.TORSO
	torso.hex_grid.add_tile(HexCoord.new(min_q, 0), l_arm_sink)
	torso.fixed_sinks.append(HexCoord.new(min_q, 0))
		
	# Add Sink for Right Arm
	var r_arm_sink = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.ARM_R, true)
	r_arm_sink.body_slot = HexTile.BodySlot.TORSO
	torso.hex_grid.add_tile(HexCoord.new(max_q, 0), r_arm_sink)
	torso.fixed_sinks.append(HexCoord.new(max_q, 0))
	
	# Find outermost R for head and legs
	var min_r = 0
	var max_r = 0
	for h in torso.valid_hexes:
		if h.r < min_r: min_r = h.r
		if h.r > max_r: max_r = h.r
		
	# Add Sink for Head (Top)
	var head_sink = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.HEAD, true)
	head_sink.body_slot = HexTile.BodySlot.TORSO
	torso.hex_grid.add_tile(HexCoord.new(0, min_r), head_sink)
	torso.fixed_sinks.append(HexCoord.new(0, min_r))
	
	# Add Sink for Left Leg (Bottom Left)
	var l_leg_sink = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.LEG_L, true)
	l_leg_sink.body_slot = HexTile.BodySlot.TORSO
	torso.hex_grid.add_tile(HexCoord.new(-1, max_r), l_leg_sink)
	torso.fixed_sinks.append(HexCoord.new(-1, max_r))
	
	# Add Sink for Right Leg (Bottom Right)
	var r_leg_sink = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.LEG_R, true)
	r_leg_sink.body_slot = HexTile.BodySlot.TORSO
	torso.hex_grid.add_tile(HexCoord.new(1, max_r), r_leg_sink)
	torso.fixed_sinks.append(HexCoord.new(1, max_r))
	
	# Add Sink for Accessory Return (receives energy from Head/Backpack, acts as Input)
	var head_return_sink = load("res://scripts/tiles/ComponentLinkTile.gd").new()
	head_return_sink.body_slot = HexTile.BodySlot.TORSO
	head_return_sink.tile_type = "Accessory Return"
	torso.hex_grid.add_tile(HexCoord.new(0, min_r + 1), head_return_sink)
	torso.fixed_sinks.append(HexCoord.new(0, min_r + 1))
	
	# Add Sink for Backpack
	var backpack_sink = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.BACKPACK, true)
	backpack_sink.body_slot = HexTile.BodySlot.TORSO
	torso.hex_grid.add_tile(HexCoord.new(0, 1), backpack_sink)
	torso.fixed_sinks.append(HexCoord.new(0, 1))
	
	if role != "":
		var ai_mount = load("res://scripts/tiles/WeaponMountTile.gd").new()
		ai_mount.body_slot = HexTile.BodySlot.TORSO
		var ai_mount_pos = HexCoord.new(1, -1)
		for h in torso.valid_hexes:
			if not torso.hex_grid.has_tile(h):
				ai_mount_pos = h
				break
		torso.hex_grid.add_tile(ai_mount_pos, ai_mount)
		torso.fixed_sinks.append(ai_mount_pos)
		
		var ai_core = load("res://scripts/tiles/MicrocoreTile.gd").new()
		ai_core.power_output = 50.0
		var ai_core_pos = null
		for d in range(6):
			var n = ai_mount_pos.neighbor(d)
			for h in torso.valid_hexes:
				if h.equals(n) and not torso.hex_grid.has_tile(h):
					ai_core_pos = h
					ai_core.active_faces.clear()
					ai_core.active_faces.append((d + 3) % 6)
					break
			if ai_core_pos:
				break
		if ai_core_pos:
			torso.hex_grid.add_tile(ai_core_pos, ai_core)
	
	return torso
	
static func create_starter_arm(is_left: bool, role: String = "", p_rarity: int = HexTile.Rarity.COMMON):
	var script = load("res://scripts/core/ComponentEquipment.gd")
	var slot = HexTile.BodySlot.ARM_L if is_left else HexTile.BodySlot.ARM_R
	var arm = script.new(slot, p_rarity)
	arm.component_name = "L. Arm" if is_left else "R. Arm"
	arm.role_variant = role
	arm.generate_shape()
	
	# Add a Weapon Mount at the furthest extent
	var max_q = 0
	var mount_h = HexCoord.new(0, 0)
	var dir = -1 if is_left else 1
	for h in arm.valid_hexes:
		if h.q * dir > max_q * dir:
			max_q = h.q
			mount_h = HexCoord.new(h.q, h.r)
			
	var mount = load("res://scripts/tiles/WeaponMountTile.gd").new()
	mount.body_slot = slot
	arm.hex_grid.add_tile(mount_h, mount)
	arm.fixed_sinks.append(mount_h)
	
	if role != "":
		var ai_core = load("res://scripts/tiles/MicrocoreTile.gd").new()
		ai_core.power_output = 50.0
		var ai_core_pos = null
		for d in range(6):
			var n = mount_h.neighbor(d)
			for h in arm.valid_hexes:
				if h.equals(n) and not arm.hex_grid.has_tile(h):
					ai_core_pos = h
					ai_core.active_faces.clear()
					ai_core.active_faces.append((d + 3) % 6)
					break
			if ai_core_pos:
				break
		if ai_core_pos:
			arm.hex_grid.add_tile(ai_core_pos, ai_core)
	
	return arm

static func create_starter_leg(is_left: bool, role: String = "", p_rarity: int = HexTile.Rarity.COMMON):
	var script = load("res://scripts/core/ComponentEquipment.gd")
	var slot = HexTile.BodySlot.LEG_L if is_left else HexTile.BodySlot.LEG_R
	var leg = script.new(slot, p_rarity)
	leg.component_name = "L. Leg" if is_left else "R. Leg"
	leg.role_variant = role
	leg.generate_shape()
	
	# Add Actuator at bottom
	var max_r = 0
	var mount_h = HexCoord.new(0, 0)
	for h in leg.valid_hexes:
		if h.r > max_r:
			max_r = h.r
			mount_h = HexCoord.new(h.q, h.r)
			
	var actuator = load("res://scripts/tiles/ActuatorTile.gd").new()
	actuator.body_slot = slot
	leg.hex_grid.add_tile(mount_h, actuator)
	leg.fixed_sinks.append(mount_h)
	
	return leg

static func create_starter_head(role: String = "", p_rarity: int = HexTile.Rarity.COMMON):
	var script = load("res://scripts/core/ComponentEquipment.gd")
	var head = script.new(HexTile.BodySlot.HEAD, p_rarity)
	head.component_name = "Head"
	head.role_variant = role
	head.generate_shape()
	
	var min_r = 0
	for h in head.valid_hexes:
		if h.r < min_r: min_r = h.r
		
	var tor_return = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.TORSO, true)
	tor_return.tile_type = "Torso Return"
	tor_return.body_slot = HexTile.BodySlot.HEAD
	head.hex_grid.add_tile(HexCoord.new(0, min_r), tor_return)
	head.fixed_sinks.append(HexCoord.new(0, min_r))
	
	return head

static func create_starter_backpack(role: String = "", p_rarity: int = HexTile.Rarity.COMMON):
	var script = load("res://scripts/core/ComponentEquipment.gd")
	var pack = script.new(HexTile.BodySlot.BACKPACK, p_rarity)
	pack.component_name = "Backpack"
	pack.role_variant = role
	pack.generate_shape()
	
	var core = load("res://scripts/tiles/MicrocoreTile.gd").new()
	core.body_slot = HexTile.BodySlot.BACKPACK
	pack.hex_grid.add_tile(HexCoord.new(0, 0), core)
	
	var max_r = 0
	for h in pack.valid_hexes:
		if h.r > max_r: max_r = h.r
		
	var tor_return = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.TORSO, true)
	tor_return.tile_type = "Torso Return"
	tor_return.body_slot = HexTile.BodySlot.BACKPACK
	pack.hex_grid.add_tile(HexCoord.new(0, max_r), tor_return)
	pack.fixed_sinks.append(HexCoord.new(0, max_r))
	
	return pack

static func create_shield_backpack():
	var script = load("res://scripts/core/ComponentEquipment.gd")
	var pack = script.new(HexTile.BodySlot.BACKPACK, HexTile.Rarity.MYTHIC)
	pack.component_name = "Mythic Shield"
	pack.generate_shape()
	
	var shield_class = load("res://scripts/tiles/ShieldTile.gd")
	if shield_class:
		var shield = shield_class.new()
		shield.rarity = HexTile.Rarity.MYTHIC
		shield.body_slot = HexTile.BodySlot.BACKPACK
		pack.hex_grid.add_tile(HexCoord.new(0, 0), shield)
		
	var max_r = 0
	for h in pack.valid_hexes:
		if h.r > max_r: max_r = h.r
		
	var tor_return = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.TORSO, true)
	tor_return.tile_type = "Torso Return"
	tor_return.body_slot = HexTile.BodySlot.BACKPACK
	pack.hex_grid.add_tile(HexCoord.new(0, max_r), tor_return)
	pack.fixed_sinks.append(HexCoord.new(0, max_r))
		
	return pack

static func create_jetpack_backpack():
	var script = load("res://scripts/core/ComponentEquipment.gd")
	var pack = script.new(HexTile.BodySlot.BACKPACK, HexTile.Rarity.UNCOMMON)
	pack.component_name = "Jetpack"
	pack.generate_shape()
	return pack

static func create_missile_backpack():
	var script = load("res://scripts/core/ComponentEquipment.gd")
	var pack = script.new(HexTile.BodySlot.BACKPACK, HexTile.Rarity.LEGENDARY)
	pack.component_name = "Missile Pod"
	pack.generate_shape()
	
	# Pre-wire with microcores and mounts
	var microcore_class = load("res://scripts/tiles/MicrocoreTile.gd")
	var mount_class = load("res://scripts/tiles/WeaponMountTile.gd")
	
	# Add 3 Microcores (Legendary)
	for i in range(3):
		var core = microcore_class.new()
		core.rarity = HexTile.Rarity.LEGENDARY
		core.active_faces.clear()
		core.active_faces.append_array([1, 5]) # Output left and right
		core.set_face_output(1, (i % 6) + 1) # Set specific synergy
		core.set_face_output(5, (i % 6) + 1)
		# Just drop them in arbitrary valid positions for now
		if pack.valid_hexes.size() > i:
			pack.hex_grid.add_tile(pack.valid_hexes[i], core)
			
	# Add 6 Mounts (Legendary)
	var offset = 3
	for i in range(6):
		var mount = mount_class.new()
		mount.rarity = HexTile.Rarity.LEGENDARY
		if pack.valid_hexes.size() > offset + i:
			pack.hex_grid.add_tile(pack.valid_hexes[offset + i], mount)
			
	return pack

func update_link_positions():
	if slot_type != load("res://scripts/core/HexTile.gd").BodySlot.TORSO:
		return
		
	var min_q = 0
	var max_q = 0
	var min_r = 0
	var max_r = 0
	for h in valid_hexes:
		if h.q < min_q: min_q = h.q
		if h.q > max_q: max_q = h.q
		if h.r < min_r: min_r = h.r
		if h.r > max_r: max_r = h.r
		
	var new_sinks: Array[HexCoord] = []
	new_sinks.append(HexCoord.new(0, 0)) # Core
	
	var all_hexes = hex_grid.grid.keys()
	var tiles_to_move = [] # Array of Dicts: {tile, old_coord, new_coord}
	
	for key in all_hexes:
		var h = HexCoord.new(key.x, key.y)
		var tile = hex_grid.get_tile(h)
		if tile.tile_type == "Component Link":
			var new_coord = h
			if tile.target_slot == load("res://scripts/core/HexTile.gd").BodySlot.ARM_L:
				new_coord = HexCoord.new(min_q, 0)
			elif tile.target_slot == load("res://scripts/core/HexTile.gd").BodySlot.ARM_R:
				new_coord = HexCoord.new(max_q, 0)
			elif tile.target_slot == load("res://scripts/core/HexTile.gd").BodySlot.HEAD:
				new_coord = HexCoord.new(0, min_r)
			elif tile.target_slot == load("res://scripts/core/HexTile.gd").BodySlot.LEG_L:
				new_coord = HexCoord.new(-1, max_r)
			elif tile.target_slot == load("res://scripts/core/HexTile.gd").BodySlot.LEG_R:
				new_coord = HexCoord.new(1, max_r)
			
			if new_coord.q != h.q or new_coord.r != h.r:
				tiles_to_move.append({"tile": tile, "old": h, "new": new_coord})
			else:
				new_sinks.append(new_coord)
				
	for move in tiles_to_move:
		hex_grid.remove_tile(move.old)
		hex_grid.add_tile(move.new, move.tile)
		new_sinks.append(move.new)
		
	fixed_sinks = new_sinks
