class_name GarageMenu
extends CanvasLayer



const ComponentEquipment = preload("res://scripts/core/ComponentEquipment.gd")
const SplitterTile = preload("res://scripts/tiles/SplitterTile.gd")
const AmplifierTile = preload("res://scripts/tiles/AmplifierTile.gd")
const CatalystTile = preload("res://scripts/tiles/CatalystTile.gd")
const GarageGridRenderer = preload("res://scripts/ui/GarageGridRenderer.gd")
const ComponentDiagramView = preload("res://scripts/ui/ComponentDiagramView.gd")

var inventory_panel: PanelContainer
var grid_panel: PanelContainer
var grid_renderer: GarageGridRenderer
var inv_vbox: VBoxContainer
var stats_label: Label
var tooltip_label: Label
var component_tabs: TabBar
var warning_label: Label
var scrap_label: Label
# Spare FULL components (arm/leg/torso/head/backpack assemblies) - a
# completely separate pool from the hex-tile inventory list below, and
# previously not shown anywhere in the Garage at all. Swap Component,
# Upgrade Part, and Extract Modifier all consume from THIS pool, not from
# tiles - per Natalia, that was invisible enough to look like those
# features were just broken ("I can only upgrade the torso... swap doesn't
# work even if I own another of them"). This visualizes the pool two ways:
# a zoomable slot diagram (component_diagram) showing what's equipped where,
# and a sortable, draggable spare-parts tray (component_inventory_list) you
# drag straight onto a diagram slot to equip/swap - no more digging through
# tabs to find the one that happens to have a compatible spare.
var component_inventory_list: HFlowContainer
var component_diagram: ComponentDiagramView = null
var tile_panel: VBoxContainer
# Components mode splits across THREE regions rather than one panel (see
# _set_inventory_view): component_diagram_panel (label + the big mech-loadout
# diagram) becomes the PRIMARY view in grid_panel's spot; side_grid_container
# gets a shrunk live hex-grid preview of whichever part is selected; and
# component_spare_panel (sort dropdown + the actual draggable spare-parts
# cards) lives in the sidebar space freed up by shrinking side_grid_container.
# Previously all of this was one "component_panel" stacked in the sidebar,
# which is why Natalia couldn't find her purchased parts - the tray was
# real, just squeezed/scrolled out of view under the diagram every time.
var component_diagram_panel: VBoxContainer
var component_spare_panel: VBoxContainer
var tile_sort: OptionButton
var component_sort: OptionButton
var side_grid_container: PanelContainer

# Manual drag state for spare-component cards, mirroring the existing
# dragged_tile/drag_preview pattern below (hex tiles) rather than introducing
# Godot's separate built-in Control drag-drop protocol for just this one case.
var dragged_component = null
var component_drag_preview: PanelContainer = null
var _component_drag_label: Label = null


var active_component: ComponentEquipment
var mech_components: Dictionary = {}

# Shared Mythic inventory-button shimmer material: built once and reused
# across every button/refresh instead of a fresh Shader+ShaderMaterial per
# button per _refresh_inventory_ui() call (which fires on every keystroke,
# scrap change, and upgrade - was allocating and recompiling a shader dozens
# of times a minute for no reason, since the shader has no per-instance
# uniforms and is perfectly safe to share).
static var _mythic_shimmer_mat: ShaderMaterial = null

static func _get_mythic_shimmer_mat() -> ShaderMaterial:
	if _mythic_shimmer_mat == null:
		var shader = Shader.new()
		shader.code = """
		shader_type canvas_item;
		void fragment() {
			float wave = sin(TIME * 1.5 - UV.x * 5.0 - UV.y * 5.0);
			float shine = smoothstep(0.9, 1.0, wave) * 0.3;
			COLOR = COLOR + vec4(0.3, 0.9, 0.9, 0.0) * shine;
		}
		"""
		_mythic_shimmer_mat = ShaderMaterial.new()
		_mythic_shimmer_mat.shader = shader
	return _mythic_shimmer_mat

var dragged_tile: HexTile = null
var drag_preview: Polygon2D = null

# Drag-to-paint-a-line state: normal drag-and-drop still just places one
# tile at wherever you release (unchanged). But if you pause over a cell
# mid-drag, that becomes a fill origin - continuing to drag from there
# paints a line of the SAME tile type across every cell the drag crosses,
# consuming additional matching copies from inventory as it goes.
const FILL_PAUSE_THRESHOLD = 0.4 # seconds stationary before fill mode kicks in
var drag_hover_hex: HexCoord = null
var drag_hover_since: float = 0.0
var fill_mode: bool = false
var fill_origin_hex: HexCoord = null

var inventory: Array = []
var search_input: LineEdit
var rarity_filter: OptionButton
var sim_button: Button

var is_simulating: bool = false

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("garage_menu") # lets TutorialManager know the Garage is open
	_setup_ui()
	
	# Hook up the player's components if they exist
	if get_parent() and get_parent().get("player") != null:
		mech_components = get_parent().player.components
			
		if get_parent().get("player_inventory") != null:
			inventory = get_parent().player_inventory
			
		# Fallback initial loadout if empty
		if inventory.is_empty():
			_populate_mock_inventory()
			
	_populate_component_tabs()
	_refresh_inventory_ui()

func _populate_component_tabs():
	component_tabs.clear_tabs()
	if mech_components.is_empty():
		return

	for slot in mech_components.keys():
		var comp = mech_components[slot]
		component_tabs.add_tab(comp.component_name)
		component_tabs.set_tab_metadata(component_tabs.get_tab_count() - 1, slot)

	# Drone tab: only shown once a Drone Bay tile is actually installed
	# somewhere in the equipped Backpack's hex grid (see DroneBayTile.gd).
	# Its loadout is NOT one of mech_components' own entries (deliberately -
	# see HexTile.BodySlot.DRONE's comment), so it's appended here with a
	# DRONE sentinel tab metadata that _on_tab_changed special-cases instead
	# of indexing straight into mech_components like every other tab.
	if _find_drone_bay_tile():
		component_tabs.add_tab("Drone")
		component_tabs.set_tab_metadata(component_tabs.get_tab_count() - 1, HexTile.BodySlot.DRONE)

	_on_tab_changed(0)

# Returns the equipped Backpack's Drone Bay tile (if any), or null if there's
# no Backpack equipped or it doesn't have one installed.
func _find_drone_bay_tile():
	if not mech_components.has(HexTile.BodySlot.BACKPACK):
		return null
	var DroneBayTileClass = load("res://scripts/tiles/DroneBayTile.gd")
	return DroneBayTileClass.find_in_backpack(mech_components[HexTile.BodySlot.BACKPACK])

func _refresh_component_ui():
	# If player was loaded or components changed, update the reference and tabs
	if get_parent() and get_parent().get("player") != null:
		mech_components = get_parent().player.components
	_populate_component_tabs()
	_update_chip_label()
	if component_diagram:
		component_diagram.refresh(mech_components)

# Switches between "Tiles" (edit one component's hex grid, full-size, in the
# main area - the original/default layout) and "Components" (equip/swap whole
# parts across the mech), which now spans three regions instead of one panel:
#   - grid_panel (main area): component_diagram_panel - the big mech-loadout
#     diagram, the PRIMARY view in this mode.
#   - side_grid_container (sidebar, top): a shrunk live hex-grid preview of
#     whichever part is currently selected - via a diagram slot click
#     (_on_diagram_slot_pressed) or a tab (_on_tab_changed), both unchanged.
#   - component_spare_panel (sidebar, bottom): the actual draggable
#     spare-parts cards, in the space freed up by shrinking the preview above
#     it. This used to be stacked under the diagram and regularly got
#     squeezed/scrolled out of view - splitting it into its own guaranteed
#     sidebar slot means it's never competing with the diagram for room.
# Reparenting (not just toggling .visible) is what actually moves a Control
# between regions in Godot.
func _set_inventory_view(mode: String):
	if tile_panel:
		tile_panel.visible = (mode == "tiles")

	if mode == "components":
		if component_diagram_panel and component_diagram_panel.get_parent() != grid_panel:
			component_diagram_panel.get_parent().remove_child(component_diagram_panel)
			grid_panel.add_child(component_diagram_panel)
			component_diagram_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			component_diagram_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if grid_renderer and side_grid_container and grid_renderer.get_parent() != side_grid_container:
			grid_renderer.get_parent().remove_child(grid_renderer)
			side_grid_container.add_child(grid_renderer)
		if component_spare_panel and side_grid_container and component_spare_panel.get_parent() != side_grid_container.get_parent():
			component_spare_panel.get_parent().remove_child(component_spare_panel)
			side_grid_container.get_parent().add_child(component_spare_panel)
			# Keep it directly under side_grid_container in the sidebar's
			# child order rather than wherever add_child happened to append it.
			side_grid_container.get_parent().move_child(component_spare_panel, side_grid_container.get_index() + 1)
		if component_diagram_panel:
			component_diagram_panel.visible = true
		if side_grid_container:
			side_grid_container.visible = true
		if component_spare_panel:
			component_spare_panel.visible = true
	else:
		var sidebar = tile_panel.get_parent() if tile_panel else null
		if component_diagram_panel and sidebar and component_diagram_panel.get_parent() != sidebar:
			component_diagram_panel.get_parent().remove_child(component_diagram_panel)
			sidebar.add_child(component_diagram_panel)
		if component_spare_panel and sidebar and component_spare_panel.get_parent() != sidebar:
			component_spare_panel.get_parent().remove_child(component_spare_panel)
			sidebar.add_child(component_spare_panel)
		if component_diagram_panel:
			component_diagram_panel.visible = false
		if component_spare_panel:
			component_spare_panel.visible = false
		if grid_renderer and grid_renderer.get_parent() != grid_panel:
			grid_renderer.get_parent().remove_child(grid_renderer)
			grid_panel.add_child(grid_renderer)
		if side_grid_container:
			side_grid_container.visible = false

# Clicking a slot callout on the diagram jumps the grid editor to that
# component's tab - lets you go straight from "here's what's equipped in the
# Right Arm" to editing its hex grid without hunting through the tab strip.
func _on_diagram_slot_pressed(slot_type):
	for i in range(component_tabs.get_tab_count()):
		if component_tabs.get_tab_metadata(i) == slot_type:
			component_tabs.current_tab = i
			_on_tab_changed(i)
			return

func _on_tab_changed(index: int):
	if index < 0 or index >= component_tabs.get_tab_count():
		return
		
	var slot = component_tabs.get_tab_metadata(index)
	if slot == null: return

	if slot == HexTile.BodySlot.DRONE:
		var drone_bay = _find_drone_bay_tile()
		if not drone_bay:
			return
		active_component = drone_bay.get_or_build_loadout()
	else:
		active_component = mech_components[slot]

	grid_renderer.setup(active_component.hex_grid, self)
	grid_renderer.active_component = active_component

	# Ensure any TORSO-slot component always has a Core - this covers both
	# the real Torso tab AND the Drone tab (a Drone's own body is registered
	# as slot_type TORSO too - see ComponentEquipment.create_starter_drone -
	# so it gets the same auto-Core guarantee rather than sitting there empty
	# until the drone actually gets spawned/equipped for the first time).
	if active_component.slot_type == HexTile.BodySlot.TORSO:
		var has_core = false
		var h0 = HexCoord.new(0, 0)
		if active_component.hex_grid.has_tile(h0):
			var existing_tile = active_component.hex_grid.get_tile(h0)
			if existing_tile and existing_tile.tile_type == "Core Reactor":
				has_core = true
			else:
				var removed = active_component.hex_grid.remove_tile(h0)
				inventory.append(removed)

		if not has_core:
			var core_tile = load("res://scripts/tiles/CoreTile.gd").new()
			core_tile.body_slot = HexTile.BodySlot.TORSO
			active_component.hex_grid.add_tile(h0, core_tile)
			print("Restored missing Torso Core!")
func _populate_mock_inventory():
	var main = get_tree().current_scene
	if main and "player_inventory" in main and main.player_inventory.size() > 0:
		inventory = main.player_inventory.duplicate()
		return
		
	# Fallback mock inventory
	var rare_split = SplitterTile.new()
	rare_split.rarity = HexTile.Rarity.RARE
	inventory.append(rare_split)
	
	var rare_amp = AmplifierTile.new()
	rare_amp.rarity = HexTile.Rarity.RARE
	inventory.append(rare_amp)
	
	var bp_link = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.BACKPACK, true)
	bp_link.tile_type = "Backpack Link"
	inventory.append(bp_link)
	
	var leg_cat = CatalystTile.new()
	leg_cat.output_synergy = EnergyPacket.SynergyType.LIGHTNING
	leg_cat.rarity = HexTile.Rarity.LEGENDARY
	inventory.append(leg_cat)
	
	var poison_infuser = load("res://scripts/tiles/InfuserTile.gd").new()
	poison_infuser.secondary_synergy = EnergyPacket.SynergyType.POISON
	poison_infuser.rarity = HexTile.Rarity.RARE
	inventory.append(poison_infuser)
	
	var reflector = load("res://scripts/tiles/ReflectorTile.gd").new()
	reflector.rotation_steps = 1
	reflector.rarity = HexTile.Rarity.COMMON
	inventory.append(reflector)

