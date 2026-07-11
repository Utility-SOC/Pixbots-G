extends Node2D
const MapGenerator = preload("res://scripts/core/MapGenerator.gd")
const Mech = preload("res://scripts/entities/Mech.gd")

const WeaponMountTile = preload("res://scripts/tiles/WeaponMountTile.gd")
const DroneBayTile = preload("res://scripts/tiles/DroneBayTile.gd")
const ChampionCardScript = preload("res://scripts/pvp/ChampionCard.gd")

# Companion Drones (see Drone.gd/DroneBayTile.gd): one spawned alongside the
# player per Drone Bay tile installed anywhere in their Backpack on deploy -
# a build can carry more than one bay, each flying an independent drone with
# its own loadout. Each is destroyed and respawned after its own cooldown if
# it dies mid-run - "destructible, respawns" per Natalia's design choice.
# Both dictionaries are keyed by the owning DroneBayTile's instance ID (the
# tile itself, not the Drone node, since that's what survives a drone's
# death/respawn cycle and what GarageMenu edits).
var drone_nodes: Dictionary = {} # bay instance ID -> Drone
var _drone_respawn_timers: Dictionary = {} # bay instance ID -> float seconds remaining
const DRONE_RESPAWN_DELAY = 8.0

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
# Extracted stat modifiers waiting to be infused into a part (feature 5).
# Each entry: {"stat": String, "value": float}. Managed by GarageMenu.
var player_modifier_chips: Array = []


var hud_canvas: CanvasLayer
var wave_label: Label
var timer_label: Label
var extraction_marker: Node2D = null
var extraction_indicator: Polygon2D = null
# Jammers are no longer a full-screen dim (see JammerField.gd) - the
# player's Blind state is now "standing inside a hostile JammerField",
# checked continuously by _update_player_blind_state() below.
var player_is_blind: bool = false
var boss_health_bar_bg: ColorRect = null
var boss_health_bar_fg: ColorRect = null
var boss_health_label: Label = null
var dialogue_box: Panel = null
var dialogue_label: RichTextLabel = null
var dialogue_timer: float = 0.0

# The actual game world (map/mechs/projectiles/VFX) renders inside a small
# fixed-resolution SubViewport, then gets scaled up with nearest-neighbor
# filtering - this is what makes everything read as chunky pixel art
# instead of smooth vector shapes, no matter how coarse we snap individual
# polygon vertices. HUD/menus stay OUTSIDE this (added directly to Main)
# so text stays crisp and readable rather than also getting pixelated.
#
# The ground texture already looks chunky at basically any internal
# resolution because its "fat pixel" blocks are baked directly into the
# Image at generation time (see MapGenerator._paint_textured_tile) - that's
# NOT evidence the low-res viewport itself is pixelating things enough.
# Vector-drawn content (every mech) has no such baked-in chunkiness and is
# the honest test.
#
# IMPORTANT: SubViewportContainer.stretch = true makes the container drive
# the child SubViewport's actual render size to match the CONTAINER (i.e.
# the full window) - manually setting viewport.size gets silently
# overridden the moment stretch is enabled. That was the real bug behind
# the first two attempts at this: the viewport was rendering at native
# resolution the whole time, so changing the "size" constant did nothing.
# The actual documented mechanism for low-res pixel art is stretch_shrink,
# an integer divisor: the container renders its viewport at
# (container_size / stretch_shrink) and upscales by that same factor. This
# also adapts automatically to window resizing, which a fixed size wouldn't.
# Higher = chunkier/more pixelated, lower = closer to native/smoother.
#
# Mechs now bake their OWN genuine pixel grid directly (see
# MechPartRenderer.gd - real Image rasterization, not vector-then-downscale)
# at CELL_SIZE=3 world-units-per-cell. That means this viewport-level
# downscale is no longer the primary source of chunkiness for mechs - it's
# now a second, independent pixel grid layered on top of an already-baked
# one. If this factor pushes the viewport's own effective world-units-per-
# pixel finer than the mech sprites' baked CELL_SIZE, the viewport ends up
# re-quantizing already-crisp pixel art onto a second, misaligned grid,
# which can look worse, not better (a subtle jitter/moire rather than clean
# pixels). Keeping this modest avoids fighting the baked sprites, while
# still giving projectiles/particles/VFX (which are NOT baked pixel art)
# some benefit. If mechs ever stop baking their own pixels, this is the
# dial to push back up for the ground/world overall.
const PIXEL_SHRINK_FACTOR = 2
var world: Node2D

# Battle camera zoom lives entirely in CameraShake.gd now (single owner of
# camera.zoom) - a second wheel-zoom system briefly lived here and fought
# the camera's own one every frame, causing the "pops back in" rubber-band.

func _ready():
	_setup_pixel_viewport()
	_load_campaign()
	_setup_environment()
	_setup_player()

	_setup_hud()

	# War Room (TAB) - the window into the AI director's learning loop.
	# Minimap (U) - drag to move, wheel to zoom, corner grip to resize.
	# NOTE: DebugMenu is NOT added here - it's already an autoload in
	# project.godot (adding it here too created a stacked double menu).
	add_child(load("res://scripts/ui/WarRoomMenu.gd").new())
	add_child(load("res://scripts/ui/MinimapOverlay.gd").new())
	# First-run onboarding (tutorial.json) - dormant after the player
	# completes or skips it once (user://tutorial_completed.flag).
	add_child(load("res://scripts/ui/TutorialManager.gd").new())
	# Centralized Esc-to-pause handling that works whether or not the tree
	# is currently paused (Garage/death) - see GlobalPauseHandler.gd's own
	# comment for why this replaced the old Main._unhandled_input +
	# GarageMenu._input dual-handler approach.
	add_child(load("res://scripts/ui/GlobalPauseHandler.gd").new())

	# Register gameplay actions that have no [input] section entry. The
	# cloak generator gates on InputMap.has_action("cloak") - without this
	# the action never existed, so AI ambushers could cloak and the PLAYER
	# never could (playtest: "how do I use my cloak generator?").
	# Hold C to cloak. Runtime-registered actions are rebindable through
	# the same InputMap the settings menu edits.
	if not InputMap.has_action("cloak"):
		InputMap.add_action("cloak")
		var cloak_key = InputEventKey.new()
		cloak_key.physical_keycode = KEY_C
		InputMap.action_add_event("cloak", cloak_key)

	# Per Natalia: every game start (new game or loaded save) should land in
	# the Garage first, not straight into combat - the player deploys
	# explicitly via "Deploy to Battlefield ->". _close_garage() already
	# handles kicking off the first wave's countdown on that initial
	# deploy (its "if active_enemies <= 0: _show_countdown()" - active_enemies
	# is still 0 at this point since nothing has spawned yet), so nothing
	# else needs to change for wave 1 to start correctly once the player
	# actually deploys.
	_open_garage()

