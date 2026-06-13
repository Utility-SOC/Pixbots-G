extends CanvasLayer

const CoreTile = preload("res://scripts/tiles/CoreTile.gd")

var panel: PanelContainer
var is_open: bool = false

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100 # Always on top
	
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 400)
	panel.position = Vector2(20, 20)
	panel.hide()
	add_child(panel)
	
	var vbox = VBoxContainer.new()
	panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "--- DEBUG MENU ---"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var btn_spawn = Button.new()
	btn_spawn.text = "Spawn Enemy"
	btn_spawn.pressed.connect(_on_spawn_enemy)
	vbox.add_child(btn_spawn)
	
	var btn_spawn_mass = Button.new()
	btn_spawn_mass.text = "Spawn Army (50)"
	btn_spawn_mass.pressed.connect(func():
		for i in range(50): _on_spawn_enemy()
	)
	vbox.add_child(btn_spawn_mass)
	
	var btn_loot = Button.new()
	btn_loot.text = "Force Legendary Drop"
	btn_loot.pressed.connect(_on_force_loot)
	vbox.add_child(btn_loot)
	
	var btn_heal = Button.new()
	btn_heal.text = "Heal Player"
	btn_heal.pressed.connect(_on_heal_player)
	vbox.add_child(btn_heal)
	
	var btn_time = Button.new()
	btn_time.text = "Toggle Slomo (0.2x)"
	btn_time.pressed.connect(func():
		Engine.time_scale = 0.2 if Engine.time_scale == 1.0 else 1.0
	)
	vbox.add_child(btn_time)
	
	var btn_restore = Button.new()
	btn_restore.text = "Restore Lost Components (2 Sets)"
	btn_restore.pressed.connect(_on_restore_components)
	vbox.add_child(btn_restore)
	
	var btn_garage = Button.new()
	btn_garage.text = "Teleport to Garage"
	btn_garage.pressed.connect(func():
		_toggle_menu()
		var main = get_tree().current_scene
		if main and main.has_method("_open_garage"):
			main._open_garage()
	)
	vbox.add_child(btn_garage)
	
	var spawn_as_label = Label.new()
	spawn_as_label.text = "-- Spawn Map As --"
	spawn_as_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(spawn_as_label)
	
	var map_grid = GridContainer.new()
	map_grid.columns = 3
	vbox.add_child(map_grid)
	
	var map_types = ["Normal", "Arena", "Open Field", "Desert", "Forest", "Tundra", "Volcano", "Dungeon", "Water"]
	var map_colors = [Color(0.4, 0.8, 0.4), Color(0.15, 0.1, 0.2), Color(0.4, 0.8, 0.4), Color(0.9, 0.8, 0.5), Color(0.1, 0.5, 0.2), Color(0.8, 0.9, 0.9), Color(0.3, 0.1, 0.1), Color(0.15, 0.1, 0.2), Color(0.2, 0.4, 0.9)]
	
	for i in range(map_types.size()):
		var map_type = map_types[i]
		var color = map_colors[i]
		
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(80, 80)
		
		var rect = ColorRect.new()
		rect.color = color
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(rect)
		
		var lbl = Label.new()
		lbl.text = map_type
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", 2)
		btn.add_child(lbl)
		
		btn.pressed.connect(func():
			_toggle_menu()
			var main = get_tree().current_scene
			var map = main.get_node_or_null("GameMap")
			if map:
				map.map_type = map_type
				map._generate_map()
				map._draw_map_to_texture()
				map._build_navigation()
		)
		map_grid.add_child(btn)
	
	var btn_legendary_core = Button.new()
	btn_legendary_core.text = "Upgrade Core to Legendary"
	btn_legendary_core.pressed.connect(_on_upgrade_core)
	vbox.add_child(btn_legendary_core)
	
	var btn_legendary_body = Button.new()
	btn_legendary_body.text = "Upgrade All Body Parts to Legendary"
	btn_legendary_body.pressed.connect(_on_upgrade_body_parts)
	vbox.add_child(btn_legendary_body)
	
	var btn_amped_grid = Button.new()
	btn_amped_grid.text = "Give AMPED Grid (Edge Loops)"
	btn_amped_grid.pressed.connect(_on_amped_grid)
	vbox.add_child(btn_amped_grid)
	
	var opt_reactor = OptionButton.new()
	opt_reactor.add_item("Reactor: KINETIC", 1)
	opt_reactor.add_item("Reactor: FIRE", 2)
	opt_reactor.add_item("Reactor: POISON", 3)
	opt_reactor.add_item("Reactor: LIGHTNING", 4)
	opt_reactor.add_item("Reactor: VAMPIRE", 5)
	opt_reactor.add_item("Reactor: VORTEX", 6)
	opt_reactor.item_selected.connect(_on_reactor_changed)
	vbox.add_child(opt_reactor)

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_QUOTELEFT: # The ` key
			_toggle_menu()

func _toggle_menu():
	is_open = not is_open
	panel.visible = is_open
	get_tree().paused = is_open