func _setup_ui():
	layer = 10
	
	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08, 0.4) # Mostly transparent
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	var hsplit = HSplitContainer.new()
	hsplit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(hsplit)
	
	# Left Side: Grid Editor
	var left_vbox = VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsplit.add_child(left_vbox)
	
	var top_bar = VBoxContainer.new()
	left_vbox.add_child(top_bar)
	
	var grid_label = Label.new()
	grid_label.text = " (Drag to pan, Scroll to zoom, E to rotate, Right-click to remove)"
	grid_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(grid_label)
	
	var tab_hbox = HBoxContainer.new()
	top_bar.add_child(tab_hbox)
	
	component_tabs = TabBar.new()
	component_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	component_tabs.tab_changed.connect(_on_tab_changed)
	tab_hbox.add_child(component_tabs)
	
	var action_vbox = VBoxContainer.new()
	tab_hbox.add_child(action_vbox)
	
	var swap_btn = Button.new()
	swap_btn.text = "Swap Component"
	swap_btn.pressed.connect(_on_swap_component_pressed)
	action_vbox.add_child(swap_btn)
	
	var infuse_btn = Button.new()
	infuse_btn.text = "Infuse (Destroy part)"
	infuse_btn.pressed.connect(_on_infuse_component_pressed)
	action_vbox.add_child(infuse_btn)

	var codex_btn = Button.new()
	codex_btn.text = "Synergy Codex"
	codex_btn.pressed.connect(_on_codex_pressed)
	action_vbox.add_child(codex_btn)
	
	grid_panel = PanelContainer.new()
	grid_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_panel.add_to_group("tutorial:grid_panel") # onboarding spotlight anchor - see TutorialManager.gd
	left_vbox.add_child(grid_panel)
	
	grid_renderer = GarageGridRenderer.new()
	grid_renderer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_renderer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_renderer.tooltip_requested.connect(_on_tooltip_requested)
	grid_renderer.tooltip_cleared.connect(_on_tooltip_cleared)
	grid_renderer.tile_clicked.connect(_on_tile_clicked)
	grid_panel.add_child(grid_renderer)
	
	# Add a warning label
	warning_label = Label.new()
	warning_label.name = "WarningLabel"
	warning_label.modulate = Color(1.0, 0.5, 0.5)
	warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning_label.hide()
	top_bar.add_child(warning_label)
	
	# Bottom Bar
	var bottom_bar = HBoxContainer.new()
	left_vbox.add_child(bottom_bar)
	
	sim_button = Button.new()
	sim_button.name = "SimButton"
	sim_button.text = "Simulate Energy Flow"
	sim_button.custom_minimum_size = Vector2(200, 50)
	sim_button.add_to_group("tutorial:sim_button") # onboarding spotlight anchor - see TutorialManager.gd
	sim_button.pressed.connect(_on_simulate_pressed)
	bottom_bar.add_child(sim_button)
	
	var auto_button = Button.new()
	auto_button.text = "Auto-Equip"
	auto_button.custom_minimum_size = Vector2(120, 50)
	auto_button.pressed.connect(_on_auto_equip_pressed)
	bottom_bar.add_child(auto_button)

	var clear_button = Button.new()
	clear_button.text = "Clear Grid"
	clear_button.custom_minimum_size = Vector2(120, 50)
	clear_button.pressed.connect(_on_clear_grid_pressed)
	bottom_bar.add_child(clear_button)
	
	var sep_fire_toggle = CheckButton.new()
	sep_fire_toggle.text = "Separate L/R Firing"
	
	if get_parent() and get_parent().get("player") != null:
		sep_fire_toggle.button_pressed = get_parent().player.separate_arm_firing
	else:
		sep_fire_toggle.button_pressed = true
		
	sep_fire_toggle.toggled.connect(func(pressed):
		if get_parent() and get_parent().get("player") != null:
			get_parent().player.separate_arm_firing = pressed
	)
	bottom_bar.add_child(sep_fire_toggle)
	
	var paths_toggle = CheckButton.new()
	paths_toggle.text = "Show Static Paths"
	paths_toggle.button_pressed = true
	paths_toggle.toggled.connect(func(pressed):
		grid_renderer.show_static_paths = pressed
		grid_renderer.queue_redraw()
	)
	bottom_bar.add_child(paths_toggle)
	
	var deploy_button = Button.new()
	deploy_button.text = "Deploy to Battlefield ->"
	deploy_button.custom_minimum_size = Vector2(200, 50)
	deploy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deploy_button.pressed.connect(func():
		var main = get_parent()
		if main and main.get("player") != null:
			SaveManager.save_game("autosave", main.player, inventory)
		if main and main.has_method("_close_garage"):
			main._close_garage()
	)
	bottom_bar.add_child(deploy_button)
	
	# Loadouts Bar
	var loadout_bar = HBoxContainer.new()
	left_vbox.add_child(loadout_bar)
	
	var loadout_lbl = Label.new()
	loadout_lbl.text = "Loadouts: "
	loadout_bar.add_child(loadout_lbl)
	
	for i in range(1, 4):
		var btn = Button.new()
		btn.text = "Load " + str(i)
		btn.pressed.connect(func():
			var main = get_parent()
			if main and main.get("player") != null:
				if SaveManager.load_loadout(i, main.player, inventory):
					_refresh_component_ui()
					_refresh_inventory_ui()
		)
		loadout_bar.add_child(btn)
		
		var save_btn = Button.new()
		save_btn.text = "Save " + str(i)
		save_btn.pressed.connect(func():
			var main = get_parent()
			if main and main.get("player") != null:
				SaveManager.save_loadout(i, main.player)
		)
		loadout_bar.add_child(save_btn)

	# Per-component loadout bar (FEATURE_ROADMAP.md group 1): same idea as
	# the full-build slots above, but scoped to whichever component tab is
	# currently open - lets a favorite arm/torso wiring be reused across
	# otherwise different builds. Slots are keyed per body-slot type in
	# SaveManager, so "Part Load 1" on the Torso tab is a different file
	# from "Part Load 1" on the Left Arm tab.
	var part_loadout_bar = HBoxContainer.new()
	left_vbox.add_child(part_loadout_bar)

	var part_lbl = Label.new()
	part_lbl.text = "This part: "
	part_loadout_bar.add_child(part_lbl)

	for i in range(1, 4):
		var p_load = Button.new()
		p_load.text = "Load " + str(i)
		p_load.pressed.connect(func():
			var main = get_parent()
			if not active_component or not main or main.get("player") == null:
				return
			var slot_type = active_component.slot_type
			var loaded = SaveManager.load_component_loadout(i, slot_type)
			if not loaded:
				return
			# Swap just this one component on the mech, then re-point the
			# garage at the fresh instance via the normal tab-change path.
			# (Same replace semantics as the full-build loadout slots: the
			# outgoing part and its tiles are not refunded to inventory.)
			var old = main.player.unequip_component(slot_type)
			if old:
				old.queue_free()
			main.player.equip_component(loaded)
			_refresh_component_ui()
			_on_tab_changed(component_tabs.current_tab)
		)
		part_loadout_bar.add_child(p_load)

		var p_save = Button.new()
		p_save.text = "Save " + str(i)
		p_save.pressed.connect(func():
			if active_component:
				SaveManager.save_component_loadout(i, active_component)
		)
		part_loadout_bar.add_child(p_save)

	# Scrap sinks (FEATURE_ROADMAP.md group 2): repair and infusion give
	# scrap something to buy beyond the tile-upgrade middle-click.
	var scrap_sink_bar = HBoxContainer.new()
	left_vbox.add_child(scrap_sink_bar)

	var repair_btn = Button.new()
	repair_btn.text = "Repair All"
	repair_btn.tooltip_text = "1 scrap per 2 missing HP, +25 per knocked-out tile, +100 per destroyed tile"
	repair_btn.pressed.connect(_on_repair_all)
	scrap_sink_bar.add_child(repair_btn)

	# NOTE: named infuse_xp_btn, not infuse_btn - _setup_ui already declares
	# an infuse_btn at the top (the "Infuse (Destroy part)" modifier-infusion
	# button), and GDScript treats a duplicate local name in the same
	# function scope as a compile error, which silently killed the whole
	# garage (GDScript::reload fails -> _open_garage gets a scriptless class).
	var infuse_xp_btn = Button.new()
	infuse_xp_btn.text = "Infuse This Part (+100 XP / 100 scrap)"
	infuse_xp_btn.tooltip_text = "500 XP per infusion level. Legendary+ parts roll a random stat modifier each level."
	infuse_xp_btn.pressed.connect(_on_infuse_part)
	scrap_sink_bar.add_child(infuse_xp_btn)

	# --- Feature 5 row: upgrades, modifier chips, Black Market ---------------
	var feature5_bar = HBoxContainer.new()
	left_vbox.add_child(feature5_bar)

	var upgrade_part_btn = Button.new()
	upgrade_part_btn.text = "Upgrade Part"
	upgrade_part_btn.tooltip_text = "Tier this part up one rarity: costs scrap plus ONE same-slot salvage part. YOU place the new hexes - click the pulsing cells on the grid."
	upgrade_part_btn.pressed.connect(_on_upgrade_part)
	feature5_bar.add_child(upgrade_part_btn)

	var extract_btn = Button.new()
	extract_btn.text = "Extract Modifier"
	extract_btn.tooltip_text = "Scraps the first spare component that carries a stat modifier and saves that modifier as a chip."
	extract_btn.pressed.connect(_on_extract_modifier)
	feature5_bar.add_child(extract_btn)

	var chip_btn = Button.new()
	chip_btn.text = "Infuse Chip"
	chip_btn.tooltip_text = "Applies your oldest extracted modifier chip to the current part. Chips stack, capped at +50% per stat."
	chip_btn.pressed.connect(_on_infuse_chip)
	feature5_bar.add_child(chip_btn)

	chip_count_label = Label.new()
	chip_count_label.text = "Chips: 0"
	feature5_bar.add_child(chip_count_label)

	var market_btn = Button.new()
	market_btn.text = "BLACK MARKET"
	market_btn.modulate = Color(1.0, 0.5, 0.9)
	market_btn.tooltip_text = "Experimental oversized parts with severe drawbacks. Stock rotates every 10 real-time minutes."
	market_btn.pressed.connect(_open_black_market)
	feature5_bar.add_child(market_btn)
	
	# Right Side: Inventory & Stats
	inventory_panel = PanelContainer.new()
	inventory_panel.custom_minimum_size = Vector2(300, 0)
	inventory_panel.add_to_group("tutorial:inventory_panel") # onboarding spotlight anchor - see TutorialManager.gd
	hsplit.add_child(inventory_panel)
	
	var right_vbox = VBoxContainer.new()
	inventory_panel.add_child(right_vbox)
	
	stats_label = Label.new()
	stats_label.text = "=== COMPONENT INFO ===\nGrid: Mech Core\nPower: 0\n\n=== SIMULATION ===\nStep: 0\nActive Packets: 0\nTotal Energy: 0"
	right_vbox.add_child(stats_label)

	var sep = HSeparator.new()
	right_vbox.add_child(sep)

	scrap_label = Label.new()
	scrap_label.text = "Scrap: 0"
	scrap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scrap_label.modulate = Color(1.0, 0.8, 0.2)
	right_vbox.add_child(scrap_label)

	# Tiles / Components switch - a ButtonGroup makes the two toggle buttons
	# mutually exclusive automatically (no manual un-press bookkeeping).
	var view_switch_hbox = HBoxContainer.new()
	right_vbox.add_child(view_switch_hbox)

	var view_group = ButtonGroup.new()

	var tiles_tab_btn = Button.new()
	tiles_tab_btn.text = "Tiles"
	tiles_tab_btn.toggle_mode = true
	tiles_tab_btn.button_pressed = true
	tiles_tab_btn.button_group = view_group
	tiles_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tiles_tab_btn.pressed.connect(func(): _set_inventory_view("tiles"))
	view_switch_hbox.add_child(tiles_tab_btn)

	var components_tab_btn = Button.new()
	components_tab_btn.text = "Components"
	components_tab_btn.toggle_mode = true
	components_tab_btn.button_group = view_group
	components_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	components_tab_btn.pressed.connect(func(): _set_inventory_view("components"))
	view_switch_hbox.add_child(components_tab_btn)

	# --- Tiles panel ---------------------------------------------------------
	tile_panel = VBoxContainer.new()
	tile_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(tile_panel)

	var inv_label = Label.new()
	inv_label.text = "INVENTORY (R-click: scrap | M-click: upgrade)"
	inv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inv_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tile_panel.add_child(inv_label)

	var mass_sell_hbox = HBoxContainer.new()
	mass_sell_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	tile_panel.add_child(mass_sell_hbox)

	var sell_c_btn = Button.new()
	sell_c_btn.text = "Sell Common"
	sell_c_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell_c_btn.pressed.connect(_on_sell_all.bind(0))
	mass_sell_hbox.add_child(sell_c_btn)

	var sell_uc_btn = Button.new()
	sell_uc_btn.text = "Sell <= Uncommon"
	sell_uc_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell_uc_btn.pressed.connect(_on_sell_all.bind(1))
	mass_sell_hbox.add_child(sell_uc_btn)

	var sell_r_btn = Button.new()
	sell_r_btn.text = "Sell <= Rare"
	sell_r_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell_r_btn.pressed.connect(_on_sell_all.bind(2))
	mass_sell_hbox.add_child(sell_r_btn)

	var filter_hbox = HBoxContainer.new()
	tile_panel.add_child(filter_hbox)

	search_input = LineEdit.new()
	search_input.placeholder_text = "Search..."
	search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_input.text_changed.connect(func(_text): _refresh_inventory_ui())
	filter_hbox.add_child(search_input)

	rarity_filter = OptionButton.new()
	rarity_filter.add_item("All", 99)
	rarity_filter.add_item("Common", 0)
	rarity_filter.add_item("Uncommon", 1)
	rarity_filter.add_item("Rare", 2)
	rarity_filter.add_item("Legendary", 3)
	rarity_filter.item_selected.connect(func(_index): _refresh_inventory_ui())
	filter_hbox.add_child(rarity_filter)

	tile_sort = OptionButton.new()
	tile_sort.add_item("Sort: rarity", 0)
	tile_sort.add_item("Sort: type", 1)
	tile_sort.item_selected.connect(func(_index): _refresh_inventory_ui())
	filter_hbox.add_child(tile_sort)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tile_panel.add_child(scroll)

	inv_vbox = VBoxContainer.new()
	inv_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inv_vbox)

	# --- Components: mech-loadout diagram (moves to the MAIN area) ------------
	# In Components mode this is reparented into grid_panel as the primary
	# view (see _set_inventory_view) - it starts here in the sidebar, hidden,
	# just so it has a home while in Tiles mode.
	component_diagram_panel = VBoxContainer.new()
	component_diagram_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	component_diagram_panel.visible = false
	right_vbox.add_child(component_diagram_panel)

	var comp_inv_label = Label.new()
	comp_inv_label.text = "MECH LOADOUT (drag a spare part onto a slot to equip or swap it)"
	comp_inv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	comp_inv_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	component_diagram_panel.add_child(comp_inv_label)

	component_diagram = ComponentDiagramView.new()
	component_diagram.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	component_diagram.size_flags_vertical = Control.SIZE_EXPAND_FILL
	component_diagram.slot_pressed.connect(_on_diagram_slot_pressed)
	component_diagram_panel.add_child(component_diagram)

	# Lives in the sidebar, hidden until Components mode reparents
	# grid_renderer into it (see _set_inventory_view). Half the height it used
	# to be (Natalia: shrink the hex-grid preview and use the freed space for
	# the actual inventory list below it) - SIZE_FILL (not expand) so it
	# stays exactly this tall and doesn't compete with component_spare_panel
	# for the sidebar's remaining vertical space.
	side_grid_container = PanelContainer.new()
	side_grid_container.size_flags_vertical = Control.SIZE_FILL
	side_grid_container.custom_minimum_size = Vector2(0, 130)
	side_grid_container.visible = false
	right_vbox.add_child(side_grid_container)

	# --- Components: spare-parts inventory (moves to the SIDEBAR, below the
	# shrunk hex preview) --------------------------------------------------
	# This is the actual draggable tray Natalia bought Black Market parts
	# into - previously stacked directly under the (much taller) diagram in
	# this same sidebar column, where it regularly got squeezed to nothing or
	# scrolled below the fold. Splitting it out into its own guaranteed slot,
	# below a HALVED hex preview, means it always has real, visible room.
	component_spare_panel = VBoxContainer.new()
	component_spare_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	component_spare_panel.visible = false
	right_vbox.add_child(component_spare_panel)

	var comp_sort_hbox = HBoxContainer.new()
	component_spare_panel.add_child(comp_sort_hbox)

	var spare_lbl = Label.new()
	spare_lbl.text = "Spare parts (unequipped - drag onto a slot above)"
	spare_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	comp_sort_hbox.add_child(spare_lbl)

	component_sort = OptionButton.new()
	component_sort.add_item("Sort: rarity", 0)
	component_sort.add_item("Sort: type", 1)
	component_sort.item_selected.connect(func(_index): _refresh_component_inventory_list())
	comp_sort_hbox.add_child(component_sort)

	var spare_scroll = ScrollContainer.new()
	spare_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	component_spare_panel.add_child(spare_scroll)

	component_inventory_list = HFlowContainer.new()
	component_inventory_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spare_scroll.add_child(component_inventory_list)

	# Drag preview for spare-component cards - separate visual from the hex
	# drag_preview below since a whole component doesn't read well as a hex.
	component_drag_preview = PanelContainer.new()
	component_drag_preview.custom_minimum_size = Vector2(84, 40)
	component_drag_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var drag_style = StyleBoxFlat.new()
	drag_style.bg_color = Color(0.15, 0.15, 0.18, 0.9)
	drag_style.border_width_left = 2
	drag_style.border_width_right = 2
	drag_style.border_width_top = 2
	drag_style.border_width_bottom = 2
	drag_style.border_color = Color(1.0, 1.0, 1.0, 0.6)
	drag_style.corner_radius_top_left = 8
	drag_style.corner_radius_top_right = 8
	drag_style.corner_radius_bottom_left = 8
	drag_style.corner_radius_bottom_right = 8
	component_drag_preview.add_theme_stylebox_override("panel", drag_style)
	_component_drag_label = Label.new()
	_component_drag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_component_drag_label.add_theme_font_size_override("font_size", 11)
	component_drag_preview.add_child(_component_drag_label)
	component_drag_preview.hide()
	add_child(component_drag_preview)

	# Drag preview setup
	drag_preview = Polygon2D.new()
	var pts = PackedVector2Array()
	for i in range(6):
		var angle = deg_to_rad(60 * i - 30)
		pts.append(Vector2(cos(angle), sin(angle)) * 20)
	drag_preview.polygon = pts
	drag_preview.color = Color(1, 1, 1, 0.5)
	drag_preview.hide()
	add_child(drag_preview)
	
	# Tooltip
	tooltip_label = Label.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.9)
	style.corner_radius_top_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 10
	style.content_margin_top = 10
	tooltip_label.add_theme_stylebox_override("normal", style)
	tooltip_label.hide()
	add_child(tooltip_label)

