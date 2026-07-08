extends CanvasLayer

const CoreTile = preload("res://scripts/tiles/CoreTile.gd")

var panel: PanelContainer
var is_open: bool = false
var squad_type_dropdown: OptionButton
var opt_reactor: OptionButton
var force_ruins_check: CheckBox

# Small helpers so tab construction below stays readable - every debug tool
# is one _btn() line instead of four lines of Button boilerplate.
func _btn(parent: Control, text: String, cb: Callable) -> Button:
	var b = Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var vbox = VBoxContainer.new()
	vbox.name = title
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(vbox)
	return vbox

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100 # Always on top

	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0) # height sizes to tallest tab
	panel.position = Vector2(20, 20)
	panel.hide()
	add_child(panel)

	# Was one giant scrolling VBox - long enough that half the tools lived
	# below the fold and the scrollbar fought the map-button grid. A
	# TabContainer keeps every tool one click away with no scrolling, and
	# new debug tools just go on whichever tab fits (or a new tab) instead
	# of making the scroll longer.
	var outer = VBoxContainer.new()
	panel.add_child(outer)

	var title = Label.new()
	title.text = "--- DEBUG MENU (` to close) ---"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(title)

	var tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(tabs)

	# --- Tab: Spawn -------------------------------------------------------
	var tab_spawn = _tab(tabs, "Spawn")
	_btn(tab_spawn, "Spawn Enemy", _on_spawn_enemy)
	_btn(tab_spawn, "Spawn Army (50)", func():
		for i in range(50): _on_spawn_enemy()
	)

	var squad_spawn_label = Label.new()
	squad_spawn_label.text = "-- Spawn Squad Type --"
	squad_spawn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tab_spawn.add_child(squad_spawn_label)

	squad_type_dropdown = OptionButton.new()
	squad_type_dropdown.custom_minimum_size = Vector2(0, 32)
	tab_spawn.add_child(squad_type_dropdown)
	_btn(tab_spawn, "Spawn Selected Squad", _on_spawn_squad_type)
	_btn(tab_spawn, "Force Legendary Drop", _on_force_loot)

	# --- Tab: Player --------------------------------------------------------
	var tab_player = _tab(tabs, "Player")
	_btn(tab_player, "Heal Player", _on_heal_player)
	_btn(tab_player, "Restore Lost Components (2 Sets)", _on_restore_components)
	_btn(tab_player, "Upgrade Core to Legendary", _on_upgrade_core)
	_btn(tab_player, "Upgrade All Body Parts to Legendary", _on_upgrade_body_parts)
	_btn(tab_player, "Give Mythic Shield Backpack", func():
		var main = get_tree().current_scene
		if main and main.get("player") != null:
			var pack = load("res://scripts/core/ComponentEquipment.gd").create_shield_backpack()
			main.player.equip_component(pack)
			if main.get("garage_ui") != null:
				if main.garage_ui.has_method("_refresh_component_ui"):
					main.garage_ui._refresh_component_ui()
			print("[Debug] Equipped Mythic Shield Backpack!")
	)
	_btn(tab_player, "Give Mythic Drone Bay Backpack", func():
		var main = get_tree().current_scene
		if main and main.get("player") != null:
			var pack = load("res://scripts/core/ComponentEquipment.gd").create_drone_backpack(HexTile.Rarity.MYTHIC)
			main.player.equip_component(pack)
			if main.get("garage_ui") != null:
				if main.garage_ui.has_method("_refresh_component_ui"):
					main.garage_ui._refresh_component_ui()
			print("[Debug] Equipped Mythic Drone Bay Backpack! Deploy to see the Drone tab and spawn the companion.")
	)

	opt_reactor = OptionButton.new()
	opt_reactor.add_item("Reactor: KINETIC", EnergyPacket.SynergyType.KINETIC)
	opt_reactor.add_item("Reactor: FIRE", EnergyPacket.SynergyType.FIRE)
	opt_reactor.add_item("Reactor: ICE", EnergyPacket.SynergyType.ICE)
	opt_reactor.add_item("Reactor: LIGHTNING", EnergyPacket.SynergyType.LIGHTNING)
	opt_reactor.add_item("Reactor: VORTEX", EnergyPacket.SynergyType.VORTEX)
	opt_reactor.add_item("Reactor: POISON", EnergyPacket.SynergyType.POISON)
	opt_reactor.add_item("Reactor: EXPLOSION", EnergyPacket.SynergyType.EXPLOSION)
	opt_reactor.add_item("Reactor: PIERCE", EnergyPacket.SynergyType.PIERCE)
	opt_reactor.add_item("Reactor: VAMPIRIC", EnergyPacket.SynergyType.VAMPIRIC)
	opt_reactor.item_selected.connect(_on_reactor_changed)
	tab_player.add_child(opt_reactor)

	_btn(tab_player, "Teleport to Garage", func():
		_toggle_menu()
		var main = get_tree().current_scene
		if main and main.has_method("_open_garage"):
			main._open_garage()
	)

	# --- Tab: Inventory ------------------------------------------------------
	var tab_inv = _tab(tabs, "Inventory")
	_btn(tab_inv, "Give GOD Inventory (50x All Legendary)", _on_give_god_inventory)
	_btn(tab_inv, "Give MYTHIC Inventory (50x All Mythic)", func(): _on_give_god_inventory(true))
	_btn(tab_inv, "Give Mythic Components (1 Set)", _on_give_mythic_components)

	# --- Tab: World ---------------------------------------------------------
	var tab_world = _tab(tabs, "World")

	var spawn_as_label = Label.new()
	spawn_as_label.text = "-- Spawn Map As --"
	spawn_as_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tab_world.add_child(spawn_as_label)

	# Ruins were Tabletop-only originally; this lets any map type below
	# generate them too. Read at press-time by each map button below, so
	# toggling it doesn't require reopening the menu.
	force_ruins_check = CheckBox.new()
	force_ruins_check.text = "Force Ruins (any map type)"
	tab_world.add_child(force_ruins_check)

	var map_grid = GridContainer.new()
	map_grid.columns = 3
	tab_world.add_child(map_grid)

	var map_types = ["Normal", "Arena", "Open Field", "Desert", "Forest", "Tundra", "Volcano", "Dungeon", "Water", "Tabletop"]
	var map_colors = [Color(0.4, 0.8, 0.4), Color(0.15, 0.1, 0.2), Color(0.4, 0.8, 0.4), Color(0.9, 0.8, 0.5), Color(0.1, 0.5, 0.2), Color(0.8, 0.9, 0.9), Color(0.3, 0.1, 0.1), Color(0.15, 0.1, 0.2), Color(0.2, 0.4, 0.9), Color(0.85, 0.7, 0.45)]

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
			# GameMap lives under Main.world (the pixel-viewport game world),
			# not directly under Main - see Main.gd's _setup_pixel_viewport().
			var map = main.world.get_node_or_null("GameMap") if (main and "world" in main and main.world) else null
			if map:
				map.map_type = map_type
				map.force_ruins = force_ruins_check.button_pressed
				map._generate_map()
				map._draw_map_to_texture()
				map._build_navigation()
				# Map sizes can differ wildly (Tabletop is 64x32 vs the
				# 400x250 default) - drop the player onto the new map's
				# center so they're never stranded outside its walls.
				if main.get("player") != null:
					var center = Vector2(map.width * map.tile_size / 2.0, map.height * map.tile_size / 2.0)
					main.player.global_position = map.get_valid_spawn_position(center)
		)
		map_grid.add_child(btn)

	_btn(tab_world, "Toggle Slomo (0.2x)", func():
		Engine.time_scale = 0.2 if Engine.time_scale == 1.0 else 1.0
	)

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_QUOTELEFT: # The ` key
			_toggle_menu()