func _setup_pixel_viewport():
	# A Control anchored PRESET_FULL_RECT under a bare Node2D (Main) doesn't
	# reliably inherit the window's rect - Godot's anchor system needs a
	# Control/CanvasLayer basis to size against, and a plain Node2D doesn't
	# provide one. hud_canvas (below, in _setup_hud) already proves the
	# CanvasLayer -> Control pattern works correctly in this exact project,
	# so the pixel viewport uses the same structure instead of relying on
	# anchor behavior under a Node2D parent that isn't guaranteed to resize
	# the container (the failure mode is a correctly-running but invisible/
	# zero-sized viewport - exactly a blank screen with only the HUD showing).
	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "PixelViewportLayer"
	canvas_layer.layer = 0 # Below hud_canvas (layer 5), so HUD draws on top
	add_child(canvas_layer)

	var container = SubViewportContainer.new()
	container.name = "PixelViewportContainer"
	container.stretch = true
	container.stretch_shrink = PIXEL_SHRINK_FACTOR
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Deliberately leaving mouse_filter at its default (STOP) - the
	# SubViewportContainer needs to actively receive mouse events so it can
	# forward them into the SubViewport for player aiming.
	canvas_layer.add_child(container)

	var viewport = SubViewport.new()
	viewport.name = "PixelViewport"
	# No explicit size - with stretch_shrink active, the container manages
	# the viewport's render size automatically (container.size / shrink),
	# continuously, including on window resize.
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)

	world = Node2D.new()
	world.name = "World"
	viewport.add_child(world)

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

	# Boss UI
	var b_width = 400
	var b_height = 30
	var b_margin = 16
	boss_health_bar_bg = ColorRect.new()
	boss_health_bar_bg.color = Color(0.1, 0.1, 0.1, 0.8)
	boss_health_bar_bg.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	boss_health_bar_bg.position = Vector2((1280 - b_width) / 2, 720 - b_height - b_margin)
	boss_health_bar_bg.size = Vector2(b_width, b_height)
	boss_health_bar_bg.visible = false
	hud_canvas.add_child(boss_health_bar_bg)
	
	boss_health_bar_fg = ColorRect.new()
	boss_health_bar_fg.color = Color(0.8, 0.1, 0.1, 1.0)
	boss_health_bar_fg.position = Vector2(2, 2)
	boss_health_bar_fg.size = Vector2(b_width - 4, b_height - 4)
	boss_health_bar_bg.add_child(boss_health_bar_fg)
	
	boss_health_label = Label.new()
	boss_health_label.add_theme_font_size_override("font_size", 24)
	boss_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_health_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	boss_health_bar_bg.add_child(boss_health_label)

	# Dialogue UI
	dialogue_box = Panel.new()
	dialogue_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	dialogue_box.position = Vector2(1280 / 2 - 400, 100)
	dialogue_box.size = Vector2(800, 120)
	dialogue_box.visible = false
	hud_canvas.add_child(dialogue_box)

	dialogue_label = RichTextLabel.new()
	dialogue_label.bbcode_enabled = true
	dialogue_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialogue_label.offset_left = 16
	dialogue_label.offset_top = 16
	dialogue_label.offset_right = -16
	dialogue_label.offset_bottom = -16
	dialogue_label.add_theme_font_size_override("normal_font_size", 20)
	dialogue_label.add_theme_font_size_override("bold_font_size", 22)
	dialogue_box.add_child(dialogue_label)

	add_child(hud_canvas)
	_update_hud()

func show_dialogue(speaker: String, text: String, color: Color = Color(1.0, 0.85, 0.2), duration: float = 6.0):
	if text == "": return
	dialogue_box.visible = true
	var hex_color = color.to_html(false)
	dialogue_label.text = "[b][color=#%s]%s[/color][/b]\n%s" % [hex_color, speaker, text]
	dialogue_timer = duration

# Continuously re-evaluated (not a timer) - the player is Blind exactly
# while standing inside a hostile JammerField's live boundary, and un-blind
# the instant they leave or its owner dies. The jammer_field scan itself
# stays unconditional every frame (that group is small, 1-3 active fields
# at once, and needs the real-time boundary check), but the "enemy" group -
# up to 80 members - only gets its .visible toggled on an actual blind-state
# TRANSITION, not every single frame regardless of change. This was walking
# and writing .visible on the whole enemy roster 60x/sec even while nothing
# changed - a genuine per-frame O(enemy count) cost for a state that only
# actually flips a few times per encounter. Since this loop no longer runs
# every frame, a freshly-spawned enemy while the player is ALREADY blind
# (no transition to trigger this loop) needs its own one-time correction at
# spawn time instead - see SquadDirector._spawn_bot_for_role's visibility
# sync right after add_child(bot).
var _was_player_blind: bool = false

func _update_player_blind_state():
	if not player or not is_instance_valid(player):
		return
	var blind = false
	for f in EntityCache.get_group("jammer_field"):
		if is_instance_valid(f) and not f.owner_is_player and f.is_point_inside(player.global_position):
			blind = true
			f.report_jam_contact(player.global_position)
			break
	player_is_blind = blind
	if blind == _was_player_blind:
		return
	_was_player_blind = blind
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(enemy):
			enemy.visible = not blind

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

	if not _drone_respawn_timers.is_empty():
		var ready_bays = []
		for bay_id in _drone_respawn_timers.keys():
			_drone_respawn_timers[bay_id] -= delta
			if _drone_respawn_timers[bay_id] <= 0.0:
				ready_bays.append(bay_id)
		for bay_id in ready_bays:
			_drone_respawn_timers.erase(bay_id)
		if not ready_bays.is_empty():
			_spawn_drones_if_needed()

	if dialogue_timer > 0:
		dialogue_timer -= delta
		if dialogue_timer <= 0:
			dialogue_box.visible = false

	_update_player_blind_state()

# Spawns a companion Drone for every Drone Bay tile installed anywhere in the
# player's Backpack that doesn't already have a live drone and isn't on
# respawn cooldown - called on every deploy (_close_garage) and again
# whenever an individual bay's respawn cooldown elapses following a
# mid-combat drone death (see _on_drone_died).
func _spawn_drones_if_needed():
	if not player or not player.components.has(HexTile.BodySlot.BACKPACK):
		return
	var backpack = player.components[HexTile.BodySlot.BACKPACK]
	var bays = DroneBayTile.find_all_in_backpack(backpack)
	for i in range(bays.size()):
		var drone_bay = bays[i]
		var bay_id = drone_bay.get_instance_id()
		if drone_nodes.has(bay_id) and is_instance_valid(drone_nodes[bay_id]):
			continue
		if _drone_respawn_timers.has(bay_id):
			continue

		var drone = load("res://scripts/entities/Drone.gd").new()
		var loadout = drone_bay.get_or_build_loadout() # also assigns visual_class if unset - must run before reading it below
		drone.setup(player, loadout, drone_bay.rarity, drone_bay.visual_class)
		# Spread multiple drones' starting positions out (and their
		# _orbit_angle, randomized independently in Drone.gd's setup) so a
		# multi-bay build doesn't spawn every drone stacked on the same point.
		var spread_angle = (TAU / max(1, bays.size())) * i
		drone.global_position = player.global_position + Vector2(cos(spread_angle), sin(spread_angle)) * 70.0
		drone.drone_died.connect(_on_drone_died.bind(bay_id))
		world.add_child(drone)
		drone_nodes[bay_id] = drone