# Refreshes both views of player_component_inventory (spare full arm/leg/
# torso/head/backpack assemblies): the diagram's per-slot "what's equipped"
# labels, and the draggable spare-parts tray below it. Piggybacks on
# _refresh_inventory_ui()'s call sites (upgrade, swap, extract modifier,
# black market purchase, dismantle, etc. all already call that) rather than
# needing its own separate hook everywhere.
func _refresh_component_inventory_list():
	if component_diagram:
		component_diagram.refresh(mech_components)

	if not component_inventory_list:
		return
	for c in component_inventory_list.get_children():
		c.queue_free()

	var main = get_parent()
	if not main or main.get("player_component_inventory") == null:
		return
	var comps = main.player_component_inventory

	# Defensive filter: previously a SINGLE malformed entry (e.g. a leftover
	# from an older save predating some earlier fix, or any future edge case
	# that slips a bad object into this array) could take down this entire
	# function the moment the sort comparator or the card-building loop below
	# touched its .rarity/.slot_type - which produces a tray with ZERO cards
	# and no placeholder text at all, even though comps itself (and any
	# perfectly good entries alongside the bad one, including a purchase that
	# just landed) was fine. That failure mode is indistinguishable from "my
	# purchase just didn't show up" from the player's side, which is exactly
	# what Natalia kept reporting even after two rounds of pure layout fixes.
	# Filtering up front means one bad apple can never hide everyone else's
	# entries, and the warning below at least gets it into the log instead of
	# vanishing silently.
	var valid_comps = []
	var dropped = 0
	for c in comps:
		if is_instance_valid(c) and c.get("rarity") != null and c.get("slot_type") != null:
			valid_comps.append(c)
		else:
			dropped += 1
	if dropped > 0:
		push_warning("GarageMenu: %d malformed player_component_inventory entries hidden from Spare Parts tray" % dropped)

	if valid_comps.is_empty():
		var empty_lbl = Label.new()
		if comps.is_empty():
			empty_lbl.text = "(none yet - boss kills, rare salvage drops, or the Black Market)"
		else:
			empty_lbl.text = "(%d entries couldn't be displayed - corrupted data, see log)" % dropped
		empty_lbl.modulate = Color(0.6, 0.6, 0.6)
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		component_inventory_list.add_child(empty_lbl)
		return

	var sorted_comps = valid_comps.duplicate()
	var sort_by_type = component_sort != null and component_sort.get_selected_id() == 1
	if sort_by_type:
		sorted_comps.sort_custom(func(a, b):
			if a.slot_type == b.slot_type:
				return a.rarity > b.rarity
			return a.slot_type < b.slot_type
		)
	else:
		sorted_comps.sort_custom(func(a, b):
			if a.rarity == b.rarity:
				return a.slot_type < b.slot_type
			return a.rarity > b.rarity
		)

	var rarity_names = ["Common", "Uncommon", "Rare", "Legendary", "Mythic"]
	var rarity_colors = [Color(0.5, 0.5, 0.5), Color(0.2, 0.7, 0.3), Color(0.2, 0.4, 0.8), Color(0.8, 0.5, 0.1), Color(0.1, 0.8, 0.8)]
	for comp in sorted_comps:
		var rarity_name = rarity_names[comp.rarity] if comp.rarity < rarity_names.size() else "?"
		var rarity_color = rarity_colors[comp.rarity] if comp.rarity < rarity_colors.size() else Color.WHITE

		var card = PanelContainer.new()
		card.custom_minimum_size = Vector2(88, 54)
		var style = StyleBoxFlat.new()
		style.bg_color = rarity_color * 0.45
		style.bg_color.a = 1.0
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.border_color = rarity_color
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		card.add_theme_stylebox_override("panel", style)
		if comp.rarity == 4:
			card.material = _get_mythic_shimmer_mat()

		var vbox = VBoxContainer.new()
		card.add_child(vbox)

		var slot_lbl = Label.new()
		slot_lbl.text = _slot_display_name(comp.slot_type)
		slot_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_lbl.add_theme_font_size_override("font_size", 11)
		slot_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(slot_lbl)

		var rarity_lbl = Label.new()
		var rarity_txt = rarity_name
		if comp.get("infusion_level", 0) > 0:
			rarity_txt += " Lv%d" % comp.infusion_level
		rarity_lbl.text = rarity_txt
		rarity_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rarity_lbl.add_theme_font_size_override("font_size", 10)
		vbox.add_child(rarity_lbl)

		card.tooltip_text = "%s - drag onto its slot on the diagram above to equip/swap" % comp.component_name
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.gui_input.connect(_on_component_item_gui_input.bind(comp))
		component_inventory_list.add_child(card)

# Mirrors _on_inventory_item_gui_input's hex-tile drag-start pattern below,
# just for spare-component cards instead of tiles.
func _on_component_item_gui_input(event: InputEvent, comp):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		dragged_component = comp
		if _component_drag_label:
			_component_drag_label.text = "%s\n%s" % [_slot_display_name(comp.slot_type), comp.component_name]
		component_drag_preview.show()
		component_drag_preview.global_position = get_viewport().get_mouse_position()

func _drop_component(pos: Vector2):
	var comp = dragged_component
	dragged_component = null
	component_drag_preview.hide()
	if component_diagram:
		component_diagram.set_highlight(-1)
	if not comp:
		return

	if not component_diagram:
		return
	var target_slot = component_diagram.get_slot_at_point(pos)
	if target_slot == -1:
		return # dropped outside any slot box - stays in the spare pool, no-op

	if target_slot != comp.slot_type:
		_show_warning("%s doesn't fit the %s slot" % [comp.component_name, _slot_display_name(target_slot)])
		return

	var main = get_parent()
	if not main or main.get("player_component_inventory") == null or main.get("player") == null:
		return

	main.player_component_inventory.erase(comp)

	var main_player = main.player
	var old = main_player.components.get(target_slot, null)
	if old:
		main_player.remove_child(old)
		main_player.components.erase(target_slot)
		main.player_component_inventory.append(old)

	main_player.equip_component(comp)
	_refresh_component_ui()
	_refresh_inventory_ui()
	_show_scrap_float("Equipped %s" % comp.component_name, Color(0.3, 0.9, 1.0))