func _on_spawn_enemy():
	var main = get_tree().current_scene
	var director = main.get_node_or_null("SquadDirector")
	
	if not director:
		director = load("res://scripts/ai/SquadDirector.gd").new()
		director.name = "SquadDirector"
		main.add_child(director)
		
		# Register default templates just in case
		var t_sniper = load("res://scripts/ai/SquadTemplate.gd").new("Sniper Team", {"sniper": 2, "brawler": 1})
		director.register_template(t_sniper)
		var t_recon = load("res://scripts/ai/SquadTemplate.gd").new("Recon", {"scout": 3})
		director.register_template(t_recon)
		var t_assault = load("res://scripts/ai/SquadTemplate.gd").new("Assault", {"brawler": 2, "flamethrower": 1})
		director.register_template(t_assault)
		var t_ambush = load("res://scripts/ai/SquadTemplate.gd").new("Ambushers", {"ambusher": 3})
		director.register_template(t_ambush)
	
	if director:
		var roles = ["sniper", "brawler", "scout", "ambusher", "flamethrower"]
		var role = roles.pick_random()
		var rand_rarity = randi() % 4
		var mech = director._spawn_bot_for_role(role, false, rand_rarity)
		mech.global_position = Vector2(randf_range(200, 1000), randf_range(200, 1000))
		mech.collision_layer = 4
		mech.collision_mask = 1 | 2 | 8
		var player = get_tree().get_nodes_in_group("player")
		if player.size() > 0:
			mech.target = player[0]

func _on_force_loot():
	var player = get_tree().get_nodes_in_group("player")
	if player.size() > 0:
		var tile_classes = [
			preload("res://scripts/tiles/AmplifierTile.gd"),
			preload("res://scripts/tiles/ReflectorTile.gd"),
			preload("res://scripts/tiles/SplitterTile.gd"),
			preload("res://scripts/tiles/WeaponMountTile.gd"),
			preload("res://scripts/tiles/InfuserTile.gd"),
			preload("res://scripts/tiles/AccumulatorTile.gd"),
			preload("res://scripts/tiles/CatalystTile.gd"),
			preload("res://scripts/tiles/DirectionalConduitTile.gd"),
			preload("res://scripts/tiles/FilterTile.gd"),
			preload("res://scripts/tiles/ResonatorTile.gd")
		]
		var script = tile_classes.pick_random()
		var tile = script.new()
		tile.rarity = HexTile.Rarity.LEGENDARY
		var drop = load("res://scripts/entities/LootPickup.gd").new()
		drop.tile_data = tile
		drop.global_position = player[0].global_position + Vector2(50, 50)
		get_tree().current_scene.add_child(drop)

func _on_heal_player():
	var player = get_tree().get_nodes_in_group("player")
	if player.size() > 0:
		player[0].hp = player[0].max_hp

func _on_upgrade_core():
	var player = get_tree().get_nodes_in_group("player")
	if player.size() > 0:
		var mech = player[0]
		if mech.components.has(HexTile.BodySlot.TORSO):
			var torso = mech.components[HexTile.BodySlot.TORSO]
			for tile in torso.hex_grid.get_all_tiles():
				if tile is CoreTile:
					tile.rarity = HexTile.Rarity.LEGENDARY
					tile.active_faces.clear()
					tile.active_faces.append_array([0, 1, 2, 3, 4, 5])
					# Assign different synergies to each face
					tile.set_face_output(0, 1) # KINETIC
					tile.set_face_output(1, 2) # FIRE
					tile.set_face_output(2, 3) # ICE
					tile.set_face_output(3, 4) # POISON
					tile.set_face_output(4, 5) # LIGHTNING
					tile.set_face_output(5, 7) # VORTEX
					print("[Debug] Core upgraded to Legendary with all synergies!")

func _on_upgrade_body_parts():
	var player = get_tree().get_nodes_in_group("player")
	if player.size() > 0:
		var mech = player[0]
		var slots = [load("res://scripts/core/HexTile.gd").BodySlot.TORSO, 
					 load("res://scripts/core/HexTile.gd").BodySlot.HEAD, 
					 load("res://scripts/core/HexTile.gd").BodySlot.LEG_L, 
					 load("res://scripts/core/HexTile.gd").BodySlot.LEG_R, 
					 load("res://scripts/core/HexTile.gd").BodySlot.ARM_L, 
					 load("res://scripts/core/HexTile.gd").BodySlot.ARM_R,
					 load("res://scripts/core/HexTile.gd").BodySlot.BACKPACK]
		
		for slot in slots:
			if mech.components.has(slot):
				var comp = mech.components[slot]
				comp.rarity = load("res://scripts/core/HexTile.gd").Rarity.LEGENDARY
				comp.generate_shape()
				comp.update_link_positions()
				print("[Debug] Upgraded slot ", slot, " to Legendary!")
				
		var renderer = mech.get_node_or_null("MechRenderer")
		if renderer:
			renderer._rebuild_visuals()