func _on_drone_died(_rarity: int, bay_id: int):
	drone_nodes.erase(bay_id)
	_drone_respawn_timers[bay_id] = DRONE_RESPAWN_DELAY

# Garage state is a hard reset point for the drones same as everything else
# about the run (see _open_garage's full-heal) - simpler and more robust than
# trying to keep live drones correctly paused/hidden through the Garage UI.
# Fresh ones spawn right back on deploy (_close_garage).
func _despawn_all_drones():
	for bay_id in drone_nodes.keys():
		if is_instance_valid(drone_nodes[bay_id]):
			drone_nodes[bay_id].queue_free()
	drone_nodes.clear()
	_drone_respawn_timers.clear()

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
		world.add_child(extraction_marker)


# Esc/ui_cancel handling moved to GlobalPauseHandler.gd (added in _ready())
# - it needs to work whether or not the tree is paused, which this
# function couldn't do since Main itself isn't PROCESS_MODE_ALWAYS.

func _load_campaign():
	var file = FileAccess.open("res://campaign.json", FileAccess.READ)
	if file:
		var text = file.get_as_text()
		var json = JSON.new()
		if json.parse(text) == OK:
			campaign_data = json.data

func _setup_environment():
	map = MapGenerator.new()
	# Per-run map rotation (design ruling). Tabletop is weighted double -
	# it's the game's eventual identity; long-term every biome here becomes
	# a themed tabletop mat (grass mat, tundra mat...) rather than "terrain".
	var map_rotation = ["Tabletop", "Tabletop", "Normal", "Open Field", "Forest", "Desert", "Tundra", "Volcano", "Dungeon", "Water"]
	map.map_type = map_rotation[randi() % map_rotation.size()]
	map.name = "GameMap"
	world.add_child(map)