func _refresh_inventory_ui():
	_refresh_component_inventory_list()

	for c in inv_vbox.get_children():
		c.queue_free()

	if scrap_label:
		var main = get_parent()
		if main and main.get("player_scrap") != null:
			scrap_label.text = "Scrap: " + str(main.player_scrap)

		
	var search_text = ""
	if search_input: search_text = search_input.text.to_lower()
	var filter_rarity = 99
	if rarity_filter: filter_rarity = rarity_filter.get_selected_id()
	
	var grouped_inventory = {}
	for tile in inventory:
		var key = tile.tile_type + "_" + str(tile.rarity)
		if not grouped_inventory.has(key):
			grouped_inventory[key] = []
		grouped_inventory[key].append(tile)

	var sorted_keys = grouped_inventory.keys()
	var sort_by_type = tile_sort != null and tile_sort.get_selected_id() == 1
	if sort_by_type:
		sorted_keys.sort_custom(func(a, b):
			var ta = grouped_inventory[a][0]
			var tb = grouped_inventory[b][0]
			if ta.tile_type == tb.tile_type:
				return ta.rarity > tb.rarity
			return ta.tile_type < tb.tile_type
		)
	else:
		sorted_keys.sort_custom(func(a, b):
			var ta = grouped_inventory[a][0]
			var tb = grouped_inventory[b][0]
			if ta.rarity == tb.rarity:
				return ta.tile_type < tb.tile_type
			return ta.rarity > tb.rarity
		)

	for key in sorted_keys:
		var stack = grouped_inventory[key]
		var tile = stack[0]
		var count = stack.size()
		
		if search_text != "" and not tile.tile_type.to_lower().contains(search_text):
			continue
		if filter_rarity != 99 and tile.rarity != filter_rarity:
			continue
			
		var btn = Button.new()
		var mult = 1.0 + (tile.rarity * 0.15)
		var rarity_name = ["Common", "Uncommon", "Rare", "Legendary", "Mythic"][tile.rarity]
		var rarity_colors = [Color(0.5, 0.5, 0.5), Color(0.2, 0.7, 0.3), Color(0.2, 0.4, 0.8), Color(0.8, 0.5, 0.1), Color(0.1, 0.8, 0.8)]
		
		var style = StyleBoxFlat.new()
		style.bg_color = rarity_colors[tile.rarity] * 0.5 # Darkened background
		style.border_width_bottom = 2
		style.border_color = rarity_colors[tile.rarity]
		btn.add_theme_stylebox_override("normal", style)
		
		if tile.rarity == 4:
			btn.material = _get_mythic_shimmer_mat()
		
		btn.text = tile.tile_type + "\n" + rarity_name + " (x" + str(snapped(mult, 0.01)) + ")"
		if count > 1:
			btn.text += " [%d]" % count
		btn.custom_minimum_size = Vector2(0, 50)
		btn.gui_input.connect(_on_inventory_item_gui_input.bind(tile))
		inv_vbox.add_child(btn)


# NOTE: ui_cancel/Esc is NOT handled here anymore - it used to call
# main._close_garage() directly (silently deploying you to battle), then a
# later fix tried intercepting it here to open a Pause Menu instead. That
# still didn't reliably work ("when dead still cannot esc") because it
# depended on this _input() firing in the right order relative to Main's
# separate _unhandled_input handler. Esc-to-pause is now centralized in
# GlobalPauseHandler.gd (an always-processing node added once in
# Main._ready()), which works regardless of pause state or dispatch order.
# "Deploy to Battlefield ->" remains the explicit way to actually leave.
func _input(event):

	if event is InputEventMouseMotion:
		if dragged_tile:
			drag_preview.global_position = event.global_position
		if dragged_component:
			component_drag_preview.global_position = event.global_position
			if component_diagram:
				component_diagram.set_highlight(component_diagram.get_slot_at_point(event.global_position))

	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if dragged_tile:
			_drop_tile(event.global_position)
		if dragged_component:
			_drop_component(event.global_position)

# Polling (not motion-event-driven) on purpose: if the cursor goes
# perfectly still, no InputEventMouseMotion fires at all, so a "have you
# been stationary for N seconds" check needs a per-frame timer instead of
# only re-checking whenever the mouse happens to twitch.
func _process(_delta):
	if not dragged_tile:
		return

	var pos = get_viewport().get_mouse_position()
	if not grid_renderer.get_global_rect().has_point(pos):
		drag_hover_hex = null
		if not fill_mode:
			grid_renderer.fill_preview_hexes = []
			grid_renderer.queue_redraw()
		return

	var local_pos = grid_renderer.get_global_transform().affine_inverse() * pos
	var hex = grid_renderer._pixel_to_hex(local_pos)

	if drag_hover_hex == null or not hex.equals(drag_hover_hex):
		drag_hover_hex = hex
		drag_hover_since = Time.get_ticks_msec() / 1000.0
	elif not fill_mode:
		var paused_for = Time.get_ticks_msec() / 1000.0 - drag_hover_since
		if paused_for >= FILL_PAUSE_THRESHOLD:
			fill_mode = true
			fill_origin_hex = hex

	if fill_mode:
		var line = HexCoord.hex_line(fill_origin_hex, hex)
		grid_renderer.fill_preview_hexes = line
		grid_renderer.queue_redraw()

func _on_inventory_item_gui_input(event: InputEvent, tile: HexTile):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragged_tile = tile
			drag_preview.show()
			drag_preview.global_position = get_viewport().get_mouse_position()
			tooltip_label.hide()
			# Fresh drag - reset any leftover fill-mode state from a
			# previous drag/drop cycle.
			drag_hover_hex = null
			fill_mode = false
			fill_origin_hex = null
			grid_renderer.fill_preview_hexes = []
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_scrap_tile(tile)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_upgrade_tile(tile)

# Single source of truth for what a tile is worth - this exact
# rarity->value ladder was previously copy-pasted in three places
# (_scrap_tile, _on_sell_all, and now upgrade costs derive from it too).
static func tile_scrap_value(tile: HexTile) -> int:
	match tile.rarity:
		1: return 25
		2: return 75
		3: return 250
		4: return 1000
		_: return 10

const MAX_TILE_LEVEL = 10

# Upgrading costs roughly double the tile's scrap value per current level -
# so leveling your favorite tile is always pricier than scrapping chaff,
# and high-rarity upgrades are a serious investment (Mythic L1->2 = 2000).
static func tile_upgrade_cost(tile: HexTile) -> int:
	return tile_scrap_value(tile) * 2 * tile.level

func _show_scrap_float(text: String, color: Color = Color(1.0, 0.8, 0.2)):
	var float_lbl = Label.new()
	float_lbl.text = text
	float_lbl.modulate = color
	float_lbl.global_position = get_viewport().get_mouse_position() - Vector2(20, 20)
	add_child(float_lbl)
	var tw = create_tween()
	tw.tween_property(float_lbl, "global_position:y", float_lbl.global_position.y - 50, 1.0)
	tw.parallel().tween_property(float_lbl, "modulate:a", 0.0, 1.0)
	tw.tween_callback(float_lbl.queue_free)

func _scrap_tile(tile: HexTile):
	var main = get_parent()
	if main and main.get("player_scrap") != null:
		var scrap_value = tile_scrap_value(tile)
		main.player_scrap += scrap_value
		inventory.erase(tile)
		_refresh_inventory_ui()
		_show_scrap_float("+" + str(scrap_value) + " Scrap")

# Middle-click: spend scrap to level a tile up (+10% power per level via
# the shared _get_power_multiplier() curve every tile type already uses).
func _upgrade_tile(tile: HexTile):
	var main = get_parent()
	if not main or main.get("player_scrap") == null:
		return
	if tile.level >= MAX_TILE_LEVEL:
		_show_scrap_float("Max level!", Color(0.9, 0.4, 0.3))
		return
	var cost = tile_upgrade_cost(tile)
	if main.player_scrap < cost:
		_show_scrap_float("Need " + str(cost) + " scrap", Color(0.9, 0.4, 0.3))
		return
	main.player_scrap -= cost
	tile.level += 1
	_refresh_inventory_ui()
	_show_scrap_float("Lv." + str(tile.level) + "  (-" + str(cost) + " scrap)", Color(0.4, 1.0, 0.5))

func _on_repair_all():
	var main = get_parent()
	if not main or main.get("player") == null or main.get("player_scrap") == null:
		return
	var mech = main.player

	var missing_hp = max(0.0, mech.max_hp - mech.hp)
	var damaged_tiles = 0
	var disabled_tiles = 0
	var destroyed_tiles = 0
	for comp in mech.components.values():
		for tile in comp.hex_grid.get_all_tiles():
			if "power_lost" in tile and tile.power_lost:
				destroyed_tiles += 1
			elif tile.is_disabled:
				disabled_tiles += 1
			elif tile.hp < tile.max_hp:
				damaged_tiles += 1

	# Destroyed (power_lost) tiles - the "grave enough hit" outcome from
	# Mech._roll_component_disable - cost more than an ordinary knocked-out
	# tile since they'd otherwise never come back on their own.
	var cost = int(ceil(missing_hp / 2.0)) + disabled_tiles * 25 + destroyed_tiles * 100
	if cost <= 0 and damaged_tiles == 0:
		_show_scrap_float("Nothing to repair", Color(0.7, 0.7, 0.7))
		return
	cost = max(cost, 1)
	if main.player_scrap < cost:
		_show_scrap_float("Need " + str(cost) + " scrap", Color(0.9, 0.4, 0.3))
		return

	main.player_scrap -= cost
	mech.hp = mech.max_hp
	for comp in mech.components.values():
		for tile in comp.hex_grid.get_all_tiles():
			tile.hp = tile.max_hp
			tile.is_disabled = false
			tile.disable_timer = 0.0
			tile.times_disabled = 0
			if "power_lost" in tile:
				tile.power_lost = false
	_refresh_inventory_ui() # updates the scrap label
	_show_scrap_float("Fully repaired  (-" + str(cost) + " scrap)", Color(0.4, 1.0, 0.5))

const INFUSE_COST = 100
const INFUSE_XP = 100

func _on_infuse_part():
	var main = get_parent()
	if not main or main.get("player_scrap") == null or not active_component:
		return
	if main.player_scrap < INFUSE_COST:
		_show_scrap_float("Need " + str(INFUSE_COST) + " scrap", Color(0.9, 0.4, 0.3))
		return
	main.player_scrap -= INFUSE_COST
	var before_level = active_component.infusion_level
	active_component.add_infusion_xp(INFUSE_XP)
	_refresh_inventory_ui() # updates the scrap label
	if active_component.infusion_level > before_level:
		_show_scrap_float("INFUSION LEVEL UP! (Lv." + str(active_component.infusion_level) + ")", Color(0.3, 0.9, 1.0))
	else:
		_show_scrap_float("+%d XP (%d/%d)" % [INFUSE_XP, active_component.infusion_xp, 500 + active_component.infusion_level * 500], Color(0.4, 1.0, 0.5))

# --- Feature 5: manual-hex upgrades ----------------------------------------

# Hexes the player still has to place after an upgrade (consumed by
# GarageGridRenderer's expansion-click mode).
var pending_expansion_hexes: int = 0
var chip_count_label: Label = null

const UPGRADE_COSTS = [0, 500, 1500, 4000, 10000] # cost to REACH rarity index

func _on_upgrade_part():
	var main = get_parent()
	if not active_component or not main or main.get("player_scrap") == null:
		return
	if active_component.rarity >= HexTile.Rarity.MYTHIC:
		_show_scrap_float("Already Mythic!", Color(0.7, 0.7, 0.7))
		return
	var cost = UPGRADE_COSTS[active_component.rarity + 1]
	if main.player_scrap < cost:
		_show_scrap_float("Need " + str(cost) + " scrap", Color(0.9, 0.4, 0.3))
		return
	# Consume one same-slot salvage component - drops feed the upgrade loop
	var salvage_idx = -1
	if main.get("player_component_inventory") != null:
		for i in range(main.player_component_inventory.size()):
			var c = main.player_component_inventory[i]
			if c != active_component and c.slot_type == active_component.slot_type:
				salvage_idx = i
				break
	if salvage_idx < 0:
		_show_scrap_float("Need a spare %s to sacrifice" % _slot_display_name(active_component.slot_type), Color(0.9, 0.4, 0.3))
		return

	main.player_scrap -= cost
	main.player_component_inventory.remove_at(salvage_idx)
	var granted = active_component.upgrade_rarity()
	pending_expansion_hexes += granted
	_mark_player_grid_dirty()
	_refresh_component_ui()
	_refresh_inventory_ui()
	_show_scrap_float("UPGRADED! Click %d pulsing cells to grow the part" % granted, Color(0.3, 0.9, 1.0))
	grid_renderer.queue_redraw()

# --- Feature 5: modifier extraction + chip infusion --------------------------

