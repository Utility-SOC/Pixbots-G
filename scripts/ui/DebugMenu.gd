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
	
	var btn_garage = Button.new()
	btn_garage.text = "Teleport to Garage"
	btn_garage.pressed.connect(func():
		_toggle_menu()
		var main = get_tree().current_scene
		if main and main.has_method("_open_garage"):
			main._open_garage()
	)
	vbox.add_child(btn_garage)
	
	var btn_arena = Button.new()
	btn_arena.text = "Regenerate as Arena"
	btn_arena.pressed.connect(func():
		_toggle_menu()
		var main = get_tree().current_scene
		var map = main.get_node_or_null("GameMap")
		if map:
			map.map_type = "Arena"
			map._generate_map()
			map._draw_map_to_texture()
			map._build_navigation()
	)
	vbox.add_child(btn_arena)
	
	var btn_legendary_core = Button.new()
	btn_legendary_core.text = "Upgrade Core to Legendary"
	btn_legendary_core.pressed.connect(_on_upgrade_core)
	vbox.add_child(btn_legendary_core)
	
	var btn_legendary_body = Button.new()
	btn_legendary_body.text = "Upgrade All Body Parts to Legendary"
	btn_legendary_body.pressed.connect(_on_upgrade_body_parts)
	vbox.add_child(btn_legendary_body)
	
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