func _setup_player():
	player = Mech.new()
	player.is_player = true
	player.name = "PlayerMech"
	
	# Player is Layer 4 (bit 3). 
	player.collision_layer = 8
	player.collision_mask = 1 | 2 | 4 # Collides with environment, water, enemies
	
	player.global_position = map.get_valid_spawn_position(Vector2(map.width * map.tile_size / 2.0, map.height * map.tile_size / 2.0))

	world.add_child(player)
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
		if load_data.has("modifier_chips"):
			player_modifier_chips = load_data["modifier_chips"]
		# Resume the RUN, not just the gear - the wave counter was never in
		# the save format (play report: "game save is still not saving
		# wave"), so every load silently restarted at wave 1.
		if load_data.has("current_wave"):
			current_wave = max(1, int(load_data["current_wave"]))
			last_garage_wave = current_wave
	else:

		_initialize_starter_inventory()
	
	var camera = Camera2D.new()
	camera.set_script(load("res://scripts/core/CameraShake.gd"))
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 5.0
	# Camera2D.zoom is relative to the viewport it's actually rendering
	# into, not the window - since that's now the small internal
	# PixelViewport (container_size / PIXEL_SHRINK_FACTOR), the old zoom of
	# 1.5 (tuned for native rendering) made the camera capture 1/Nth the
	# world area it used to, which is why everything rendered N times too
	# big AND paradoxically too smooth (more internal pixels ended up spent
	# per mech than intended). Dividing by the shrink factor here keeps the
	# on-screen framing where it was while still getting the low-res pass.
	camera.zoom = Vector2(1.5, 1.5) / PIXEL_SHRINK_FACTOR
	camera.set("base_zoom", 1.5 / PIXEL_SHRINK_FACTOR) # CameraShake owns zoom from here
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
				
	# Add Infusers (enum values, not magic ints - the old literal `3` here
	# was commented POISON but is actually LIGHTNING in SynergyType order,
	# so the starter "poison" infuser had been infusing lightning)
	var poison_infuser = load("res://scripts/tiles/InfuserTile.gd").new()
	poison_infuser.rarity = HexTile.Rarity.RARE
	poison_infuser.secondary_synergy = EnergyPacket.SynergyType.POISON
	player_inventory.append(poison_infuser)

	var fire_infuser = load("res://scripts/tiles/InfuserTile.gd").new()
	fire_infuser.rarity = HexTile.Rarity.RARE
	fire_infuser.secondary_synergy = EnergyPacket.SynergyType.FIRE
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
	var dm = load("res://scripts/core/DialogueManager.gd").new()
	dm._ready()
	show_dialogue("Shopkeeper", dm.get_intermission_quip(), Color(0.7, 0.85, 1.0), 5.0)
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
	LootManager.current_wave = current_wave
	# Reactive music: combat loop (faster arps + drums) for the wave.
	AudioManager.set_combat_state(true)

	# Spawn Squad Director if it doesn't exist
	var director = world.get_node_or_null("SquadDirector")
	if not director:
		director = load("res://scripts/ai/SquadDirector.gd").new()
		director.name = "SquadDirector"
		world.add_child(director)
		
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

		var t_support = load("res://scripts/ai/SquadTemplate.gd").new("Support Detachment", {"support": 1, "brawler": 2})
		t_support.spawn_weight = 70.0
		director.register_template(t_support)

		var t_command = load("res://scripts/ai/SquadTemplate.gd").new("Command Escort", {"commander": 1, "brawler": 2, "sniper": 1})
		t_command.has_shields = true
		t_command.spawn_weight = 55.0 # rare-ish: a Commander on the field should feel like an event
		director.register_template(t_command)

		# Piercing Jammer's whole value is the execute-immunity aura it
		# throws over its escort - pair it with roles a pierce-execute
		# player would normally love shredding (brawler/ambusher, both
		# squishy-ish melee-range targets) so the counterplay is legible.
		var t_pierce_escort = load("res://scripts/ai/SquadTemplate.gd").new("Pierce Escort", {"piercing_jammer": 1, "brawler": 1, "ambusher": 1})
		t_pierce_escort.spawn_weight = 45.0 # baseline rare-ish; SquadDirector up-weights hard once PIERCE-execution share is detected
		director.register_template(t_pierce_escort)

		# Divers flank through water other roles have to route around -
		# paired with a scout for the same "hit-and-fade" playstyle rather
		# than a tanky escort, since the whole point is terrain, not brawn.
		var t_recon_amphib = load("res://scripts/ai/SquadTemplate.gd").new("Amphibious Recon", {"diver": 2, "scout": 1})
		t_recon_amphib.spawn_weight = 60.0
		director.register_template(t_recon_amphib)

		# Restore learned weights/fitness onto the defaults just registered,
		# plus any evolved compositions and solver profiles from previous
		# sessions. Must run AFTER the defaults exist so the merge-by-name
		# updates them in place instead of duplicating them.
		director.load_learned_state()

	# Director tells (see SquadDirector.get_intel_line): Evan tips the player
	# off when the learning loop is genuinely reacting to them. Skipped in
	# Boss Rush, which runs its own intro dialogue on the same channel.
	director.note_wave_started()
	if SaveManager.current_game_mode != "boss_rush":
		var intel = director.get_intel_line(current_wave)
		if intel != "":
			show_dialogue("Evan", intel, Color(0.7, 0.9, 1.0), 6.0)

	# Periodically let the director try out a new experimental squad
	# composition (mutation or fresh random template). Not every wave, so
	# each trial gets a few waves to actually accumulate deployments before
	# the next one shows up.
	if current_wave % 3 == 0:
		director.maybe_introduce_experimental_template()
	if current_wave % 4 == 0:
		director.maybe_introduce_experimental_profile()
	if current_wave % 5 == 0:
		director.maybe_introduce_experimental_boss_profile()

	active_enemies = 0
	
	# Boss Rush Mode Logic
	if SaveManager.current_game_mode == "boss_rush":
		if current_wave <= 15:
			# Sequence 15 Rivals at Mythic tier
			var r_name = ""
			if current_wave - 1 < director.all_rival_profiles.keys().size():
				r_name = director.all_rival_profiles.keys()[current_wave - 1]
			else:
				r_name = director.get_next_rival()
			if current_wave == 1:
				# show_dialogue() doesn't queue - it just overwrites the label -
				# so spawning the rival (which shows its own intro line) in the
				# same call would clobber this banner before it's ever seen.
				# Delay the spawn a few seconds so the gauntlet intro actually
				# gets read first.
				var dm_intro = load("res://scripts/core/DialogueManager.gd").new()
				dm_intro._ready()
				show_dialogue("Shopkeeper", dm_intro.get_boss_rush_intro(), Color(1.0, 0.7, 0.3), 8.0)
				var intro_timer = Timer.new()
				intro_timer.wait_time = 3.0
				intro_timer.one_shot = true
				intro_timer.timeout.connect(func(): _spawn_rival(director, HexTile.Rarity.MYTHIC, r_name))
				add_child(intro_timer)
				intro_timer.start()
			else:
				_spawn_rival(director, HexTile.Rarity.MYTHIC, r_name)
		else:
			if current_wave == 16:
				# Same clobbering concern as the intro banner above - _spawn_boss
				# can show its own "first boss" dialogue in the rare case a Boss
				# Rush save somehow never triggered it in the campaign proper.
				var dm_completion = load("res://scripts/core/DialogueManager.gd").new()
				dm_completion._ready()
				show_dialogue("Shopkeeper", dm_completion.get_boss_rush_completion(), Color(1.0, 0.7, 0.3), 8.0)
				var completion_timer = Timer.new()
				completion_timer.wait_time = 3.0
				completion_timer.one_shot = true
				completion_timer.timeout.connect(func(): _spawn_boss(director, true))
				add_child(completion_timer)
				completion_timer.start()
			else:
				# Endless Mega Bosses
				_spawn_boss(director, true)
		return

	# Megaboss Wave Check (Every 25 waves)
	if current_wave > 0 and current_wave % 25 == 0:
		_spawn_boss(director, true)
	# Rival Challenge (every 10 waves)
	elif current_wave > 0 and current_wave % 10 == 0:
		_spawn_rival(director)
	# Boss Wave Check (Every 5 waves)
	elif current_wave > 0 and current_wave % 5 == 0:
		_spawn_boss(director, false)
	# Traveling Champion (PvP ghost): on ordinary waves, an imported
	# champion sometimes shows up at the shop to challenge you - "counted
	# like any game-shop challenger" per the design ruling. Story-wise it's
	# a visiting player; mechanically it's their exact exported build.
	elif current_wave >= 3 and randf() < 0.12:
		var ghosts = ChampionCardScript.list_ghosts()
		if not ghosts.is_empty():
			_spawn_traveling_champion(ghosts[randi() % ghosts.size()])

	# Difficulty scales how MANY as well as how strong (SquadDirector
	# handles per-bot strength; near-peer stat scaling lives there too).
	var count_mult = SaveManager.DIFFICULTY_COUNT_MULT[SaveManager.difficulty]
	# Map-area density scaling: the Tabletop (64x32) is ~1/50th the default
	# map's area - the same 80-cap there is a mosh pit, not a battle. sqrt
	# keeps small maps busy-but-breathable (Tabletop lands around x0.23).
	var area_ratio = float(map.width * map.height) / float(400 * 250)
	var density_mult = clamp(sqrt(area_ratio), 0.15, 1.0)
	var target_enemy_count = min(80, int((5 + int((current_wave - 1) / 4) * 20) * count_mult * density_mult))
	target_enemy_count = max(3, target_enemy_count)

	# Staggered deployment (fire-and-forget async) - see _spawn_wave_async.
	_spawn_wave_async(director, target_enemy_count)

# True while a wave is still trickling in - guards _on_enemy_died from
# declaring a premature wave-clear when the player kills the first squads
# before the rest have deployed.
var _spawning_wave: bool = false
var _wave_spawned_any: bool = false