func _update_chip_label():
	var main = get_parent()
	if chip_count_label and main and main.get("player_modifier_chips") != null:
		var txt = "Chips: %d" % main.player_modifier_chips.size()
		if main.player_modifier_chips.size() > 0:
			var next = main.player_modifier_chips[0]
			txt += "  (next: %s +%d%%)" % [str(next["stat"]), int(round((float(next["value"]) - 1.0) * 100.0))]
		chip_count_label.text = txt

func _on_extract_modifier():
	var main = get_parent()
	if not main or main.get("player_modifier_chips") == null or main.get("player_component_inventory") == null:
		return
	# First spare component carrying a stat modifier gets sacrificed
	for i in range(main.player_component_inventory.size()):
		var c = main.player_component_inventory[i]
		var mods = c.get("stat_modifiers")
		if mods != null and not mods.is_empty():
			var stat = mods.keys()[0]
			main.player_modifier_chips.append({"stat": stat, "value": float(mods[stat])})
			main.player_component_inventory.remove_at(i)
			_update_chip_label()
			_show_scrap_float("Extracted %s chip (part destroyed)" % str(stat), Color(0.3, 0.9, 1.0))
			return
	_show_scrap_float("No spare part with a modifier to extract", Color(0.9, 0.4, 0.3))

func _on_infuse_chip():
	var main = get_parent()
	if not active_component or not main or main.get("player_modifier_chips") == null:
		return
	if main.player_modifier_chips.is_empty():
		_show_scrap_float("No chips - extract one first", Color(0.9, 0.4, 0.3))
		return
	var chip = main.player_modifier_chips.pop_front()
	var stat = str(chip["stat"])
	var bonus = float(chip["value"]) - 1.0
	var current = float(active_component.stat_modifiers.get(stat, 1.0))
	# Chips stack, capped at +50% per stat per component ("constants later")
	active_component.stat_modifiers[stat] = min(1.5, current + bonus)
	_update_chip_label()
	_mark_player_grid_dirty()
	_show_scrap_float("%s now +%d%% on this part" % [stat, int(round((active_component.stat_modifiers[stat] - 1.0) * 100.0))], Color(0.4, 1.0, 0.5))

# --- Feature 5: Black Market -------------------------------------------------
# Stock is deterministic per 10-minute real-time window (seeded from unix
# time / 600), so reopening the popup shows the same rotation until the
# window rolls over. Purchases are remembered per window.

const MARKET_CYCLE_SECONDS = 600
const MARKET_FORBIDDABLE = ["Amplifier", "Accumulator", "Splitter", "Catalyst", "Shield Generator"]
var _market_sold: Dictionary = {}

# Shared human-readable slot names - used by the Black Market listing, the
# spare-components list, and the Swap Component warning/popup, so a purchased
# part is identifiable as "Right Arm" everywhere instead of showing up as a
# raw enum int (which is what "Black Market 3" used to mean - a real bug that
# made purchased parts basically unrecognizable in the spare-parts list).
const SLOT_DISPLAY_NAMES = {
	HexTile.BodySlot.TORSO: "Torso",
	HexTile.BodySlot.ARM_L: "Left Arm",
	HexTile.BodySlot.ARM_R: "Right Arm",
	HexTile.BodySlot.LEG_L: "Left Leg",
	HexTile.BodySlot.LEG_R: "Right Leg",
	HexTile.BodySlot.HEAD: "Head",
	HexTile.BodySlot.BACKPACK: "Backpack",
	HexTile.BodySlot.DRONE: "Drone",
}

static func _slot_display_name(slot) -> String:
	return SLOT_DISPLAY_NAMES.get(slot, "Slot %s" % str(slot))

func _open_black_market():
	var main = get_parent()
	if not main or main.get("player_scrap") == null:
		return
	if main.has_method("show_dialogue"):
		var dm = load("res://scripts/core/DialogueManager.gd").new()
		dm._ready()
		main.show_dialogue("Shopkeeper", dm.get_black_market_quip(), Color(1.0, 0.5, 0.9), 6.0)
	var cycle = int(Time.get_unix_time_from_system()) / MARKET_CYCLE_SECONDS
	var rng = RandomNumberGenerator.new()
	rng.seed = cycle

	var popup = PopupPanel.new()
	var vbox = VBoxContainer.new()
	popup.add_child(vbox)

	var title = Label.new()
	title.text = "BLACK MARKET - stock rotates in %d s" % (MARKET_CYCLE_SECONDS - int(Time.get_unix_time_from_system()) % MARKET_CYCLE_SECONDS)
	title.modulate = Color(1.0, 0.5, 0.9)
	vbox.add_child(title)

	var slot_names = SLOT_DISPLAY_NAMES
	var rarity_names = ["Common", "Uncommon", "Rare", "Legendary", "Mythic"]
	var prices = [0, 0, 1200, 3200, 8000]

	# Market never rolls Backpack - keep that exclusion even though the
	# shared SLOT_DISPLAY_NAMES dict (used for display everywhere else) does
	# include it.
	var market_slots = [HexTile.BodySlot.TORSO, HexTile.BodySlot.ARM_L, HexTile.BodySlot.ARM_R, HexTile.BodySlot.LEG_L, HexTile.BodySlot.LEG_R, HexTile.BodySlot.HEAD]

	for i in range(3):
		var roll = rng.randf()
		var rarity = HexTile.Rarity.RARE
		if roll > 0.85: rarity = HexTile.Rarity.MYTHIC
		elif roll > 0.5: rarity = HexTile.Rarity.LEGENDARY
		var slots = market_slots
		var slot = slots[rng.randi() % slots.size()]
		var extra_hexes = 4 + rarity
		var forb_a = MARKET_FORBIDDABLE[rng.randi() % MARKET_FORBIDDABLE.size()]
		var forb_b = MARKET_FORBIDDABLE[rng.randi() % MARKET_FORBIDDABLE.size()]
		var price = prices[rarity]
		var sold_key = "%d_%d" % [cycle, i]

		var offer_btn = Button.new()
		var forb_txt = forb_a if forb_a == forb_b else forb_a + " & " + forb_b
		offer_btn.text = "%s %s  |  +%d extra hexes  |  FORBIDS: %s  |  %d scrap" % [rarity_names[rarity], slot_names[slot], extra_hexes, forb_txt, price]
		offer_btn.disabled = _market_sold.has(sold_key)
		if offer_btn.disabled:
			offer_btn.text += "  [SOLD]"

		# Capture loop state for the purchase lambda
		var offer = {"rarity": rarity, "slot": slot, "slot_name": slot_names[slot], "extra": extra_hexes, "forbidden": [forb_a, forb_b] if forb_a != forb_b else [forb_a], "price": price, "key": sold_key, "seed": cycle * 100 + i}
		offer_btn.pressed.connect(func():
			if main.player_scrap < offer.price:
				_show_scrap_float("Need " + str(offer.price) + " scrap", Color(0.9, 0.4, 0.3))
				return
			# Build FIRST, spend/mark-sold only after a successful build.
			# Previously scrap was deducted and _market_sold was flagged
			# BEFORE _build_market_component() ran - so if that call ever
			# failed partway through (a bad roll producing something the
			# procedural generator choked on), the price was already paid and
			# the offer permanently flagged [SOLD] on every future reopen of
			# this popup, with nothing ever landing in the spare-parts tray to
			# show for it. That silent-loss ordering is exactly what could
			# make "I bought it and it didn't show up" happen even though
			# nothing else about the purchase flow looked wrong. Now a failed
			# build costs nothing and leaves the offer purchasable again.
			var built = _build_market_component(offer)
			if built == null:
				_show_scrap_float("Purchase failed - no scrap taken, try again", Color(0.9, 0.4, 0.3))
				return
			main.player_scrap -= offer.price
			_market_sold[offer.key] = true
			main.player_component_inventory.append(built)
			_refresh_inventory_ui()
			offer_btn.disabled = true
			offer_btn.text += "  [SOLD]"
			_show_scrap_float("Deal done. No refunds.", Color(1.0, 0.5, 0.9))
		)
		vbox.add_child(offer_btn)

	var warning = Label.new()
	warning.text = "Experimental hardware. Oversized grids, hard restrictions, no refunds."
	warning.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(warning)

	add_child(popup)
	popup.popup_centered(Vector2(640, 220))
	popup.popup_hide.connect(func(): popup.queue_free())

func _build_market_component(offer: Dictionary):
	var comp = ComponentEquipment.new(offer.slot, offer.rarity)
	# Was "Black Market " + str(offer.slot) - since offer.slot is a raw enum
	# int, that literally showed up as e.g. "Black Market 3" in the spare-parts
	# list and Swap Component popup, making a purchased part unrecognizable
	# (this looked exactly like "the Black Market isn't working" even though
	# the purchase itself succeeded and was equip-compatible).
	comp.component_name = "Black Market " + offer.get("slot_name", _slot_display_name(offer.slot))
	comp.forbidden_tile_types = offer.forbidden.duplicate()
	comp.generate_procedural_shape()

	# Oversized: bolt on the extra hexes procedurally (deterministic per offer)
	var rng = RandomNumberGenerator.new()
	rng.seed = offer.seed
	var added = 0
	var guard = 0
	while added < offer.extra and guard < 200:
		guard += 1
		if comp.valid_hexes.is_empty():
			break
		var base = comp.valid_hexes[rng.randi() % comp.valid_hexes.size()]
		var n = HexCoord.new(base.q, base.r).neighbor(rng.randi() % 6)
		if comp.add_expansion_hex(n):
			added += 1

	# Standard entry point so energy can actually route in
	if comp.slot_type != HexTile.BodySlot.TORSO and not comp.hex_grid.has_tile(HexCoord.new(0, 0)):
		var intake = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.NONE, true)
		intake.tile_type = "Energy Intake"
		intake.body_slot = comp.slot_type
		comp.hex_grid.add_tile(HexCoord.new(0, 0), intake)
		comp.fixed_sinks.append(HexCoord.new(0, 0))
	return comp

func _on_sell_all(max_rarity: int):
	var main = get_parent()
	if not main or main.get("player_scrap") == null: return
	var to_remove = []
	var total_scrap = 0
	for tile in inventory:
		if tile.rarity <= max_rarity:
			to_remove.append(tile)
			total_scrap += tile_scrap_value(tile)
			
	for tile in to_remove:
		inventory.erase(tile)
		
	if total_scrap > 0:
		main.player_scrap += total_scrap
		_refresh_inventory_ui()
		var float_lbl = Label.new()
		float_lbl.text = "+" + str(total_scrap) + " Scrap"
		float_lbl.modulate = Color(1.0, 0.8, 0.2)
		float_lbl.global_position = get_viewport().get_mouse_position() - Vector2(20, 20)
		add_child(float_lbl)
		var tw = create_tween()
		tw.tween_property(float_lbl, "global_position:y", float_lbl.global_position.y - 50, 1.0)
		tw.parallel().tween_property(float_lbl, "modulate:a", 0.0, 1.0)
		tw.tween_callback(float_lbl.queue_free)

func _on_inventory_item_down(tile: HexTile):
	pass # Deprecated in favor of gui_input


func _drop_tile(pos: Vector2):
	if fill_mode and grid_renderer.fill_preview_hexes.size() > 1:
		_drop_fill_line()
	elif grid_renderer.get_global_rect().has_point(pos):
		var local_pos = grid_renderer.get_global_transform().affine_inverse() * pos
		var hex = grid_renderer._pixel_to_hex(local_pos)

		# Check if valid in current component shape
		if active_component and not active_component.can_place_tile(hex):
			print("Cannot place tile outside component bounds or on fixed sinks!")
		elif active_component and dragged_tile and active_component.forbidden_tile_types.has(dragged_tile.tile_type):
			# Black Market drawback: this component refuses certain tile types
			_show_scrap_float("FORBIDDEN: this part rejects %s tiles" % dragged_tile.tile_type, Color(1.0, 0.4, 0.4))
		elif hex.q == 0 and hex.r == 0 and active_component.slot_type == HexTile.BodySlot.TORSO:
			print("Cannot override Torso Core!")
			# Return the dragged tile to inventory
			inventory.append(dragged_tile)
			_refresh_inventory_ui()
		elif grid_renderer.hex_grid:
			if not grid_renderer.hex_grid.has_tile(hex):
				grid_renderer.hex_grid.add_tile(hex, dragged_tile)
				inventory.erase(dragged_tile)
				_refresh_inventory_ui()
				grid_renderer.queue_redraw()
				_tutorial_notify("tile_placed:any")
				_tutorial_notify("tile_placed:" + dragged_tile.tile_type)
			else:
				print("Slot occupied!")

	dragged_tile = null
	drag_preview.hide()
	fill_mode = false
	fill_origin_hex = null
	drag_hover_hex = null
	grid_renderer.fill_preview_hexes = []

