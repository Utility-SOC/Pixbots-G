extends Node2D
const MapGenerator = preload("res://scripts/core/MapGenerator.gd")
const Mech = preload("res://scripts/entities/Mech.gd")

const WeaponMountTile = preload("res://scripts/tiles/WeaponMountTile.gd")

var current_mode: String = "sandbox"
var current_wave: int = 1
var campaign_data: Dictionary = {}
var active_enemies: int = 0
var garage_timer: float = 90.0

var map: MapGenerator
var garage_ui: CanvasLayer
var player: Mech
var player_inventory: Array = []
var player_component_inventory: Array = []
var player_scrap: int = 0


var hud_canvas: CanvasLayer
var wave_label: Label
var timer_label: Label
var extraction_marker: Node2D = null
var extraction_indicator: Polygon2D = null

func _ready():
	_load_campaign()
	_setup_environment()
	_setup_player()
	
	_setup_hud()
	
	# Assume Sandbox mode defaults for now if not set by MainMenu
	_start_intermission()

func _setup_hud():
	hud_canvas = CanvasLayer.new()
	hud_canvas.layer = 5
	
	wave_label = Label.new()
	wave_label.add_theme_font_size_override("font_size", 32)
	wave_label.position = Vector2(20, 20)
	hud_canvas.add_child(wave_label)
	
	timer_label = Label.new()
	timer_label.add_theme_font_size_override("font_size", 24)
	timer_label.position = Vector2(20, 60)
	hud_canvas.add_child(timer_label)
	
	# Simple arrow indicator
	extraction_indicator = Polygon2D.new()
	var pts = PackedVector2Array([Vector2(20, 0), Vector2(-20, 15), Vector2(-10, 0), Vector2(-20, -15)])
	extraction_indicator.polygon = pts
	extraction_indicator.color = Color(0.2, 1.0, 0.4)
	extraction_indicator.visible = false
	hud_canvas.add_child(extraction_indicator)
	
	add_child(hud_canvas)
	_update_hud()

func _update_hud():
	if wave_label:
		wave_label.text = "Wave: " + str(current_wave)
	if timer_label:
		if garage_timer > 0:
			timer_label.text = "Extraction in: " + str(int(garage_timer)) + "s"
			timer_label.modulate = Color.WHITE
		else:
			timer_label.text = "Extraction Ready! Follow indicator."
			timer_label.modulate = Color(0.2, 1.0, 0.4)


func _process(delta: float):
	if garage_timer > 0:
		garage_timer -= delta
		_update_hud()
		if garage_timer <= 0:
			_spawn_extraction_marker()
			_update_hud()
			
	if is_instance_valid(extraction_marker) and extraction_indicator and player:
		extraction_indicator.visible = true
		var viewport_rect = get_viewport_rect()
		var center = viewport_rect.size / 2.0
		var dir = (extraction_marker.global_position - player.global_position).normalized()
		extraction_indicator.position = center + dir * (min(viewport_rect.size.x, viewport_rect.size.y) / 2.0 - 50)
		extraction_indicator.rotation = dir.angle()
	elif extraction_indicator:
		extraction_indicator.visible = false

func _spawn_extraction_marker():
	var marker_class = load("res://scripts/entities/ExtractionMarker.gd")
	if marker_class:
		extraction_marker = marker_class.new()
		var offset = Vector2(randf_range(600, 1500), randf_range(600, 1500))
		if randf() > 0.5: offset.x *= -1
		if randf() > 0.5: offset.y *= -1
		
		if player:
			var target_pos = player.global_position + offset
			if map:
				target_pos = map.get_valid_spawn_position(target_pos)
			extraction_marker.global_position = target_pos
		add_child(extraction_marker)


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
	player.died.connect(_on_player_died)
	
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
		if load_data.has("scrap"):
			player_scrap = load_data["scrap"]
	else:

		_initialize_starter_inventory()
	
	var camera = Camera2D.new()
	camera.set_script(load("res://scripts/core/CameraShake.gd"))
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 5.0
	camera.zoom = Vector2(1.5, 1.5)
	camera.add_to_group("camera")
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
				
	# Add Magnets and Shields
	for r in rarities:
		for i in range(5):
			var tile = load("res://scripts/tiles/MagnetTile.gd").new()
			tile.rarity = r
			player_inventory.append(tile)
			
			var shield = load("res://scripts/tiles/ShieldGeneratorTile.gd").new()
			shield.rarity = r
			player_inventory.append(shield)
				
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
	_update_hud()
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
		
		var t_jammer = load("res://scripts/ai/SquadTemplate.gd").new("Jammer Escort", {"jammer": 1, "brawler": 2, "sniper": 1})
		t_jammer.has_shields = true
		t_jammer.spawn_weight = 80.0
		director.register_template(t_jammer)
	
	active_enemies = 0
	
	# Megaboss Wave Check (Every 25 waves)
	if current_wave > 0 and current_wave % 25 == 0:
		_spawn_boss(director, true)
	# Boss Wave Check (Every 5 waves)
	elif current_wave > 0 and current_wave % 5 == 0:
		_spawn_boss(director, false)

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
			mech.target = player
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
			m.target = player
			add_child(m)