# Spawning a full wave used to happen synchronously: up to ~16 squads x 5
# mechs, each running the grid solver AND baking six pixel-art parts, all
# in one frame - the "game freezes when a wave spawns" hitch. Now ONE
# squad deploys per beat, spreading that cost across frames. It also reads
# better: squads arrive at the table edges in sequence, like minis being
# set down one handful at a time.
func _spawn_wave_async(director, target_enemy_count: int) -> void:
	_spawning_wave = true
	var safety_break = 0
	while active_enemies < target_enemy_count and safety_break < 50:
		safety_break += 1
		if not is_instance_valid(director) or not is_instance_valid(player) or not is_inside_tree():
			break

		var squad = director.spawn_squad()
		if not squad:
			break

		# Squads enter from the table's edges or from behind large
		# obstacles - not from a fixed ring around the player.
		var center_spawn = _pick_spawn_anchor()
		var inset = 96.0
		var map_w = map.width * map.tile_size
		var map_h = map.height * map.tile_size

		for mech in squad.members:
			var raw_pos = center_spawn + Vector2(randf_range(-200, 200), randf_range(-200, 200))
			# Hard-clamp inside the walls BEFORE the valid-position search:
			# get_valid_spawn_position returns its input unchanged when it
			# can't find a clear tile, which let edge-anchored spawns with
			# unlucky offsets end up outside the map entirely.
			raw_pos.x = clamp(raw_pos.x, inset, map_w - inset)
			raw_pos.y = clamp(raw_pos.y, inset, map_h - inset)
			mech.global_position = map.get_valid_spawn_position(raw_pos)
			mech.target = player
			mech.died.connect(_on_enemy_died)
			mech.collision_layer = 4 # Enemies are Layer 3 (bit 2)
			mech.collision_mask = 1 | 2 | 8 # Hit env, water, player
			active_enemies += 1
			_wave_spawned_any = true

		# One squad per beat - this is the anti-freeze.
		await get_tree().create_timer(0.12).timeout

	_spawning_wave = false

	# Player killed the whole trickle before deployment finished: that IS
	# a wave clear, not a spawn failure.
	if active_enemies <= 0 and safety_break > 0 and _wave_spawned_any:
		_wave_spawned_any = false
		_on_wave_cleared()
		return
	_wave_spawned_any = false

	if active_enemies <= 0:
		# Fallback if assembly fails entirely
		active_enemies = 3
		var wave_multiplier = SaveManager.wave_hp_multiplier(SaveManager.difficulty, current_wave)
		for i in range(3):
			var m = load("res://scripts/entities/Mech.gd").new()
			m.max_hp = 100.0 * wave_multiplier
			m.hp = m.max_hp
			m.global_position = map.get_valid_spawn_position(Vector2(1600 + i * 50, 1600))
			m.died.connect(_on_enemy_died)
			m.target = player
			world.add_child(m)

# Spawn anchor selection: candidates are points just inside the four
# walls plus points beside big obstacles (cover). Prefers anchors a
# comfortable distance from the player; if everything is close (small
# Tabletop maps), takes the farthest available rather than giving up.
func _pick_spawn_anchor() -> Vector2:
	var map_w = map.width * map.tile_size
	var map_h = map.height * map.tile_size
	var inset = 120.0
	var candidates: Array = []

	for i in range(4):
		match randi() % 4:
			0: candidates.append(Vector2(randf_range(inset, map_w - inset), inset))
			1: candidates.append(Vector2(randf_range(inset, map_w - inset), map_h - inset))
			2: candidates.append(Vector2(inset, randf_range(inset, map_h - inset)))
			3: candidates.append(Vector2(map_w - inset, randf_range(inset, map_h - inset)))

	if map.obstacles.size() > 0:
		var obstacle_keys = map.obstacles.keys()
		for i in range(3):
			var k = obstacle_keys[randi() % obstacle_keys.size()]
			candidates.append(Vector2(k.x * map.tile_size, k.y * map.tile_size) + Vector2(randf_range(-64, 64), randf_range(-64, 64)))

	var comfortable: Array = candidates.filter(func(c): return c.distance_to(player.global_position) > 700.0)
	if comfortable.size() > 0:
		return comfortable[randi() % comfortable.size()]
	var best = candidates[0]
	for c in candidates:
		if c.distance_to(player.global_position) > best.distance_to(player.global_position):
			best = c
	return best

# Bosses used to be a scaled-up Brawler, no exceptions, then a flat const
# array of 6 hand-picked archetypes. Now they're spawned from a BossProfile
# pulled off SquadDirector's evolving, fitness-weighted pool (see
# SquadDirector._register_default_boss_profiles/get_active_boss_profile) -
# the same 6 starting kits, but mutation grows real variety over time
# (different enrage styles, ability combos, even different underlying
# roles), same as squad templates and solver profiles already do.
#
# hp_mult exists because the underlying roles' base_hp varies wildly
# (60-350) for balance reasons that have nothing to do with "is this a
# boss" - it roughly levels every archetype back to a comparable HP band
# (regular ~750, mega ~3750) so difficulty stays comparable across profiles
# while still leaving each one a bit squishier or tankier to match its
# flavor. First-pass numbers, not measured against real playtesting.
func _spawn_boss(director, is_mega: bool):
	var profile = director.get_active_boss_profile()
	var boss = director._spawn_bot_for_role(profile.base_role)
	boss.boss_profile = profile
	var hp_mult = profile.hp_mult
	if is_mega:
		boss.scale = Vector2(3.0, 3.0)
		boss.max_hp *= 25.0 * hp_mult
		boss.is_boss = true
		boss.set_meta("boss_drop", "mega")
	else:
		boss.scale = Vector2(2.0, 2.0)
		boss.max_hp *= 5.0 * hp_mult
		boss.is_boss = true
		var backpacks = ["shield", "jetpack", "missile", "drone"]
		boss.set_meta("boss_drop", backpacks.pick_random())

	# is_boss/boss_profile are set above, AFTER _spawn_bot_for_role's
	# add_child already triggered _ready() and built the visual once with
	# is_boss still false - so the boss-only silhouette accents (spike-crown,
	# cloak-fin, satellite dish, etc. - see MechRenderer.gd) never showed up
	# without an explicit rebuild here.
	if boss.has_method("refresh_boss_visuals"):
		boss.refresh_boss_visuals()

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
	# NOT world.add_child(boss) - director._spawn_bot_for_role() already
	# parented it under SquadDirector (which itself lives under world), same
	# as every regular squad member. A second add_child here throws "already
	# has a parent" (see the identical fix in _spawn_rival below).

	# One-time "First boss" dialogue pair (STORY_SCRIPT.md) instead of the
	# regular rotating boss_defeats line - see first_boss_encountered's own
	# comment in SaveManager.gd. Tag the boss now so _on_boss_died knows which
	# defeat line to show without re-checking the (by-then-flipped) flag.
	boss.set_meta("is_first_boss", not SaveManager.first_boss_encountered)
	if not SaveManager.first_boss_encountered:
		var dm = load("res://scripts/core/DialogueManager.gd").new()
		dm._ready()
		show_dialogue("Shopkeeper", dm.get_first_boss_intro(), Color(1.0, 0.6, 0.2), 8.0)