# Places dragged_tile at the first valid cell in the paused-then-dragged
# line, then keeps placing additional matching copies (same tile_type +
# rarity) pulled from inventory at each subsequent valid, empty cell along
# the line - stopping early if inventory runs out. Skips the Torso Core
# cell and anything outside the component's shape, same protections as a
# normal single-tile drop.
func _drop_fill_line():
	if not grid_renderer.hex_grid or not dragged_tile:
		return

	var placed_first = false
	for hex in grid_renderer.fill_preview_hexes:
		if active_component and not active_component.can_place_tile(hex):
			continue
		if active_component and active_component.slot_type == HexTile.BodySlot.TORSO and hex.q == 0 and hex.r == 0:
			continue
		if grid_renderer.hex_grid.has_tile(hex):
			continue

		if not placed_first:
			grid_renderer.hex_grid.add_tile(hex, dragged_tile)
			inventory.erase(dragged_tile)
			placed_first = true
		else:
			var match_idx = _find_matching_inventory_index(dragged_tile)
			if match_idx < 0:
				break # Out of matching copies - stop filling
			var next_tile = inventory[match_idx]
			inventory.remove_at(match_idx)
			grid_renderer.hex_grid.add_tile(hex, next_tile)

	if not placed_first:
		# Even the origin cell was blocked/invalid - give the tile back
		inventory.append(dragged_tile)
	else:
		_tutorial_notify("tile_placed:any")
		_tutorial_notify("tile_placed:" + dragged_tile.tile_type)

	_refresh_inventory_ui()
	grid_renderer.queue_redraw()

func _find_matching_inventory_index(reference: HexTile) -> int:
	for i in range(inventory.size()):
		var t = inventory[i]
		if t.tile_type == reference.tile_type and t.rarity == reference.rarity:
			return i
	return -1

func _add_to_inventory(tile: HexTile):
	inventory.append(tile)
	_refresh_inventory_ui()

func _on_tooltip_requested(tile: HexTile, screen_pos: Vector2):
	if dragged_tile: return
	tooltip_label.show()
	tooltip_label.global_position = screen_pos + Vector2(15, 15)
	var mult = 1.0 + (tile.rarity * 0.15)
	var rarity_name = ["Common", "Uncommon", "Rare", "Legendary", "Mythic"][tile.rarity]
	var text = "[ %s ] %s\nPower Multiplier: x%s" % [rarity_name, tile.tile_type, str(snapped(mult, 0.01))]
	if "sync_adjustment" in tile and tile.sync_adjustment != 0:
		text += "\nSync Shift: " + ("+" if tile.sync_adjustment > 0 else "") + str(tile.sync_adjustment)
	if "amplification" in tile:
		text += "\nAmplification: " + str(tile.amplification)
	if "split_count" in tile:
		text += "\nSplits: " + str(tile.split_count)
	tooltip_label.text = text

func _on_tooltip_cleared():
	tooltip_label.text = ""
	tooltip_label.visible = false

func _on_tile_clicked(tile: HexTile):
	if tile.tile_type == "Core Reactor":
		var popup = PopupPanel.new()
		var vbox = VBoxContainer.new()
		popup.add_child(vbox)
		
		var label = Label.new()
		label.text = "Configure Reactor Faces (Max %d)" % tile.get_max_faces()
		vbox.add_child(label)
		
		var directions = ["East", "South-East", "South-West", "West", "North-West", "North-East"]
		
		for i in range(6):
			var btn = CheckButton.new()
			btn.text = "Face " + str(i) + " (" + directions[i] + ")"
			btn.button_pressed = tile.active_faces.has(i)
			
			btn.toggled.connect(func(pressed):
				tile.toggle_face(i)
				grid_renderer.queue_redraw()
				for j in range(6):
					var child_btn = vbox.get_child(j + 1)
					if child_btn is CheckButton:
						child_btn.set_block_signals(true)
						child_btn.button_pressed = tile.active_faces.has(j)
						child_btn.set_block_signals(false)
			)
			vbox.add_child(btn)

		# MYTHIC Core: shift native generation to a single element on every
		# face at once, bypassing the need for early Catalysts.
		if tile.rarity == HexTile.Rarity.MYTHIC:
			var syn_names = ["RAW", "FIRE", "ICE", "LIGHTNING", "VORTEX", "POISON", "EXPLOSION", "KINETIC", "PIERCE", "VAMPIRIC"]
			var native_state = [int(tile.face_outputs.get(0, 0))]
			var native_btn = Button.new()
			native_btn.text = "MYTHIC native element: %s (click to cycle all faces)" % syn_names[native_state[0] % 10]
			native_btn.pressed.connect(func():
				native_state[0] = (native_state[0] + 1) % 10
				for f in range(6):
					tile.set_face_output(f, native_state[0])
				native_btn.text = "MYTHIC native element: %s (click to cycle all faces)" % syn_names[native_state[0]]
				_mark_player_grid_dirty()
				grid_renderer.queue_redraw()
			)
			vbox.add_child(native_btn)

		add_child(popup)
		popup.popup_centered(Vector2(250, 300))
		popup.popup_hide.connect(func(): popup.queue_free())

	elif tile.tile_type == "Splitter" or tile.tile_type == "Accessory Return":
		var popup = PopupPanel.new()
		var vbox = VBoxContainer.new()
		popup.add_child(vbox)
		
		var label = Label.new()
		label.text = "Configure Outputs (Max %d)" % tile.get_max_faces()
		vbox.add_child(label)
		
		var directions = ["East", "South-East", "South-West", "West", "North-West", "North-East"]
		
		for i in range(6):
			var btn = CheckButton.new()
			btn.text = "Face " + str(i) + " (" + directions[i] + ")"
			btn.button_pressed = tile.active_faces.has(i)
			
			btn.toggled.connect(func(pressed):
				tile.toggle_output(i)
				grid_renderer.queue_redraw()
				for j in range(6):
					var child_btn = vbox.get_child(j + 1)
					if child_btn is CheckButton:
						child_btn.set_block_signals(true)
						child_btn.button_pressed = tile.active_faces.has(j)
						child_btn.set_block_signals(false)
			)
			vbox.add_child(btn)
			
		add_child(popup)
		popup.popup_centered(Vector2(250, 300))
		popup.popup_hide.connect(func(): popup.queue_free())
		
	elif tile.tile_type == "Reflector":
		var popup = PopupPanel.new()
		var vbox = VBoxContainer.new()
		popup.add_child(vbox)
		
		var label = Label.new()
		label.text = "Configure Reflector Rotation"
		vbox.add_child(label)
		
		var btn = Button.new()
		btn.text = "Rotate 60 deg (Current: %d)" % tile.rotation_steps
		btn.pressed.connect(func():
			tile.rotation_steps = (tile.rotation_steps % 5) + 1
			btn.text = "Rotate 60 deg (Current: %d)" % tile.rotation_steps
			grid_renderer.queue_redraw()
		)
		vbox.add_child(btn)
		
		add_child(popup)
		popup.popup_centered(Vector2(250, 100))
		popup.popup_hide.connect(func(): popup.queue_free())
	
	elif tile.tile_type == "Elemental Infuser" or tile.tile_type == "Catalyst":
		var popup = PopupPanel.new()
		var vbox = VBoxContainer.new()
		popup.add_child(vbox)
		
		var label = Label.new()
		label.text = "Configure " + tile.tile_type + " Synergy"
		vbox.add_child(label)
		
		var SynergyType = EnergyPacket.SynergyType
		var btn = Button.new()
		var current_name = "RAW"
		var prop_name = "secondary_synergy" if tile.tile_type == "Elemental Infuser" else "target_synergy"
		for key_name in SynergyType.keys():
			if SynergyType[key_name] == tile.get(prop_name):
				current_name = key_name
				break
		btn.text = "Synergy: %s" % current_name
		btn.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.pressed:
				if event.button_index == MOUSE_BUTTON_LEFT:
					tile.cycle_synergy()
				elif event.button_index == MOUSE_BUTTON_RIGHT:
					if tile.has_method("cycle_synergy_backward"):
						tile.cycle_synergy_backward()
						
				var new_name = "RAW"
				for key_name in SynergyType.keys():
					if SynergyType[key_name] == tile.get(prop_name):
						new_name = key_name
						break
				btn.text = "Synergy: %s" % new_name
				grid_renderer.queue_redraw()
		)
		vbox.add_child(btn)

		# MYTHIC Catalyst: Inverted mode - a purity filter instead of a
		# converter (voids everything except the chosen element).
		if tile.tile_type == "Catalyst" and tile.rarity == HexTile.Rarity.MYTHIC:
			var inv_btn = CheckButton.new()
			inv_btn.text = "MYTHIC: Inverted (void all but chosen element)"
			inv_btn.button_pressed = tile.get("inverted") == true
			inv_btn.toggled.connect(func(on):
				tile.inverted = on
				_mark_player_grid_dirty()
				grid_renderer.queue_redraw()
			)
			vbox.add_child(inv_btn)

		add_child(popup)
		popup.popup_centered(Vector2(250, 100))
		popup.popup_hide.connect(func(): popup.queue_free())

	elif tile.tile_type == "Microcore":
		var popup = PopupPanel.new()
		var vbox = VBoxContainer.new()
		popup.add_child(vbox)
		
		var label = Label.new()
		label.text = "Configure Microcore Outputs (Max %d)" % tile.get_max_faces()
		vbox.add_child(label)
		
		var directions = ["East", "South-East", "South-West", "West", "North-West", "North-East"]
		var SynergyType = EnergyPacket.SynergyType
		
		for i in range(6):
			var hbox = HBoxContainer.new()
			var btn = CheckButton.new()
			btn.text = "Face " + str(i) + " (" + directions[i] + ")"
			btn.button_pressed = tile.active_faces.has(i)
			hbox.add_child(btn)
			
			var syn_btn = Button.new()
			var current_syn = tile.get_face_output(i) if tile.has_method("get_face_output") else 0
			var syn_name = "RAW"
			for key_name in SynergyType.keys():
				if SynergyType[key_name] == current_syn:
					syn_name = key_name
					break
			syn_btn.text = "Syn: %s" % syn_name
			syn_btn.disabled = not btn.button_pressed or tile.rarity < HexTile.Rarity.UNCOMMON
			hbox.add_child(syn_btn)
			
			btn.toggled.connect(func(pressed):
				tile.toggle_face(i)
				syn_btn.disabled = not pressed or tile.rarity < HexTile.Rarity.UNCOMMON
				grid_renderer.queue_redraw()
				for j in range(6):
					var child_hbox = vbox.get_child(j + 1)
					var child_btn = child_hbox.get_child(0)
					if child_btn is CheckButton:
						child_btn.set_block_signals(true)
						child_btn.button_pressed = tile.active_faces.has(j)
						child_btn.set_block_signals(false)
			)
			
			syn_btn.pressed.connect(func():
				if tile.has_method("cycle_face_output"):
					tile.cycle_face_output(i)
					var new_syn = tile.get_face_output(i)
					var new_name = "RAW"
					for key_name in SynergyType.keys():
						if SynergyType[key_name] == new_syn:
							new_name = key_name
							break
					syn_btn.text = "Syn: %s" % new_name
			)
			vbox.add_child(hbox)
			
		add_child(popup)
		popup.popup_centered(Vector2(400, 300))
		popup.popup_hide.connect(func(): popup.queue_free())
		
	elif tile.tile_type == "Accumulator":
		var popup = PopupPanel.new()
		var vbox = VBoxContainer.new()
		popup.add_child(vbox)
		
		var label = Label.new()
		label.text = "Configure Accumulator Trigger Key"
		vbox.add_child(label)
		
		var opt = OptionButton.new()
		opt.add_item("None")
		opt.add_item("Key 1")
		opt.add_item("Key 2")
		opt.add_item("Key 3")
		
		var current = 0
		if tile.trigger_key == "1": current = 1
		elif tile.trigger_key == "2": current = 2
		elif tile.trigger_key == "3": current = 3
		opt.select(current)
		
		opt.item_selected.connect(func(index):
			if index == 0: tile.trigger_key = "None"
			elif index == 1: tile.trigger_key = "1"
			elif index == 2: tile.trigger_key = "2"
			elif index == 3: tile.trigger_key = "3"
			grid_renderer.queue_redraw()
		)
		vbox.add_child(opt)

		add_child(popup)
		popup.popup_centered(Vector2(250, 100))
		popup.popup_hide.connect(func(): popup.queue_free())

	elif tile.tile_type == "Magnet":
		var popup = PopupPanel.new()
		var vbox = VBoxContainer.new()
		popup.add_child(vbox)

		var label = Label.new()
		label.text = "Configure Magnet"
		vbox.add_child(label)

		var rarity_names = ["Common", "Uncommon", "Rare", "Legendary", "Mythic"]
		var btn = Button.new()

		var describe_filter = func() -> String:
			if tile.rarity < HexTile.Rarity.MYTHIC:
				return "Rarity filter is a Mythic-only ability"
			elif tile.min_attract_rarity < 0:
				return "Attracts: Any Rarity (click to change)"
			else:
				return "Attracts: %s or above (click to change)" % rarity_names[tile.min_attract_rarity]

		btn.text = describe_filter.call()
		btn.disabled = tile.rarity < HexTile.Rarity.MYTHIC
		btn.pressed.connect(func():
			tile.cycle_min_attract_rarity()
			btn.text = describe_filter.call()
		)
		vbox.add_child(btn)

		if tile.rarity < HexTile.Rarity.MYTHIC:
			var hint = Label.new()
			hint.text = "Upgrade this Magnet to Mythic to filter what it attracts."
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD
			vbox.add_child(hint)
		else:
			# MYTHIC Magnet: Attract/Repel field flip (joins the rarity
			# filter above - Mythic gets BOTH, per design ruling).
			var repel_btn = CheckButton.new()
			repel_btn.text = "MYTHIC: Repel mode (reflect enemy shots back at them)"
			repel_btn.button_pressed = tile.get("repel_mode") == true
			repel_btn.toggled.connect(func(_on):
				tile.toggle_repel_mode()
				_mark_player_grid_dirty()
			)
			vbox.add_child(repel_btn)

		add_child(popup)
		popup.popup_centered(Vector2(280, 120))
		popup.popup_hide.connect(func(): popup.queue_free())

	elif tile.tile_type == "Weapon Mount" or tile.tile_type == "Jumpjet" or tile.tile_type == "Amplifier" or tile.tile_type == "Directional Conduit" or tile.tile_type == "Shield Generator" or tile.tile_type == "Actuator":
		# Mythic-ability popup for tiles that had no click config before.
		var popup = PopupPanel.new()
		var vbox = VBoxContainer.new()
		popup.add_child(vbox)

		var label = Label.new()
		label.text = "Configure " + tile.tile_type
		vbox.add_child(label)

		if tile.rarity < HexTile.Rarity.MYTHIC:
			var hint = Label.new()
			hint.text = "Mythic ability locked - upgrade this tile to Mythic."
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD
			vbox.add_child(hint)
		else:
			var mode_names: Array = []
			var prop = ""
			var cycle_method = ""
			match tile.tile_type:
				"Weapon Mount":
					mode_names = ["Normal", "Shotgun", "Radial Burst", "Beam"]
					prop = "mythic_pattern"
					cycle_method = "cycle_mythic_pattern"
				"Jumpjet":
					mode_names = ["Jump", "Blink"]
					prop = "mythic_mode"
					cycle_method = "cycle_mythic_mode"
				"Amplifier":
					mode_names = ["Balanced", "Pure Damage", "AoE Focus"]
					prop = "mythic_focus"
					cycle_method = "cycle_mythic_focus"
				"Directional Conduit":
					mode_names = ["Two-Way", "One-Way Valve"]
					prop = "mythic_mode"
					cycle_method = "cycle_mythic_mode"
				"Shield Generator":
					mode_names = ["Aegis (tank)", "Deflector (overflow eject)"]
					prop = "mythic_mode"
					cycle_method = "cycle_mythic_mode"
				"Actuator":
					mode_names = ["Velocity", "Ember", "Balanced"]
					prop = "mythic_mode"
					cycle_method = "cycle_mythic_mode"

			var mode_btn = Button.new()
			mode_btn.text = "MYTHIC mode: %s (click to cycle)" % mode_names[int(tile.get(prop)) % mode_names.size()]
			mode_btn.pressed.connect(func():
				tile.call(cycle_method)
				mode_btn.text = "MYTHIC mode: %s (click to cycle)" % mode_names[int(tile.get(prop)) % mode_names.size()]
				_mark_player_grid_dirty()
			)
			vbox.add_child(mode_btn)

		add_child(popup)
		popup.popup_centered(Vector2(300, 120))
		popup.popup_hide.connect(func(): popup.queue_free())