func _spawn_boss(director, is_mega: bool):
	var boss = director._spawn_bot_for_role("brawler")
	if is_mega:
		boss.scale = Vector2(3.0, 3.0)
		boss.max_hp *= 25.0
		boss.is_boss = true
		boss.set_meta("boss_drop", "mega")
	else:
		boss.scale = Vector2(2.0, 2.0)
		boss.max_hp *= 5.0
		boss.is_boss = true
		var backpacks = ["shield", "jetpack", "missile"]
		boss.set_meta("boss_drop", backpacks.pick_random())
		
	boss.hp = boss.max_hp
	var offset = Vector2(randf_range(500, 1000), randf_range(500, 1000))
	if randf() > 0.5: offset.x *= -1
	if randf() > 0.5: offset.y *= -1
	var center_spawn = player.global_position + offset
	
	boss.global_position = map.get_valid_spawn_position(center_spawn)
	boss.target = player
	boss.died.connect(_on_boss_died.bind(boss))
	boss.collision_layer = 4
	boss.collision_mask = 1 | 2 | 8
	active_enemies += 1

func _on_boss_died(boss):
	var drop_type = boss.get_meta("boss_drop", "shield")
	var drop_pack = null
	
	if drop_type == "mega":
		# Megaboss guaranteed Legendary Drop
		var pickup = load("res://scripts/entities/LootPickup.gd").new()
		pickup.global_position = boss.global_position
		
		# Generate a legendary tile
		var tile_types = [
			preload("res://scripts/tiles/WeaponMountTile.gd"),
			preload("res://scripts/tiles/AccumulatorTile.gd"),
			preload("res://scripts/tiles/ReflectorTile.gd"),
			preload("res://scripts/tiles/SplitterTile.gd"),
			preload("res://scripts/tiles/CatalystTile.gd")
		]
		var legend_tile = tile_types.pick_random().new()
		legend_tile.rarity = HexTile.Rarity.LEGENDARY
		pickup.item_data = legend_tile
		get_tree().current_scene.add_child(pickup)
	else:
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
	if active_enemies == 0:
		_on_wave_cleared()

var last_garage_wave: int = 1

func _on_player_died():
	print("!!! GAME OVER - MAGNIFICENT EXPLOSION !!!")
	player.visible = false
	player.set_process(false)
	player.set_physics_process(false)
	
	var explosion = load("res://scripts/visuals/DeathExplosion.gd").new()
	explosion.global_position = player.global_position
	add_child(explosion)
	
	# Wait 3 seconds, then kick back to garage
	var timer = Timer.new()
	timer.wait_time = 3.0
	timer.one_shot = true
	timer.timeout.connect(func():
		current_wave = last_garage_wave # Kick back to last checkpoint
		
		# Clear all active enemies
		for enemy in get_tree().get_nodes_in_group("enemy"):
			enemy.queue_free()
		active_enemies = 0
		
		_open_garage()
	)
	add_child(timer)
	timer.start()

func _on_wave_cleared():
	print("--- WAVE CLEARED ---")
	current_wave += 1
	_start_intermission()

func _open_garage():
	print("Opening Garage Menu...")
	get_tree().paused = true
	
	# Full heal on entering garage
	player.hp = player.max_hp
	player.visible = true
	player.set_process(true)
	player.set_physics_process(true)
	
	var GarageMenuClass = load("res://scripts/ui/GarageMenu.gd")
	if GarageMenuClass:
		garage_ui = GarageMenuClass.new()
		add_child(garage_ui)
	else:
		print("Failed to load GarageMenu!")
	
func _close_garage():
	print("Deploying from Garage...")
	get_tree().paused = false
	
	garage_timer = 90.0
	_update_hud()
		
	last_garage_wave = current_wave
	
	if player != null:
		SaveManager.save_game("autosave", player, player_inventory)
		
	if garage_ui:
		garage_ui.queue_free()
		garage_ui = null
		
	if active_enemies <= 0:
		_show_countdown()