func _toggle_menu():
	is_open = not is_open
	panel.visible = is_open
	get_tree().paused = is_open
	if is_open:
		_refresh_squad_dropdown()

# Templates evolve over a session (mutation/culling - see SquadDirector.gd),
# so this list is rebuilt fresh every time the menu opens rather than once
# at _ready(), when SquadDirector likely doesn't even exist yet.
func _refresh_squad_dropdown():
	if not squad_type_dropdown:
		return
	squad_type_dropdown.clear()
	var director = _get_squad_director()
	if not director:
		return
	for t in director.templates:
		var label = t.template_name
		if t.is_experimental:
			label += " (experimental)"
		squad_type_dropdown.add_item(label)

func _get_squad_director():
	var main = get_tree().current_scene
	# SquadDirector lives under Main.world (the pixel-viewport game world),
	# not directly under Main - see Main.gd's _setup_pixel_viewport().
	if not main or not ("world" in main) or not main.world:
		return null
	return main.world.get_node_or_null("SquadDirector")

func _on_spawn_squad_type():
	var director = _get_squad_director()
	if not director or squad_type_dropdown.item_count == 0:
		return
	var idx = squad_type_dropdown.selected
	if idx < 0 or idx >= director.templates.size():
		return
	var template = director.templates[idx]

	var main = get_tree().current_scene
	if not main or not main.get("map") or not main.get("player"):
		return

	# Spawn point is always 50 units closer to the map center than the
	# player currently is, regardless of which direction that ends up being.
	var map = main.map
	var map_center = Vector2(map.width * map.tile_size / 2.0, map.height * map.tile_size / 2.0)
	var player_pos = main.player.global_position
	var dir_to_center = (map_center - player_pos).normalized()
	if dir_to_center == Vector2.ZERO:
		dir_to_center = Vector2.RIGHT # Player is exactly at map center - direction is arbitrary
	var spawn_pos = player_pos + dir_to_center * 50.0

	director.spawn_specific_squad(template, spawn_pos)
	_toggle_menu() # Close (and unpause) so you can immediately see it