# Any Mythic-mode change alters the precalculated grid state - make sure
# the mech rebuilds it before the next shot.
func _mark_player_grid_dirty():
	var main = get_parent()
	if main and main.get("player") != null:
		main.player.is_grid_dirty = true

# Fire-and-forget notification to TutorialManager, if one exists (it may
# not - only present during the first-run onboarding flow). Kept as a tiny
# shared helper so every call site is one line instead of a repeated
# get_first_node_in_group + null-check.
func _tutorial_notify(event: String):
	var tm = get_tree().get_first_node_in_group("tutorial_manager")
	if tm:
		tm.notify(event)

func _on_simulate_pressed():
	_tutorial_notify("event:simulate_pressed")
	if is_simulating:
		is_simulating = false
		if sim_button: sim_button.text = "Simulate Energy Flow"
		return
		
	if not grid_renderer.hex_grid: return
	
	is_simulating = true
	if sim_button: sim_button.text = "Stop Simulation"
	
	var initial_packets: Array[EnergyPacket] = []
	
	if active_component:
		# Clear pending packets on current grid before simulating
		for t in active_component.hex_grid.get_all_tiles():
			if "pending_packets" in t:
				t.pending_packets.clear()
				
		# 1. Generate local energy from any Core Reactors in this component's grid

		for h in grid_renderer.hex_grid.grid.keys():
			var tile = grid_renderer.hex_grid.get_tile(h)
			if tile.has_method("generate_energy"):
				var pkts = tile.generate_energy(grid_renderer.hex_grid)
				for p in pkts:
					p.position = HexCoord.new(h.x, h.y)
				initial_packets.append_array(pkts)
				
		# 2. Add actual transfer packets from Torso to simulate cross-component energy flow
		if active_component.slot_type != HexTile.BodySlot.TORSO:
			if mech_components.has(HexTile.BodySlot.TORSO) and mech_components[HexTile.BodySlot.TORSO]:
				var torso_comp = mech_components[HexTile.BodySlot.TORSO]
				var t_pkts = []
				for h in torso_comp.hex_grid.grid.keys():
					var tile = torso_comp.hex_grid.get_tile(h)
					if tile.has_method("generate_energy"):
						var pkts = tile.generate_energy(torso_comp.hex_grid)
						for p in pkts: p.position = HexCoord.new(h.x, h.y)
						t_pkts.append_array(pkts)
						
				var dummy_mech = load("res://scripts/entities/Mech.gd").new()
				dummy_mech._simulate_grid(torso_comp.hex_grid, t_pkts)
				var transfers = dummy_mech._collect_transfers(torso_comp)
				
				if transfers.has(active_component.slot_type):
					for packet in transfers[active_component.slot_type]:
						var dir = 3 # default west
						if active_component.slot_type == HexTile.BodySlot.ARM_L: dir = 3
						elif active_component.slot_type == HexTile.BodySlot.ARM_R: dir = 0
						elif active_component.slot_type == HexTile.BodySlot.HEAD: dir = 5
						elif active_component.slot_type == HexTile.BodySlot.LEG_L or active_component.slot_type == HexTile.BodySlot.LEG_R: dir = 1
						elif active_component.slot_type == HexTile.BodySlot.BACKPACK: dir = 4
						
						packet.direction = dir
						var opp_dir = (dir + 3) % 6
						packet.position = HexCoord.new(0, 0).neighbor(opp_dir)
						packet.is_active = true
						initial_packets.append(packet)
				dummy_mech.free()
			
		# 3. If Torso, pull returning energy from Head and Backpack
		if active_component.slot_type == HexTile.BodySlot.TORSO:
			var dummy_mech = load("res://scripts/entities/Mech.gd").new()
			
			# We need to simulate the Torso first to find out what it sends out!
			var dummy_t_pkts: Array[EnergyPacket] = []
			for p in initial_packets:
				dummy_t_pkts.append(p.copy())
			dummy_mech._simulate_grid(active_component.hex_grid, dummy_t_pkts)
			var dummy_transfers = dummy_mech._collect_transfers(active_component)
			
			for p_slot in [HexTile.BodySlot.HEAD, HexTile.BodySlot.BACKPACK]:
				if mech_components.has(p_slot) and mech_components[p_slot]:
					var p_comp = mech_components[p_slot]
					var p_pkts: Array[EnergyPacket] = []
					
					# 3a. Add energy received from Torso
					if dummy_transfers.has(p_slot):
						var incoming = dummy_transfers[p_slot]
						dummy_mech._route_to_peripheral(incoming, p_comp)
						p_pkts.append_array(incoming)
					
					# 3b. Add generated energy
					for h in p_comp.hex_grid.grid.keys():
						var tile = p_comp.hex_grid.get_tile(h)
						if tile.has_method("generate_energy"):
							var pkts = tile.generate_energy(p_comp.hex_grid)
							for p in pkts: p.position = HexCoord.new(h.x, h.y)
							p_pkts.append_array(pkts)
							
					dummy_mech._simulate_grid(p_comp.hex_grid, p_pkts)
					var transfers = dummy_mech._collect_transfers(p_comp)
					
					if transfers.has(HexTile.BodySlot.TORSO):
						# Find Accessory Return on Torso
						var acc_pos = HexCoord.new(0, 0)
						for coord_v in grid_renderer.hex_grid.grid.keys():
							var t = grid_renderer.hex_grid.grid[coord_v]
							if t.tile_type == "Accessory Return":
								acc_pos = HexCoord.new(coord_v.x, coord_v.y)
								break
								
						for pkt in transfers[HexTile.BodySlot.TORSO]:
							# Start them one step backwards based on their direction, but wait: we want them to enter the Accessory Return. 
							# If we just let them enter with a fixed direction like North (2), they will be processed.
							pkt.direction = 2 # Entering from North
							var opp_dir = (pkt.direction + 3) % 6
							pkt.position = acc_pos.neighbor(opp_dir)
							pkt.is_active = true
							initial_packets.append(pkt)
			dummy_mech.free()
			
			# Clean up any leftover packets on peripheral weapon mounts so they don't leak
			for p_slot in [HexTile.BodySlot.HEAD, HexTile.BodySlot.BACKPACK]:
				if mech_components.has(p_slot) and mech_components[p_slot]:
					for t in mech_components[p_slot].hex_grid.get_all_tiles():
						if t.tile_type == "Weapon Mount" and "pending_packets" in t:
							t.pending_packets.clear()
			
	for p in initial_packets:
		p.set_meta("source_hex", p.position)
		p.set_meta("target_hex", p.position)
		p.set_meta("anim_progress", 1.0)
		p.is_active = true
	
	grid_renderer.active_packets = initial_packets
	grid_renderer.simulation_step = 0
	
	_update_stats()
	_simulate_step()

func _simulate_step():
	var active = grid_renderer.active_packets
	if active.is_empty(): return
	
	grid_renderer.simulation_step += 1
	var new_packets: Array[EnergyPacket] = []
	
	for pkt in active:
		if not pkt.is_active: continue
		var pos = pkt.position
		
		# Animate to next tile
		var dir = pkt.direction
		var next_pos = pos.neighbor(dir)
		
		var out_pkts = []
		if grid_renderer.hex_grid.has_tile(next_pos):
			var tile = grid_renderer.hex_grid.get_tile(next_pos)
			out_pkts = tile.process_energy(pkt, (dir + 3) % 6)
			for out in out_pkts:
				if out.magnitude < 0.5:
					out.is_active = false
				out.position = next_pos
				out.set_meta("source_hex", pos)
				out.set_meta("target_hex", next_pos)
				out.set_meta("anim_progress", 0.0)
		else:
			var is_valid_empty = false
			if active_component and "valid_hexes" in active_component:
				for h in active_component.valid_hexes:
					if h.q == next_pos.q and h.r == next_pos.r:
						is_valid_empty = true
						break
						
			if is_valid_empty:
				# Pass straight through empty hex with 5% loss
				pkt.position = next_pos
				pkt.magnitude *= 0.95
				for k in pkt.synergies.keys():
					pkt.synergies[k] *= 0.95
				pkt.set_meta("source_hex", pos)
				pkt.set_meta("target_hex", next_pos)
				pkt.set_meta("anim_progress", 0.0)
				out_pkts = [pkt]
			else:
				# Bounce off edge of component
				pkt.direction = (dir + 3) % 6
				pkt.set_meta("source_hex", pos)
				pkt.set_meta("target_hex", pos)
				pkt.set_meta("anim_progress", 0.0)
				out_pkts = [pkt]
			
		new_packets.append_array(out_pkts)
		
	var merged_packets: Array[EnergyPacket] = []
	var packet_map: Dictionary = {}
	
	for pkt in new_packets:
		if not pkt.is_active: continue
		var key = str(pkt.position.q) + "_" + str(pkt.position.r) + "_" + str(pkt.direction)
		if packet_map.has(key):
			packet_map[key].merge(pkt)
		else:
			packet_map[key] = pkt
			merged_packets.append(pkt)
			
	grid_renderer.active_packets = merged_packets
	_update_stats()
	
	# Auto step loop
	var tree = get_tree()
	if tree:
		await tree.create_timer(0.5).timeout
		if not is_simulating:
			grid_renderer.active_packets.clear()
			_update_stats()
			return
			
		var still_alive = false
		for p in grid_renderer.active_packets:
			if grid_renderer.hex_grid.has_tile(p.position):
				still_alive = true
				break
		if still_alive:
			_simulate_step()
		else:
			is_simulating = false
			if sim_button: sim_button.text = "Simulate Energy Flow"

