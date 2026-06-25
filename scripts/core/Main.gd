extends Node2D
const MapGenerator = preload("res://scripts/core/MapGenerator.gd")
const Mech = preload("res://scripts/entities/Mech.gd")
const HexCoord = preload("res://scripts/core/HexCoord.gd")
const WeaponMountTile = preload("res://scripts/tiles/WeaponMountTile.gd")

var current_mode: String = "sandbox"
var current_wave: int = 1
var campaign_data: Dictionary = {}
var active_enemies: int = 0

var map: MapGenerator
var garage_ui: CanvasLayer
var player: Mech
var player_inventory: Array = []
var player_component_inventory: Array = []

func _ready():
	_load_campaign()
	_setup_environment()
	_setup_player()
	
	# Assume Sandbox mode defaults for now if not set by MainMenu
	_start_intermission()

func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel"):
		if not get_tree().paused:
			get_tree().paused = true
			var pause_menu = load("res://scripts/ui/PauseMenu.gd").new()
			add_child(pause_menu)

func _load_campaign():
	var file = FileAccess.open("res://campaign.json", FileAccess.READ)
	if file:
		var text = file.get_as_text()
		var json = JSON.new()
		if json.parse(text) == OK:
			campaign_data = json.data

func _setup_environment():
	map = MapGenerator.new()
	map.map_type = "Open Field"
	map.name = "GameMap"
	add_child(map)

func _setup_player():
	player = Mech.new()
	player.is_player = true
	player.name = "PlayerMech"
	
	# Player is Layer 4 (bit 3). 
	player.collision_layer = 8
	player.collision_mask = 1 | 2 | 4 # Collides with environment, water, enemies
	
	player.global_position = map.get_valid_spawn_position(Vector2(map.width * map.tile_size / 2.0, map.height * map.tile_size / 2.0))
	
	add_child(player)
	player.add_to_group("player")
	
	if SaveManager.save_to_load != "":
		var load_data = SaveManager.load_game(SaveManager.save_to_load)
		if load_data.has("components") and not load_data["components"].is_empty():
			for slot in player.components.keys():
				player.components[slot].queue_free()
			player.components.clear()
			for slot in load_data["components"].keys():
				player.equip_component(load_data["components"][slot])
				
		if load_data.has("inventory"):
			player_inventory = load_data["inventory"]
		if load_data.has("component_inventory"):
			player_component_inventory = load_data["component_inventory"]
	else:
		_initialize_starter_inventory()
	
	var camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 5.0
	camera.zoom = Vector2(1.5, 1.5)
	player.add_child(camera)
	
	# Pre-calculate weapons so the first shot doesn't freeze the game
	player._recalculate_grid()

func _initialize_starter_inventory():
	player_inventory.clear()
	player_component_inventory.clear()
	
	var rarities = [HexTile.Rarity.COMMON, HexTile.Rarity.UNCOMMON, HexTile.Rarity.RARE, HexTile.Rarity.LEGENDARY]
	var classes = [
		preload("res://scripts/tiles/SplitterTile.gd"),
		preload("res://scripts/tiles/ReflectorTile.gd"),
		preload("res://scripts/tiles/AmplifierTile.gd")
	]
	
	# 3 of each rarity for Splitter, Reflector, Amplifier
	for r in rarities:
		for c in classes:
			for i in range(3):
				var tile = c.new()
				tile.rarity = r
				player_inventory.append(tile)
				
	# Add 20 Legendary Splitters per user request
	for i in range(20):
		var tile = preload("res://scripts/tiles/SplitterTile.gd").new()
		tile.rarity = HexTile.Rarity.LEGENDARY
		player_inventory.append(tile)
				
	# Add Magnets
	for r in rarities:
		for i in range(5):
			var tile = load("res://scripts/tiles/MagnetTile.gd").new()
			tile.rarity = r
			player_inventory.append(tile)
				
	# Add Infusers
	var poison_infuser = load("res://scripts/tiles/InfuserTile.gd").new()
	poison_infuser.rarity = HexTile.Rarity.RARE
	poison_infuser.secondary_synergy = 3 # POISON
	player_inventory.append(poison_infuser)
	
	var fire_infuser = load("res://scripts/tiles/InfuserTile.gd").new()
	fire_infuser.rarity = HexTile.Rarity.RARE
	fire_infuser.secondary_synergy = 1 # FIRE
	player_inventory.append(fire_infuser)
	
	# Add Catalyst
	var leg_cat = load("res://scripts/tiles/CatalystTile.gd").new()
	leg_cat.rarity = HexTile.Rarity.LEGENDARY
	player_inventory.append(leg_cat)

	# Add Jumpjets for Water Traversal
	for i in range(2):
		var jj = load("res://scripts/tiles/JumpjetTile.gd").new()
		jj.rarity = HexTile.Rarity.UNCOMMON
		player_inventory.append(jj)

func _start_intermission():
	if current_wave > 1 and (current_wave - 1) % 5 == 0:
		_open_garage()
		return
		
	_show_countdown()

func _show_countdown():
	print("--- Wave ", current_wave, " starting in 5 seconds! ---")
	var timer = Timer.new()
	timer.wait_time = 5.0
	timer.one_shot = true
	timer.timeout.connect(_start_wave)
	add_child(timer)
	timer.start()