func _on_boss_died(boss):
	# Feed the fight's outcome back into the boss profile's fitness (same
	# reinforcement loop as squad templates/solver profiles) BEFORE the
	# fixed loot-drop handling below, since that part is unrelated and
	# shouldn't be gated on the profile existing.
	if "boss_profile" in boss and boss.boss_profile and boss.has_method("get_boss_fitness"):
		var director = world.get_node_or_null("SquadDirector") if world else null
		if director:
			director._on_boss_defeated(boss.boss_profile, boss.get_boss_fitness())

	var dm = load("res://scripts/core/DialogueManager.gd").new()
	dm._ready()
	if boss.get_meta("is_first_boss", false):
		show_dialogue("Shopkeeper", dm.get_first_boss_defeat(), Color(1.0, 0.6, 0.2), 8.0)
		SaveManager.first_boss_encountered = true
		SaveManager.save_game("autosave", player, player_inventory)
	else:
		show_dialogue("Shopkeeper", dm.get_boss_defeat(), Color(1.0, 0.6, 0.2), 6.0)

	# NOTE: the actual guaranteed component drop (shield/jetpack/missile/
	# drone backpack, keyed off this same "boss_drop" meta) already happened
	# in Mech.die() via LootManager.generate_loot_for_mech() BEFORE the
	# died signal that triggers this handler fired (see that function's own
	# "LootManager is an autoload singleton... instead of instantiating a
	# throwaway copy" comment - it was migrated to be the one canonical
	# source). This used to ALSO build a second, independent shield/jetpack/
	# missile/drone drop right here from the exact same meta - a confusing
	# duplicate pickup on top of the real one at best, and its tile-scatter
	# neighbor below was actively broken (see tile_data's own note). Removed;
	# the guaranteed scattered-tiles bonus is the one thing this function
	# still uniquely contributes (LootManager only ever rolls drops from the
	# boss's OWN equipped tiles, never fresh random ones).
	var drop_type = boss.get_meta("boss_drop", "shield")

	if drop_type == "mega":
		# Megaboss guaranteed Legendary Drop
		var pickup = load("res://scripts/entities/LootPickup.gd").new()
		pickup.global_position = boss.global_position

		# Generate a legendary tile
		var legend_tile = _generate_random_tile()
		legend_tile.rarity = HexTile.Rarity.LEGENDARY
		# LootPickup's field is `tile_data`, not `item_data` (no such
		# property exists) - was silently creating pickups that could never
		# actually be collected (neither the equipment_data nor tile_data
		# branch in LootPickup._on_body_entered ever matched).
		pickup.tile_data = legend_tile
		world.add_child(pickup)

	# NEW: Guarantee 3-5 scattered tiles for any Boss
	var drop_rarity = HexTile.Rarity.LEGENDARY if drop_type == "mega" else HexTile.Rarity.RARE
	_scatter_random_tiles(boss.global_position, randi_range(3, 5), drop_rarity)
		
	_on_enemy_died()

func _generate_random_tile() -> HexTile:
	var tile_types = [
		preload("res://scripts/tiles/WeaponMountTile.gd"),
		preload("res://scripts/tiles/AccumulatorTile.gd"),
		preload("res://scripts/tiles/ReflectorTile.gd"),
		preload("res://scripts/tiles/SplitterTile.gd"),
		preload("res://scripts/tiles/CatalystTile.gd"),
		preload("res://scripts/tiles/MagnetTile.gd"),
		preload("res://scripts/tiles/ShieldGeneratorTile.gd")
	]
	return tile_types.pick_random().new()

func _scatter_random_tiles(origin: Vector2, count: int, rarity: int):
	for i in range(count):
		var tile = _generate_random_tile()
		tile.rarity = rarity
		var pickup = load("res://scripts/entities/LootPickup.gd").new()
		# LootPickup's field is `tile_data`, not `item_data` (no such
		# property exists) - was silently spawning pickups that could never
		# actually be collected.
		pickup.tile_data = tile
		pickup.global_position = origin + Vector2(randf_range(-50, 50), randf_range(-50, 50))
		world.call_deferred("add_child", pickup)

# --- Rival Challenges (FEATURE_ROADMAP.md Story section) --------------------
# "Sometimes another player challenges you - a specialized match where the
# enemy mech is built to counter your play to date, directly or within
# +/-15% of directly." Locked cadence/tolerance per Natalia: every 10 waves,
# +/-15% of the player's own estimated power (SquadDirector._estimate_mech_power,
# the same yardstick the near-peer difficulty scaling already uses).

func _spawn_rival(director, force_rarity = -1, force_name = ""):
	var rival_rarity = director._player_dominant_rarity() if force_rarity == -1 else force_rarity
	
	var rival_name = force_name
	if rival_name == "":
		rival_name = director.get_next_rival()
		
	var profile: RivalProfile = null
	if director.all_rival_profiles.has(rival_name):
		profile = director.all_rival_profiles[rival_name]
		
	if profile:
		if profile.force_mythic_only:
			rival_rarity = HexTile.Rarity.MYTHIC
		elif profile.force_junk_only:
			rival_rarity = HexTile.Rarity.COMMON

	var role = "brawler"
	var mech_count = 1
	if profile:
		role = profile.base_role
		mech_count = profile.mech_count
		
	for i in range(mech_count):
		var role_to_spawn = role
		if rival_name == "Leo & Luna":
			role_to_spawn = "ambusher" if i == 0 else "sniper"

		var rival = director._spawn_bot_for_role(role_to_spawn, true, rival_rarity)
		rival.set_meta("is_rival", true)
		rival.set_meta("rival_name", rival_name)

		# Equivalent-budget constraint
		var player_power = director._estimate_mech_power(player)
		var rival_power = director._estimate_mech_power(rival)
		var target_power = player_power * randf_range(0.85, 1.15)
		var power_mult = clamp(target_power / max(1.0, rival_power), 0.4, 3.0)

		# If profile overrides HP, multiply
		if profile:
			power_mult *= profile.hp_mult

		rival.max_hp *= power_mult
		rival.hp = rival.max_hp
		if rival.max_shield_hp > 0:
			rival.max_shield_hp *= power_mult
			rival.shield_hp = rival.max_shield_hp
		rival.stat_modifiers["dmg_mult"] = rival.stat_modifiers.get("dmg_mult", 1.0) * power_mult

		rival.scale = Vector2(1.3, 1.3)
		var offset = Vector2(randf_range(500, 1000), randf_range(500, 1000))
		if randf() > 0.5: offset.x *= -1
		if randf() > 0.5: offset.y *= -1
		var center_spawn = player.global_position + offset
		rival.global_position = map.get_valid_spawn_position(center_spawn)
		rival.target = player
		rival.died.connect(_on_rival_defeated.bind(rival))
		rival.collision_layer = 4
		rival.collision_mask = 1 | 2 | 8
		active_enemies += 1
		# NOT world.add_child(rival) - director._spawn_bot_for_role() already
		# parented it under SquadDirector (itself already inside world), same
		# as every regular squad member (Squad.add_member only tracks a
		# reference, never reparents). A second add_child here throws "Can't
		# add child ... already has a parent 'SquadDirector'" - this was a
		# real crash every Rival wave.

		if i == 0:
			if rival.has_method("_show_floating_text"):
				rival._show_floating_text("RIVAL: " + rival_name, Color(1.0, 0.85, 0.2))
			if profile and profile.dialogue_intro != "":
				show_dialogue(rival_name, profile.dialogue_intro, Color(1.0, 0.85, 0.2), 8.0)