# Compact display for the stats panel's numbers. Stays readable at any
# magnitude: plain integers below 1000, a K/M/B/T suffix ladder up through
# the trillions (covers every sane in-game build), and true scientific
# notation beyond that - Natalia's own suggestion, and the only thing that
# stays legible once a stacked Amplifier/Resonator build (or, previously, the
# EnergyPacket synergies/magnitude decoupling bug - see EnergyPacket.gd's
# _sync_synergies_to_magnitude) pushes a number into the 1e15+ range. Built
# from plain arithmetic + %f/%d rather than relying on "%e" so it doesn't
# depend on GDScript's sprintf coverage.
static func _format_magnitude(val: float) -> String:
	if val == 0:
		return "0"
	var sign_str = "-" if val < 0 else ""
	var abs_val = abs(val)
	if abs_val < 1000.0:
		return sign_str + str(int(round(abs_val)))
	if abs_val >= 1e15:
		var exponent = int(floor(log(abs_val) / log(10.0)))
		var mantissa = abs_val / pow(10.0, exponent)
		# Rounding the mantissa can carry it up to 10.0 (e.g. 9.996 -> "10.00")
		# which would print as "10.00e5" instead of "1.00e6" - bump the
		# exponent and rescale when that happens.
		mantissa = snapped(mantissa, 0.01)
		if mantissa >= 10.0:
			mantissa /= 10.0
			exponent += 1
		return "%s%se%d" % [sign_str, str(mantissa), exponent]
	var suffixes = [
		{"v": 1e12, "s": "T"},
		{"v": 1e9, "s": "B"},
		{"v": 1e6, "s": "M"},
		{"v": 1e3, "s": "K"},
	]
	for suf in suffixes:
		if abs_val >= suf.v:
			return "%s%s%s" % [sign_str, str(snapped(abs_val / suf.v, 0.01)), suf.s]
	return sign_str + str(int(round(abs_val)))

func _update_stats():
	var total_nrg = 0.0
	for p in grid_renderer.active_packets:
		total_nrg += p.magnitude

	var grid_size = grid_renderer.hex_grid.get_all_tiles().size() if grid_renderer.hex_grid else 0

	# Aggregate synergies from all Weapon Mounts/Accessory Returns
	var synergy_totals = {}
	var total_output = 0.0
	if grid_renderer.hex_grid:
		for t in grid_renderer.hex_grid.get_all_tiles():
			if "pending_packets" in t:
				for item in t.pending_packets:
					var p = item.packet
					total_output += p.magnitude
					for k in p.synergies:
						synergy_totals[k] = synergy_totals.get(k, 0.0) + p.synergies[k]

	var syn_str = ""
	var SynergyType = EnergyPacket.SynergyType
	var syn_names = SynergyType.keys()
	for k in synergy_totals.keys():
		var val = synergy_totals[k]
		if val > 0:
			var syn_name = "UNKNOWN"
			for key_name in syn_names:
				if SynergyType[key_name] == k:
					syn_name = key_name
					break
			syn_str += "%s: %s\n" % [syn_name, _format_magnitude(val)]

	if syn_str == "":
		syn_str = "None\n"

	var nrg_str = _format_magnitude(total_nrg)
	var out_str = _format_magnitude(total_output)

	stats_label.text = "=== COMPONENT INFO ===\nTiles Used: %d\n\n=== OUTPUT ===\nTotal Damage: %s\n%s\n=== SIMULATION ===\nStep: %d\nActive Packets: %d\nMoving Energy: %s" % [
		grid_size,
		out_str,
		syn_str,
		grid_renderer.simulation_step,
		grid_renderer.active_packets.size(),
		nrg_str
	]


func _on_auto_equip_pressed():
	if not active_component or not active_component.hex_grid:
		return
	
	var solver_class = load("res://scripts/core/AutoEquipSolver.gd")
	if not solver_class:
		print("Failed to load AutoEquipSolver")
		return
	var solver = solver_class.new()
	var new_inventory = solver.solve(active_component, inventory)
	if new_inventory != null:
		inventory = new_inventory
		grid_renderer.queue_redraw()
		_refresh_inventory_ui()
		print("Auto-Equip completed!")

# Sends every removable tile in the active component's grid back to
# inventory. Uses the exact same protection rule the existing single-tile
# right-click removal already uses (only the Torso Core at (0,0) is
# protected) rather than inventing new, stricter rules that would behave
# differently from removing tiles one at a time.
func _on_clear_grid_pressed():
	if not active_component or not grid_renderer.hex_grid:
		return

	var tiles = grid_renderer.hex_grid.get_all_tiles()
	var cleared = 0
	for tile in tiles:
		var h = tile.grid_position
		if not h:
			continue
		if active_component.slot_type == HexTile.BodySlot.TORSO and h.q == 0 and h.r == 0:
			continue # Never clear the Torso Core
		grid_renderer.hex_grid.remove_tile(h)
		inventory.append(tile)
		cleared += 1

	if cleared > 0:
		_refresh_inventory_ui()
		grid_renderer.queue_redraw()
		print("[Garage] Cleared %d tiles back to inventory" % cleared)

func _on_swap_component_pressed():
	if not active_component: return
	var main = get_tree().current_scene
	if not main or main.get("player_component_inventory") == null: return
	
	var compatible = []
	for i in range(main.player_component_inventory.size()):
		var comp = main.player_component_inventory[i]
		if comp.slot_type == active_component.slot_type:
			compatible.append({"index": i, "comp": comp})
			
	if compatible.is_empty():
		# Naming the slot here matters: Swap/Upgrade/Extract all act on
		# whichever tab is currently selected (active_component), not on
		# "any spare part you own" - a spare Right Arm does nothing while
		# the Torso tab is selected. Calling out the slot by name makes that
		# tab-scoping visible instead of just looking broken.
		_show_warning("No compatible %s components in inventory!" % _slot_display_name(active_component.slot_type))
		return
		
	var popup = PopupMenu.new()
	for item in compatible:
		var name_str = item.comp.component_name
		if item.comp.rarity > 0: name_str += " (Rarity %d)" % item.comp.rarity
		if item.comp.get("infusion_level", 0) > 0: name_str += " [Lv%d]" % item.comp.infusion_level
		popup.add_item(name_str, item.index)
		
	popup.id_pressed.connect(func(id):
		# Swap!
		var new_comp = main.player_component_inventory[id]
		main.player_component_inventory.remove_at(id)
		
		var main_player = main.player
		if main_player:
			# Unequip old
			main_player.remove_child(active_component)
			main_player.components.erase(active_component.slot_type)
			main.player_component_inventory.append(active_component)
			
			# Equip new
			main_player.equip_component(new_comp)
			mech_components = main_player.components
			
			_populate_component_tabs()
			popup.queue_free()
	)
	add_child(popup)
	popup.popup_centered(Vector2(300, 400))

func _on_infuse_component_pressed():
	if not active_component: return
	var main = get_tree().current_scene
	if not main or not "player_component_inventory" in main: return
	
	if main.player_component_inventory.is_empty():
		_show_warning("No components in inventory to dismantle!")
		return
		
	var popup = PopupMenu.new()
	for i in range(main.player_component_inventory.size()):
		var comp = main.player_component_inventory[i]
		var name_str = comp.component_name
		if comp.rarity > 0: name_str += " (Rarity %d)" % comp.rarity
		if comp.get("infusion_level", 0) > 0: name_str += " [Lv%d]" % comp.infusion_level
		popup.add_item("Dismantle " + name_str, i)
		
	popup.id_pressed.connect(func(id):
		var junk = main.player_component_inventory[id]
		main.player_component_inventory.remove_at(id)
		
		# Transfer tiles from dismantled component to inventory
		var junk_tiles = junk.hex_grid.get_all_tiles()
		for t in junk_tiles:
			if t.tile_type != "Component Link" and t.tile_type != "Core Reactor":
				inventory.append(t)
		
		# Add XP
		var xp_gain = 100 + (junk.rarity * 150)
		if active_component.has_method("add_infusion_xp"):
			active_component.add_infusion_xp(xp_gain)
			_show_warning("Infused %s! +%d XP to %s" % [junk.component_name, xp_gain, active_component.component_name])
		else:
			_show_warning("ComponentEquipment missing Infusion Logic!")
			
		_refresh_inventory_ui()
		popup.queue_free()
	)
	add_child(popup)
	popup.popup_centered(Vector2(300, 400))

# --- Synergy Codex ----------------------------------------------------------
# Player-facing reference for what the 9 elemental synergies actually do -
# previously that knowledge only existed scattered across Projectile.gd's
# per-synergy branches (chain lightning, burning/frozen status, the shield
# counter-wheel, etc.) with zero in-game explanation. Colors are pulled
# straight from EnergyPacket.get_color_for_synergy so the codex always
# matches the actual projectile/tile tinting, and descriptions are a plain-
# language summary of the real mechanics (not aspirational/simplified).
const SYNERGY_CODEX_ENTRIES = [
	{"id": 0, "name": "RAW", "desc": "The baseline element - no special interactions, no counters. Always the fallback when no synergy dominates a shot."},
	{"id": 1, "name": "FIRE", "desc": "Applies a burning damage-over-time status on hit. Shots run a short lifetime (fast, close-range feel). Deals 2x against Ice shields; takes 2x from Ice shields in return."},
	{"id": 2, "name": "ICE", "desc": "Applies a frozen/slow status on hit, fighting back against Kinetic-heavy builds' mobility. Deals 2x against Fire shields; takes 2x from Fire shields in return."},
	{"id": 3, "name": "LIGHTNING", "desc": "Arcs instantly between nearby enemies (chain lightning) instead of traveling as a single bolt. Always deals 1.5x against ANY shield, on top of the normal counter-wheel bonus vs Kinetic shields."},
	{"id": 4, "name": "VORTEX", "desc": "Pulls in nearby loot and (weakly) enemies/player toward the impact point - a battlefield-control element as much as a damage one. Deals 2x against Kinetic shields."},
	{"id": 5, "name": "POISON", "desc": "Stacks a damage-over-time poison effect that can stack multiple times. Deals 2x against Vampiric shields; takes 2x from Vampiric shields in return."},
	{"id": 6, "name": "EXPLOSION", "desc": "Detonates in an area-of-effect blast on impact instead of a single-target hit - radius scales with the synergy's ratio in the shot and any Amplifier AoE bonus."},
	{"id": 7, "name": "KINETIC", "desc": "Massively extends weapon range (triple at full ratio) and keeps a locked, unwavering straight trajectory - plus knockback-heavy hits, pure mass-behind-the-shot damage. Deals 2x against Lightning shields; takes 2x from Lightning shields in return."},
	{"id": 8, "name": "PIERCE", "desc": "High-velocity, armor-piercing rounds - ignores a flat share of armor/shield mitigation on every hit, and any PIERCE hit that gets past shields has a small flat chance to instantly execute the target outright - regardless of remaining HP. Bosses, Commanders, and Piercing Jammers (plus anyone standing in a Piercing Jammer's aura) are immune to that execution."},
	{"id": 9, "name": "VAMPIRIC", "desc": "Heals the attacker for a share of the damage dealt (lifesteal). Deals 2x against Poison shields; takes 2x from Poison shields in return."},
]

var _codex_popup: PopupPanel = null

func _on_codex_pressed():
	if not _codex_popup:
		_codex_popup = _build_codex_popup()
		add_child(_codex_popup)
	_codex_popup.popup_centered(Vector2(460, 520))

func _build_codex_popup() -> PopupPanel:
	var popup = PopupPanel.new()
	popup.title = "Synergy Codex"

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 500)
	popup.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var header = Label.new()
	header.text = "How each element behaves - shield bonuses are always mutual (both directions apply)."
	header.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())

	for entry in SYNERGY_CODEX_ENTRIES:
		var row = HBoxContainer.new()
		vbox.add_child(row)

		var swatch = ColorRect.new()
		swatch.color = EnergyPacket.get_color_for_synergy(entry.id)
		swatch.custom_minimum_size = Vector2(16, 16)
		row.add_child(swatch)

		var text_vbox = VBoxContainer.new()
		text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text_vbox)

		var name_label = Label.new()
		name_label.text = entry.name
		name_label.add_theme_color_override("font_color", EnergyPacket.get_color_for_synergy(entry.id))
		text_vbox.add_child(name_label)

		var desc_label = Label.new()
		desc_label.text = entry.desc
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		desc_label.custom_minimum_size = Vector2(390, 0)
		text_vbox.add_child(desc_label)

		vbox.add_child(HSeparator.new())

	return popup

func _show_warning(msg: String):
	var dialog = AcceptDialog.new()
	dialog.dialog_text = msg
	add_child(dialog)
	dialog.popup_centered()