func _start_wave():
	print("--- WAVE ", current_wave, " COMMENCING ---")
	
	# Spawn Squad Director if it doesn't exist
	var director = get_node_or_null("SquadDirector")
	if not director:
		director = load("res://scripts/ai/SquadDirector.gd").new()
		director.name = "SquadDirector"
		add_child(director)
		
		# New Diverse Templates
		var t_sniper = load("res://scripts/ai/SquadTemplate.gd").new("Sniper Team", {"sniper": 2, "brawler": 1})
		director.register_template(t_sniper)
		
		var t_recon = load("res://scripts/ai/SquadTemplate.gd").new("Recon", {"scout": 3})
		t_recon.spawn_weight = 120.0
		director.register_template(t_recon)
		
		var t_assault = load("res://scripts/ai/SquadTemplate.gd").new("Assault", {"brawler": 2, "flamethrower": 1})
		t_assault.has_shields = true
		director.register_template(t_assault)
		
		var t_ambush = load("res://scripts/ai/SquadTemplate.gd").new("Ambushers", {"ambusher": 3})
		director.register_template(t_ambush)
	
	active_enemies = 0
	
	# Boss Wave Check
	if current_wave > 0 and current_wave % 5 == 0:
		var boss = director._spawn_bot_for_role("brawler")
		boss.scale = Vector2(2.0, 2.0)
		boss.max_hp *= 5.0
		boss.hp = boss.max_hp
		boss.is_boss = true
		
		var backpacks = ["shield", "jetpack", "missile"]
		var drop_type = backpacks.pick_random()
		boss.set_meta("boss_drop", drop_type)
		
		var offset = Vector2(randf_range(500, 1000), randf_range(500, 1000))
		if randf() > 0.5: offset.x *= -1
		if randf() > 0.5: offset.y *= -1
		var center_spawn = player.global_position + offset
		
		var raw_pos = center_spawn + Vector2(randf_range(-50, 50), randf_range(-50, 50))
		boss.global_position = map.get_valid_spawn_position(raw_pos)
		boss.target = get_tree().get_nodes_in_group("player")[0]
		boss.died.connect(_on_boss_died.bind(boss))
		boss.collision_layer = 4
		boss.collision_mask = 1 | 2 | 8
		active_enemies += 1

	var target_enemy_count = min(80, 5 + int((current_wave - 1) / 4) * 20)
	
	var safety_break = 0
	while active_enemies < target_enemy_count and safety_break < 50:
		safety_break += 1
		# Spawn the squad
		var squad = director.spawn_squad()
		if not squad: 
			break
			
		# Place them at a random spawn point away from player
		var offset = Vector2(randf_range(500, 1500), randf_range(500, 1500))
		if randf() > 0.5: offset.x *= -1
		if randf() > 0.5: offset.y *= -1
		var center_spawn = player.global_position + offset
		
		# Clamp to roughly within map bounds
		center_spawn.x = clamp(center_spawn.x, 100, map.width * map.tile_size - 100)
		center_spawn.y = clamp(center_spawn.y, 100, map.height * map.tile_size - 100)
		
		for mech in squad.members:
			var raw_pos = center_spawn + Vector2(randf_range(-200, 200), randf_range(-200, 200))
			mech.global_position = map.get_valid_spawn_position(raw_pos)
			mech.target = get_tree().get_nodes_in_group("player")[0]
			mech.died.connect(_on_enemy_died)
			mech.collision_layer = 4 # Enemies are Layer 3 (bit 2)
			mech.collision_mask = 1 | 2 | 8 # Hit env, water, player
			active_enemies += 1
			
	if active_enemies <= 0:
		# Fallback if assembly fails entirely
		active_enemies = 3
		var wave_multiplier = pow(1.10, max(0, current_wave - 1))
		for i in range(3):
			var m = load("res://scripts/entities/Mech.gd").new()
			m.max_hp = 100.0 * wave_multiplier
			m.hp = m.max_hp
			m.global_position = map.get_valid_spawn_position(Vector2(1600 + i*50, 1600))
			m.died.connect(_on_enemy_died)
			add_child(m)

func _on_boss_died(boss):
	var drop_type = boss.get_meta("boss_drop", "shield")
	var drop_pack = null
	
	if drop_type == "shield":
		drop_pack = load("res://scripts/core/ComponentEquipment.gd").create_shield_backpack()
	elif drop_type == "jetpack":
		drop_pack = load("res://scripts/core/ComponentEquipment.gd").create_jetpack_backpack()
	elif drop_type == "missile":
		drop_pack = load("res://scripts/core/ComponentEquipment.gd").create_missile_backpack()
		
	if drop_pack:
		var pickup = load("res://scripts/entities/LootPickup.gd").new()
		pickup.equipment_data = drop_pack
		pickup.global_position = boss.global_position
		get_tree().current_scene.add_child(pickup)
		
	_on_enemy_died()

func _on_enemy_died():
	active_enemies -= 1
	if active_enemies <= 0:
		_on_wave_cleared()

func _on_wave_cleared():
	print("--- WAVE CLEARED ---")
	current_wave += 1
	_start_intermission()

func _open_garage():
	print("Opening Garage Menu...")
	get_tree().paused = true
	var GarageMenuClass = load("res://scripts/ui/GarageMenu.gd")
	if GarageMenuClass:
		garage_ui = GarageMenuClass.new()
		add_child(garage_ui)
	else:
		print("Failed to load GarageMenu!")
	
func _close_garage():
	print("Deploying from Garage...")
	get_tree().paused = false
	if garage_ui:
		garage_ui.queue_free()
		garage_ui = null
		
	# Only start the next wave if we were in an intermission state
	if active_enemies <= 0:
		_show_countdown()