func _on_rival_defeated(rival):
	# Guaranteed decent-quality drop (matches the "earn merchandise" story
	# beat) - a component built at the same rarity the rival itself fought
	# at, so beating a Rival always feels worth the fight regardless of RNG.
	var rarity = rival.get("base_rarity") if "base_rarity" in rival else HexTile.Rarity.RARE
	
	if rival.has_meta("is_rival") and rival.has_meta("rival_name"):
		var r_name = rival.get_meta("rival_name")
		var director = world.get_node_or_null("SquadDirector")
		if director and director.all_rival_profiles.has(r_name):
			var prof = director.all_rival_profiles[r_name]
			var win_text = prof.dialogue_win
			if win_text == "":
				var dm = load("res://scripts/core/DialogueManager.gd").new()
				dm._ready()
				win_text = dm.get_generic_rival_win()
			show_dialogue("Shopkeeper", win_text, Color(0.8, 1.0, 0.8), 6.0)

	var drop = load("res://scripts/core/ComponentEquipment.gd").create_starter_backpack("brawler", max(rarity, HexTile.Rarity.RARE))
	if drop:
		var pickup = load("res://scripts/entities/LootPickup.gd").new()
		pickup.equipment_data = drop
		pickup.global_position = rival.global_position
		world.add_child(pickup)
		
	# NEW: Scatter 3-5 tiles
	_scatter_random_tiles(rival.global_position, randi_range(3, 5), rarity)

	_on_enemy_died()

# ---- PvP Traveling Champions (see scripts/pvp/ChampionCard.gd) -----------
# Spawns an imported ghost as a challenger fighting with the EXACT loadout
# it was exported with - no near-peer inflation (the whole point is meeting
# the other player's real build). HP scales from the ghost's OWN build
# power so a strong import is a strong fight and a junk import stays junk.
func _spawn_traveling_champion(ghost: Dictionary):
	var champ = Mech.new()
	champ.is_player = false
	champ.combat_role = "brawler"
	for slot_str in ghost.get("components", {}):
		var comp = SaveManager._deserialize_component(ghost["components"][slot_str])
		if comp:
			champ.equip_component(comp)
	var pilot = str(ghost.get("pilot_name", "Unknown Champion"))
	champ.set_meta("is_ghost", true)
	champ.set_meta("ghost_pilot", pilot)
	champ.set_meta("ghost_id", str(ghost.get("ghost_id", "")))
	champ.target = player
	champ.collision_layer = 4
	champ.collision_mask = 1 | 2 | 8

	var offset = Vector2(randf_range(500, 1000), randf_range(500, 1000))
	if randf() > 0.5: offset.x *= -1
	if randf() > 0.5: offset.y *= -1
	champ.global_position = map.get_valid_spawn_position(player.global_position + offset)
	world.add_child(champ)
	champ._recalculate_grid()

	var director = world.get_node_or_null("SquadDirector")
	if director:
		var own_power = director._estimate_mech_power(champ)
		champ.max_hp *= max(1.0, own_power / director.NEAR_PEER_BASELINE)
		champ.hp = champ.max_hp

	champ.died.connect(_on_champion_defeated.bind(champ))
	active_enemies += 1

	champ.scale = Vector2(1.3, 1.3)
	if champ.has_method("_show_floating_text"):
		champ._show_floating_text("CHAMPION: " + pilot, Color(0.6, 0.9, 1.0))
	var dm = load("res://scripts/core/DialogueManager.gd").new()
	dm._ready()
	var champ_dialogue = dm.get_travelling_champion()
	if champ_dialogue is Dictionary and champ_dialogue.get("intro", "") != "":
		show_dialogue(pilot, str(champ_dialogue["intro"]), Color(0.6, 0.9, 1.0), 8.0)

func _on_champion_defeated(champ):
	var ghost_id = str(champ.get_meta("ghost_id")) if champ.has_meta("ghost_id") else ""
	if ghost_id != "":
		ChampionCardScript.record_result(ghost_id, true) # player beat the ghost
	# Design ruling: a ghost ALWAYS drops a component + tiles biased by its
	# own equipped rarities. (Deliberately NOT counted toward the 10-boss
	# milestone - that counts regular wave bosses only.)
	LootManager.generate_ghost_loot(champ)
	if champ.has_meta("ghost_pilot"):
		show_dialogue("Shopkeeper", "%s's champion goes down! Their pilot will hear about this." % champ.get_meta("ghost_pilot"), Color(0.8, 1.0, 0.8), 6.0)
	_on_enemy_died()

func _on_enemy_died():
	active_enemies -= 1
	# Not while the wave is still trickling in - killing the first squads
	# before the rest deploy must not count as clearing the wave.
	if active_enemies == 0 and not _spawning_wave:
		_on_wave_cleared()

var last_garage_wave: int = 1

func _on_player_died():
	print("!!! GAME OVER - MAGNIFICENT EXPLOSION !!!")
	# Dying with a Traveling Champion still on the field counts as losing
	# the challenge - the ghost takes the rank points home.
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(enemy) and enemy.has_meta("is_ghost") and not enemy.get("is_dead"):
			ChampionCardScript.record_result(str(enemy.get_meta("ghost_id")), false)
			break
	_despawn_all_drones()
	player.visible = false
	player.set_process(false)
	player.set_physics_process(false)

	# Snapshot the death report now, while player.recent_damage_log is still
	# populated - see Mech.gd's field comment. Per Natalia's request:
	# "what squad got me, what elements they used".
	_show_death_report(player.recent_damage_log)

	var explosion = load("res://scripts/visuals/DeathExplosion.gd").new()
	explosion.global_position = player.global_position
	world.add_child(explosion)

	var director = world.get_node_or_null("SquadDirector")
	var loss_text_shown = false
	if director:
		# Check if player died to a rival to show loss text
		for mech in get_tree().get_nodes_in_group("enemy"):
			if mech.has_meta("is_rival") and mech.has_meta("rival_name"):
				director.consecutive_rival_losses += 1
				director.save_learned_state()
				
				if director.consecutive_rival_losses >= 3:
					SaveManager.tournament_arc_unlocked = false
					# Was a zero-arg call - save_game(save_name, mech, inventory)
					# requires all 3, so this threw and silently aborted the
					# rest of _on_player_died() every time, including the
					# 3-second "kick back to Garage" timer below. After a 3rd
					# straight Rival loss the game just hung - no dialogue, no
					# death report, no return to Garage. Matches Main.gd:1136's
					# existing autosave call for the same "player, player_inventory"
					# pattern used everywhere else in this file.
					SaveManager.save_game("autosave", player, player_inventory)
					var dm = load("res://scripts/core/DialogueManager.gd").new()
					dm._ready()
					show_dialogue("Shopkeeper", dm.get_game_over_3_loss(), Color(1.0, 0.5, 0.5), 10.0)
					loss_text_shown = true
				else:
					var r_name = mech.get_meta("rival_name")
					if director.all_rival_profiles.has(r_name):
						var prof = director.all_rival_profiles[r_name]
						var loss_text = prof.dialogue_loss
						if loss_text == "":
							var dm2 = load("res://scripts/core/DialogueManager.gd").new()
							dm2._ready()
							loss_text = dm2.get_generic_rival_loss()
						show_dialogue("Shopkeeper", loss_text, Color(1.0, 0.5, 0.5), 6.0)
						loss_text_shown = true
				break
	
	if not loss_text_shown:
		var dm = load("res://scripts/core/DialogueManager.gd").new()
		dm._ready()
		var footer = dm.get_death_footer()
		if footer != "":
			show_dialogue("Shopkeeper", footer, Color(0.8, 0.8, 0.8), 6.0)
	
	call_deferred("_show_death_report", player.recent_damage_log)
	
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