func _on_amped_grid():
	var main = get_tree().current_scene
	if main and main.get("player") != null:
		var mech = main.player
		var slots = [load("res://scripts/core/HexTile.gd").BodySlot.TORSO, 
					 load("res://scripts/core/HexTile.gd").BodySlot.HEAD, 
					 load("res://scripts/core/HexTile.gd").BodySlot.LEG_L, 
					 load("res://scripts/core/HexTile.gd").BodySlot.LEG_R, 
					 load("res://scripts/core/HexTile.gd").BodySlot.ARM_L, 
					 load("res://scripts/core/HexTile.gd").BodySlot.ARM_R,
					 load("res://scripts/core/HexTile.gd").BodySlot.BACKPACK]
		
		var classes = [
			load("res://scripts/tiles/SplitterTile.gd"),
			load("res://scripts/tiles/AmplifierTile.gd"),
			load("res://scripts/tiles/ReflectorTile.gd")
		]
		
		for slot in slots:
			if mech.components.has(slot):
				var comp = mech.components[slot]
				
				# Find max distance to identify outer edge
				var center = load("res://scripts/core/HexCoord.gd").new(0, 0)
				var max_dist = 0
				for h in comp.valid_hexes:
					if h.distance(center) > max_dist:
						max_dist = h.distance(center)
						
				# Place alternating tiles on the edge
				var edge_hexes = []
				for h in comp.valid_hexes:
					if h.distance(center) == max_dist and not comp.hex_grid.has_tile(h):
						edge_hexes.append(h)
						
				for i in range(edge_hexes.size()):
					var h = edge_hexes[i]
					var tile_class = classes[i % 3]
					var tile = tile_class.new()
					tile.rarity = load("res://scripts/core/HexTile.gd").Rarity.LEGENDARY
					tile.active_faces.clear()
					tile.active_faces.append_array([0, 1, 2, 3, 4, 5])
					comp.hex_grid.add_tile(h, tile)
					
		mech.is_grid_dirty = true
		print("[Debug] AMPED Grid applied to all components!")
		
		var renderer = mech.get_node_or_null("MechRenderer")
		if renderer:
			renderer._rebuild_visuals()
			
		main = get_tree().current_scene
		if main and main.get("player_inventory") != null:
			for i in range(20):
				var tile = preload("res://scripts/tiles/SplitterTile.gd").new()
				tile.rarity = load("res://scripts/core/HexTile.gd").Rarity.LEGENDARY
				main.player_inventory.append(tile)
				if main.get("garage_ui") != null and main.garage_ui.get("inventory") != null:
					# Ensure it's in the Garage inventory if they are different arrays
					if main.garage_ui.inventory != main.player_inventory:
						main.garage_ui.inventory.append(tile)
						
		if main and main.get("garage_ui") != null:
			if main.garage_ui.has_method("_refresh_grid_ui"):
				main.garage_ui._refresh_grid_ui()
			if main.garage_ui.has_method("_refresh_inventory_ui"):
				main.garage_ui._refresh_inventory_ui()

func _on_reactor_changed(index: int):
	var player = get_tree().get_nodes_in_group("player")
	if player.size() > 0:
		var grid = player[0].get_node("HexGridComponent")
		if grid:
			var core = grid.get_tile(0, 0)
			if core and core is CoreTile:
				for i in range(6):
					core.set_face_output(i, index + 1)
				print("[Debug] Reactor output overridden to synergy ID: ", index + 1)

func _on_restore_components():
	var main = get_tree().current_scene
	if main and main.get("player") != null:
		var ScriptComponentEquipment = load("res://scripts/core/ComponentEquipment.gd")
		var rarity = load("res://scripts/core/HexTile.gd").Rarity.LEGENDARY
		
		# Generate 2 full sets
		for i in range(2):
			var comps = [
				ScriptComponentEquipment.create_starter_torso("Legendary Torso", rarity),
				ScriptComponentEquipment.create_starter_head("Legendary Head", rarity),
				ScriptComponentEquipment.create_starter_arm(true, "Legendary Arm L", rarity),
				ScriptComponentEquipment.create_starter_arm(false, "Legendary Arm R", rarity),
				ScriptComponentEquipment.create_starter_leg(true, "Legendary Leg L", rarity),
				ScriptComponentEquipment.create_starter_leg(false, "Legendary Leg R", rarity),
				ScriptComponentEquipment.create_jetpack_backpack()
			]
			# Set the backpack rarity to legendary too
			comps[6].rarity = rarity
			
			for c in comps:
				if main.get("player_component_inventory") != null:
					main.player_component_inventory.append(c)
					
				# If this is the first set, automatically equip them
				if i == 0:
					main.player.equip_component(c)
					
		if main.get("garage_ui") != null:
			if main.garage_ui.has_method("_refresh_component_ui"):
				main.garage_ui._refresh_component_ui()
			if main.garage_ui.has_method("_refresh_grid_ui"):
				main.garage_ui._refresh_grid_ui()
		print("[Debug] Restored 2 full sets of Legendary components!")