func _on_spawn_enemy():
	var main = get_tree().current_scene
	if not main or not ("world" in main) or not main.world:
		return
	# SquadDirector (and anything it spawns) lives under Main.world (the
	# pixel-viewport game world) - see Main.gd's _setup_pixel_viewport().
	var director = main.world.get_node_or_null("SquadDirector")

	if not director:
		director = load("res://scripts/ai/SquadDirector.gd").new()
		director.name = "SquadDirector"
		main.world.add_child(director)
		
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
		# Spawn as a sibling of the player (i.e. into Main.world, the pixel
		# viewport's game world) rather than via current_scene, which is
		# Main itself - outside the pixelated viewport since this session's
		# visual identity pass.
		player[0].get_parent().add_child(drop)

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
		var slots = [HexTile.BodySlot.TORSO, 
					 HexTile.BodySlot.HEAD, 
					 HexTile.BodySlot.LEG_L, 
					 HexTile.BodySlot.LEG_R, 
					 HexTile.BodySlot.ARM_L, 
					 HexTile.BodySlot.ARM_R,
					 HexTile.BodySlot.BACKPACK]
		
		for slot in slots:
			if mech.components.has(slot):
				var comp = mech.components[slot]
				comp.rarity = HexTile.Rarity.LEGENDARY
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
			if core and core.has_method("set_face_output"):
				# opt_reactor is now a stored member (the old code re-found it
				# by scanning panel children, which broke the moment the panel
				# hierarchy changed - as it just did with the tab layout).
				var syn_id = opt_reactor.get_item_id(index)
				for i in range(6):
					core.set_face_output(i, syn_id)
				print("[Debug] Reactor output overridden to synergy ID: ", syn_id)

func _on_restore_components():
	var main = get_tree().current_scene
	if main and main.get("player") != null:
		var ScriptComponentEquipment = load("res://scripts/core/ComponentEquipment.gd")
		var rarity = HexTile.Rarity.LEGENDARY
		
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

func _on_give_god_inventory(is_mythic: bool = false):
	var main = get_tree().current_scene

	if not main or main.get("player_inventory") == null:
		return
		
	var Rarity = HexTile.Rarity
	var tile_scripts = [
		"res://scripts/tiles/SplitterTile.gd",
		"res://scripts/tiles/AmplifierTile.gd",
		"res://scripts/tiles/ReflectorTile.gd",
		"res://scripts/tiles/CatalystTile.gd",
		"res://scripts/tiles/InfuserTile.gd",
		"res://scripts/tiles/JumpjetTile.gd",
		"res://scripts/tiles/WeaponMountTile.gd",
		"res://scripts/tiles/AccumulatorTile.gd",
		"res://scripts/tiles/ActuatorTile.gd",
		"res://scripts/tiles/DirectionalConduitTile.gd",
		"res://scripts/tiles/FilterTile.gd",
		"res://scripts/tiles/MagnetTile.gd",
		"res://scripts/tiles/MicrocoreTile.gd",
		"res://scripts/tiles/ResonatorTile.gd",
		"res://scripts/tiles/ShieldGeneratorTile.gd",
		"res://scripts/tiles/ShieldTile.gd"
	]
	
	# Give 50 of each normal tile
	for path in tile_scripts:
		var script = load(path)
		if not script: continue
		for i in range(50):
			var tile = script.new()
			tile.rarity = Rarity.MYTHIC if is_mythic else Rarity.LEGENDARY
			main.player_inventory.append(tile)

			if main.get("garage_ui") != null and main.garage_ui.get("inventory") != null:
				if main.garage_ui.inventory != main.player_inventory:
					main.garage_ui.inventory.append(tile)
					
	if main.get("garage_ui") != null:
		if main.garage_ui.has_method("_refresh_inventory_ui"):
			main.garage_ui._refresh_inventory_ui()
	print("[Debug] Added GOD Inventory (50x All Legendary or Mythic)")

func _on_give_mythic_components():
	var main = get_tree().current_scene
	if main and main.get("player_component_inventory") != null:
		var ScriptComponentEquipment = load("res://scripts/core/ComponentEquipment.gd")
		var rarity = HexTile.Rarity.MYTHIC
		
		var comps = [
			ScriptComponentEquipment.create_starter_torso("Mythic Torso", rarity),
			ScriptComponentEquipment.create_starter_head("Mythic Head", rarity),
			ScriptComponentEquipment.create_starter_arm(true, "Mythic Arm L", rarity),
			ScriptComponentEquipment.create_starter_arm(false, "Mythic Arm R", rarity),
			ScriptComponentEquipment.create_starter_leg(true, "Mythic Leg L", rarity),
			ScriptComponentEquipment.create_starter_leg(false, "Mythic Leg R", rarity),
			ScriptComponentEquipment.create_jetpack_backpack()
		]
		comps[6].rarity = rarity
		comps[6].component_name = "Mythic Jetpack"
		
		for c in comps:
			main.player_component_inventory.append(c)
			
		if main.get("garage_ui") != null and main.garage_ui.has_method("_refresh_component_ui"):
			main.garage_ui._refresh_component_ui()
		print("[Debug] Added 1 full set of Mythic components to inventory!")