# "How did I die" breakdown (Natalia's playtest request) - aggregates
# Mech.recent_damage_log (last DEATH_LOG_LOOKBACK_SEC of damage taken) by
# attacker label and by element, then shows a small non-blocking panel over
# the death explosion. Doesn't block anything - it just auto-frees after a
# few seconds (or whenever the player backs out via the Garage/menu).
func _show_death_report(log: Array):
	if log.is_empty():
		return

	var by_label: Dictionary = {}
	var by_element: Dictionary = {}
	for entry in log:
		var l = str(entry.get("label", "Environment"))
		var e = str(entry.get("element", "RAW"))
		var amt = float(entry.get("amount", 0.0))
		by_label[l] = by_label.get(l, 0.0) + amt
		by_element[e] = by_element.get(e, 0.0) + amt

	var labels_sorted = by_label.keys()
	labels_sorted.sort_custom(func(a, b): return by_label[a] > by_label[b])
	var elements_sorted = by_element.keys()
	elements_sorted.sort_custom(func(a, b): return by_element[a] > by_element[b])

	var canvas = CanvasLayer.new()
	canvas.layer = 120
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS

	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.02, 0.02, 0.92)
	style.border_color = Color(1.0, 0.35, 0.3)
	style.set_border_width_all(2)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.custom_minimum_size = Vector2(460, 0)
	panel.position += Vector2(-230, 40)
	canvas.add_child(panel)

	var vbox = VBoxContainer.new()
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "DESTROYED"
	title.add_theme_font_size_override("font_size", 22)
	title.modulate = Color(1.0, 0.45, 0.4)
	vbox.add_child(title)

	var squad_parts: Array = []
	for l in labels_sorted:
		squad_parts.append("%s (%d)" % [l, int(round(by_label[l]))])
	var squad_line = Label.new()
	squad_line.text = "Hit by: " + ", ".join(squad_parts)
	squad_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	squad_line.custom_minimum_size = Vector2(428, 0)
	vbox.add_child(squad_line)

	var elem_line = Label.new()
	elem_line.text = "Elements: " + ", ".join(elements_sorted)
	elem_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	elem_line.custom_minimum_size = Vector2(428, 0)
	elem_line.modulate = Color(0.85, 0.85, 0.9)
	vbox.add_child(elem_line)

	add_child(canvas)

	var fade_timer = Timer.new()
	fade_timer.wait_time = 7.0
	fade_timer.one_shot = true
	fade_timer.timeout.connect(canvas.queue_free)
	canvas.add_child(fade_timer)
	fade_timer.start()

func _on_wave_cleared():
	print("--- WAVE CLEARED ---")
	AudioManager.set_combat_state(false) # back to the ambient loop
	# Occasional post-wave debrief when the director just logged a lopsided
	# kill pattern (see SquadDirector.get_debrief_line's gating).
	var tell_director = world.get_node_or_null("SquadDirector")
	if tell_director:
		var debrief = tell_director.get_debrief_line()
		if debrief != "":
			show_dialogue("Evan", debrief, Color(0.7, 0.9, 1.0), 5.0)
	current_wave += 1
	if current_wave > SaveManager.max_wave_reached:
		SaveManager.max_wave_reached = current_wave
	_start_intermission()

func _open_garage():
	print("Opening Garage Menu...")
	get_tree().paused = true
	AudioManager.set_combat_state(false) # garage is downtime regardless of how we got here
	_despawn_all_drones()

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
		# Anything could have changed in there - tile placement, routing,
		# synergy cycling, Mythic toggles, part swaps. The mech's
		# precalculated weapons are stale until _recalculate_grid runs, and
		# individual garage edit paths historically forgot to set this flag
		# (the "projectiles don't change until restart" bug). One
		# unconditional flag on deploy covers every edit path, present and
		# future.
		player.is_grid_dirty = true
		# Recalculate NOW rather than leaving it lazy - _shoot() only ever
		# ran _recalculate_grid() on-demand the first time is_grid_dirty was
		# true, which meant the (non-trivial: iterates every tile across
		# every component, then runs the full packet simulation) recalc
		# happened synchronously in the middle of the player's first shot
		# after every deploy, not just the first shot of a session. Natalia:
		# "the first time I shoot after a few seconds of not shooting it
		# freezes the game... a brief freeze, .25-.5 seconds." Doing it here
		# instead moves that cost to the deploy transition (already a scene
		# change moment) instead of interrupting live combat input.
		if player.has_method("_recalculate_grid"):
			player._recalculate_grid()
		SaveManager.save_game("autosave", player, player_inventory)
		_spawn_drones_if_needed()
		# Reactive music: key the soundtrack to the build that just left the
		# bay - the dominant synergy across every armed weapon's packet.
		var syn_totals: Dictionary = {}
		for data in player.precalculated_weapons:
			for k in data.packet.synergies:
				syn_totals[k] = syn_totals.get(k, 0.0) + data.packet.synergies[k]
		var dominant = EnergyPacket.SynergyType.RAW
		var dominant_val = 0.0
		for k in syn_totals:
			if syn_totals[k] > dominant_val:
				dominant_val = syn_totals[k]
				dominant = k
		AudioManager.set_dominant_synergy(dominant)

	if garage_ui:
		garage_ui.queue_free()
		garage_ui = null
		
	if active_enemies <= 0:
		_show_countdown()
