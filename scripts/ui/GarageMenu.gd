class_name GarageMenu
extends CanvasLayer



const ComponentEquipment = preload("res://scripts/core/ComponentEquipment.gd")
const SplitterTile = preload("res://scripts/tiles/SplitterTile.gd")
const AmplifierTile = preload("res://scripts/tiles/AmplifierTile.gd")
const CatalystTile = preload("res://scripts/tiles/CatalystTile.gd")
const GarageGridRenderer = preload("res://scripts/ui/GarageGridRenderer.gd")
const ComponentDiagramView = preload("res://scripts/ui/ComponentDiagramView.gd")
const GarageSimulationRunner = preload("res://scripts/ui/GarageSimulationRunner.gd")
const GarageMarket = preload("res://scripts/ui/GarageMarket.gd")
const GarageShop = preload("res://scripts/ui/GarageShop.gd")
const SynergyCodexPopup = preload("res://scripts/ui/SynergyCodexPopup.gd")
const TileActionMenu = preload("res://scripts/ui/TileActionMenu.gd")
const GarageInventoryPanel = preload("res://scripts/ui/GarageInventoryPanel.gd")
const GarageTileConfigPopup = preload("res://scripts/ui/GarageTileConfigPopup.gd")
const GaragePacketInspector = preload("res://scripts/ui/GaragePacketInspector.gd")
const GarageUIBuilder = preload("res://scripts/ui/GarageUIBuilder.gd")

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
# tiles - per the user, that was invisible enough to look like those
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
# which is why the user couldn't find their purchased parts - the tray was
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
# Set when fill_mode kicks in AND the origin hex already holds a tile of the
# SAME type as what's being dragged (playtest: "if I hover over a splitter,
# before I hover a blank space then fill, it will match the first
# splitter") - every tile placed for the rest of this fill line has its
# config stamped from this one via HexTile.copy_config_from. Null means
# "no template, place with whatever config each inventory copy already had"
# (unchanged legacy behavior).
var fill_template_tile: HexTile = null

# Orientation (0-5, a hex direction index) a multi-cell tile like the Lance
# Mount would be placed in if dropped right now - see GarageGridRenderer.
# _gui_input's wheel handling (scroll rotates instead of zooms while
# dragging a footprint tile) and GarageInventoryPanel._drop_footprint_tile.
var footprint_rotation: int = 0

var inventory: Array = []
var search_input: LineEdit
var rarity_filter: OptionButton
var sim_button: Button
# Live inventory search text (lowercased), read by GarageGridRenderer._draw_
# tile to dim grid tiles that don't match - see GarageInventoryPanel.
# refresh_inventory_ui. Empty means no filter/no dimming.
var inventory_search_filter: String = ""

var is_simulating: bool = false
var simulation_runner: GarageSimulationRunner = null
var garage_market: GarageMarket = null
var garage_shop: GarageShop = null
var synergy_codex_popup: SynergyCodexPopup = null
var tile_action_menu: TileActionMenu = null
var garage_inventory_panel: GarageInventoryPanel = null
var garage_tile_config_popup: GarageTileConfigPopup = null
var garage_packet_inspector: GaragePacketInspector = null

# Simulation Timeline Scrubber (Status.md queue) - visible only once a
# simulation has run at least once for the current grid. See
# GarageSimulationRunner.seek_to_step/_update_scrubber_range.
var sim_scrubber: HSlider = null
var sim_step_label: Label = null
# Opt-in switch for what a tile click does while the scrubber is visible -
# OFF by default so simulating never silently blocks normal editing (see
# _on_tile_clicked's field comment for the regression this fixes).
var sim_inspect_toggle: CheckButton = null
# Set true only while the scrubber's own code moves .value programmatically
# (syncing to live auto-play) - guards _on_sim_scrubber_changed so that
# doesn't misread a programmatic move as a user drag and re-seek redundantly.
var _scrubber_syncing: bool = false

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
	# Preserve whatever was selected before the rebuild - playtest report:
	# "I cannot upgrade any components except the torso - I pop to the
	# torso every time I try to upgrade anything else." upgrade_part()/
	# extract_modifier()/infuse_chip() (TileActionMenu.gd) and Swap
	# Component (below) all call _refresh_component_ui() afterward, which
	# calls this - the upgrade itself was applying correctly to whatever
	# was actually active, but this then unconditionally jumped to tab 0
	# (always Torso, per slot_order below), snapping the view back and
	# making it look like only Torso could ever be upgraded. Captured as
	# the raw tab metadata (not active_component.slot_type) since a Drone
	# tab's active_component is that drone's own internal loadout, whose
	# slot_type reads TORSO (see create_starter_drone) - deriving "which
	# tab" from the component instead of the metadata would misidentify a
	# selected Drone tab as the real Torso tab.
	var prev_meta = null
	if component_tabs.get_tab_count() > 0 and component_tabs.current_tab >= 0:
		prev_meta = component_tabs.get_tab_metadata(component_tabs.current_tab)

	component_tabs.clear_tabs()
	if mech_components.is_empty():
		return

	# Canonical slot order, Torso ALWAYS first - insertion order comes from
	# whatever the save dict happened to hold, which could bury the Torso
	# tab off-screen behind a pile of drone tabs.
	var slot_order = [HexTile.BodySlot.TORSO, HexTile.BodySlot.ARM_L, HexTile.BodySlot.ARM_R, HexTile.BodySlot.LEG_L, HexTile.BodySlot.LEG_R, HexTile.BodySlot.HEAD, HexTile.BodySlot.BACKPACK]
	for slot in mech_components.keys():
		if not slot_order.has(slot):
			slot_order.append(slot) # future slots still get a tab
	for slot in slot_order:
		if not mech_components.has(slot):
			continue
		var comp = mech_components[slot]
		component_tabs.add_tab(comp.component_name)
		component_tabs.set_tab_metadata(component_tabs.get_tab_count() - 1, slot)

	# Drone tabs: one per Drone Bay tile actually installed somewhere in the
	# equipped Backpack's hex grid (see DroneBayTile.gd) - a build can carry
	# more than one bay, each flying its own independent drone with its own
	# loadout. None of these are entries in mech_components (deliberately -
	# see HexTile.BodySlot.DRONE's comment), so each is appended here with a
	# Dictionary tab metadata ({"slot": DRONE, "bay": <the specific tile>})
	# that _on_tab_changed special-cases instead of indexing straight into
	# mech_components like every other (plain-int-metadata) tab.
	var drone_bays = _find_all_drone_bay_tiles()
	for i in range(drone_bays.size()):
		var label = "Drone" if drone_bays.size() == 1 else "Drone %d" % (i + 1)
		component_tabs.add_tab(label)
		component_tabs.set_tab_metadata(component_tabs.get_tab_count() - 1, {"slot": HexTile.BodySlot.DRONE, "bay": drone_bays[i]})
		drone_bays[i].bay_number = i + 1

	var restore_index = 0
	if prev_meta != null:
		for i in range(component_tabs.get_tab_count()):
			var m = component_tabs.get_tab_metadata(i)
			if m is Dictionary and prev_meta is Dictionary:
				if m.get("slot") == prev_meta.get("slot") and m.get("bay") == prev_meta.get("bay"):
					restore_index = i
					break
			elif m == prev_meta:
				restore_index = i
				break
	component_tabs.current_tab = restore_index
	_on_tab_changed(restore_index)

# Returns every Drone Bay tile installed anywhere across the mech's
# equipped components (not just the Backpack - nothing actually restricts
# where a Drone Bay can be placed, see DroneBayTile.find_all_in_mech; a
# bay placed in the Torso/an Arm/a Leg/the Head used to never get a Drone
# tab here despite clearly being present in the build).
func _find_all_drone_bay_tiles():
	var DroneBayTileClass = load("res://scripts/tiles/DroneBayTile.gd")
	return DroneBayTileClass.find_all_in_mech(mech_components)

func _refresh_component_ui():
	# If player was loaded or components changed, update the reference and tabs
	if get_parent() and get_parent().get("player") != null:
		mech_components = get_parent().player.components
	_populate_component_tabs()
	if not tile_action_menu:
		tile_action_menu = TileActionMenu.new(self)
	tile_action_menu.update_chip_label()
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
# The Drone satellite is a single callout regardless of how many Drone Bay
# tabs actually exist (see ComponentDiagramView's _slot_defs comment) -
# clicking it jumps to the FIRST Drone tab; editing a second/third bay's
# loadout means picking its tab directly from the strip.
func _on_diagram_slot_pressed(slot_type):
	for i in range(component_tabs.get_tab_count()):
		var meta = component_tabs.get_tab_metadata(i)
		if meta is Dictionary:
			if meta.get("slot") == slot_type:
				component_tabs.current_tab = i
				_on_tab_changed(i)
				return
		elif meta == slot_type:
			component_tabs.current_tab = i
			_on_tab_changed(i)
			return

func _on_tab_changed(index: int):
	if index < 0 or index >= component_tabs.get_tab_count():
		return

	var meta = component_tabs.get_tab_metadata(index)
	if meta == null: return

	# Switching tabs swaps grid_renderer.hex_grid to a different component
	# entirely - any Timeline Scrubber snapshot from before belongs to a
	# grid that isn't even on screen anymore, so it hides itself rather
	# than scrubbing a stale/invisible sim.
	if sim_scrubber:
		sim_scrubber.visible = false
	if sim_inspect_toggle:
		sim_inspect_toggle.visible = false

	# Force-stop a still-animating live Simulate run before switching grids.
	# is_simulating only ever clears itself when the sim naturally drains to
	# completion or the player manually presses "Stop Simulation" - leaving
	# either undone (switching tabs mid-animation, the common case) left it
	# stuck true forever. Two real consequences: the orphaned step() await-
	# loop kept firing every 0.5s against whatever grid_renderer.hex_grid
	# THEN pointed at (i.e. corrupting the NEXT component you looked at, not
	# the one the sim was actually for), and run_silent_snapshot()'s own
	# `if garage.is_simulating: return` guard permanently blocked the silent
	# recompute below from ever running again for the rest of the session -
	# playtest report: "I still need to run the simulation before the energy
	# coming into the component will model accurately," despite the silent-
	# snapshot feature being wired in correctly.
	if is_simulating:
		is_simulating = false
		if sim_button: sim_button.text = "Simulate Energy Flow"

	if meta is Dictionary and meta.get("slot") == HexTile.BodySlot.DRONE:
		var drone_bay = meta.get("bay")
		if not drone_bay or not is_instance_valid(drone_bay):
			return
		active_component = drone_bay.get_or_build_loadout()
	else:
		active_component = mech_components[meta]

	grid_renderer.setup(active_component.hex_grid, self, active_component.valid_hexes)
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

	# Playtest request: "still needing to run the simulation on the torso in
	# order to get accurate info in any of the peripherals - could it cache
	# the results of a silent calculation... so I can start simulating
	# anywhere and have more or less consistent results?" - a silent (non-
	# animated) full recompute runs every time the viewed component changes,
	# so pending_packets/stats_label are already accurate the instant you
	# switch tabs, whether or not Simulate has ever been pressed on this
	# component or the torso. See GarageSimulationRunner.run_silent_snapshot.
	if not simulation_runner:
		simulation_runner = GarageSimulationRunner.new(self)
	simulation_runner.run_silent_snapshot()

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
	leg_cat.target_synergy = EnergyPacket.SynergyType.LIGHTNING
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
	GarageUIBuilder.new(self).build()

# Refreshes both views of player_component_inventory (spare full arm/leg/
# torso/head/backpack assemblies): the diagram's per-slot "what's equipped"
# labels, and the draggable spare-parts tray below it. Piggybacks on
# _refresh_inventory_ui()'s call sites (upgrade, swap, extract modifier,
# black market purchase, dismantle, etc. all already call that) rather than
# needing its own separate hook everywhere.
func _refresh_component_inventory_list():
	if not garage_inventory_panel:
		garage_inventory_panel = GarageInventoryPanel.new(self)
	garage_inventory_panel.refresh_component_list()

func _refresh_inventory_ui():
	if not garage_inventory_panel:
		garage_inventory_panel = GarageInventoryPanel.new(self)
	garage_inventory_panel.refresh_inventory_ui()

# Single source of truth for what a tile is worth - this exact
# rarity->value ladder was previously copy-pasted in three places
# (scrap, sell-all, and upgrade costs derive from it too).
static func tile_scrap_value(tile: HexTile) -> int:
	match tile.rarity:
		1: return 25
		2: return 75
		3: return 250
		4: return 1000
		_: return 10

# Upgrading costs roughly double the tile's scrap value per current level -
# so leveling your favorite tile is always pricier than scrapping chaff,
# and high-rarity upgrades are a serious investment (Mythic L1->2 = 2000).
static func tile_upgrade_cost(tile: HexTile) -> int:
	return tile_scrap_value(tile) * 2 * tile.level

func _input(event):
	if not garage_inventory_panel:
		garage_inventory_panel = GarageInventoryPanel.new(self)
	garage_inventory_panel.handle_input(event)

func _process(_delta):
	if not garage_inventory_panel:
		garage_inventory_panel = GarageInventoryPanel.new(self)
	garage_inventory_panel.handle_process(_delta)

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

func _on_repair_all():
	if not tile_action_menu:
		tile_action_menu = TileActionMenu.new(self)
	tile_action_menu.repair_all()

func _on_infuse_part():
	if not tile_action_menu:
		tile_action_menu = TileActionMenu.new(self)
	tile_action_menu.infuse_part()

# --- Feature 5: manual-hex upgrades ----------------------------------------

# Hexes the player still has to place after an upgrade (consumed by
# GarageGridRenderer'''s expansion-click mode).
var pending_expansion_hexes: int = 0
var chip_count_label: Label = null

func _on_upgrade_part():
	if not tile_action_menu:
		tile_action_menu = TileActionMenu.new(self)
	tile_action_menu.upgrade_part()

# --- Feature 5: modifier extraction + chip infusion --------------------------

func _on_extract_modifier():
	if not tile_action_menu:
		tile_action_menu = TileActionMenu.new(self)
	tile_action_menu.extract_modifier()

func _on_infuse_chip():
	if not tile_action_menu:
		tile_action_menu = TileActionMenu.new(self)
	tile_action_menu.infuse_chip()

# Shared human-readable slot names - used by the Black Market listing, the
# spare-components list, and the Swap Component warning/popup, so a purchased
# part is identifiable as "Right Arm" everywhere instead of showing up as a
# raw enum int (which is what "Black Market 3" used to mean - a real bug that
# made purchased parts basically unrecognizable in the spare-parts list).
const SLOT_DISPLAY_NAMES = {
	HexTile.BodySlot.TORSO: "Main Chassis",
	HexTile.BodySlot.ARM_L: "Left Arm",
	HexTile.BodySlot.ARM_R: "Right Arm",
	HexTile.BodySlot.LEG_L: "Left Leg",
	HexTile.BodySlot.LEG_R: "Right Leg",
	HexTile.BodySlot.HEAD: "Sensor Head",
	HexTile.BodySlot.BACKPACK: "Backpack",
	HexTile.BodySlot.DRONE: "Drone",
}

static func _slot_display_name(slot) -> String:
	return SLOT_DISPLAY_NAMES.get(slot, "Slot %s" % str(slot))

func _open_black_market():
	if not garage_market:
		garage_market = GarageMarket.new(self)
	garage_market.open_popup()

func _open_shop():
	if not garage_shop:
		garage_shop = GarageShop.new(self)
	garage_shop.open_popup()

func _on_sell_all(max_rarity: int):
	if not garage_market:
		garage_market = GarageMarket.new(self)
	garage_market.sell_all(max_rarity)

func _add_to_inventory(tile: HexTile):
	if not garage_inventory_panel:
		garage_inventory_panel = GarageInventoryPanel.new(self)
	garage_inventory_panel.add_to_inventory(tile)

func _on_tooltip_requested(tile: HexTile, screen_pos: Vector2):
	if not garage_inventory_panel:
		garage_inventory_panel = GarageInventoryPanel.new(self)
	garage_inventory_panel.on_tooltip_requested(tile, screen_pos)
	_update_mount_preview(tile, screen_pos)

func _on_tooltip_cleared():
	if not garage_inventory_panel:
		garage_inventory_panel = GarageInventoryPanel.new(self)
	garage_inventory_panel.on_tooltip_cleared()
	if mount_preview:
		mount_preview.hide_preview()

# --- weapon-mount preview (see MountPreviewPopup.gd) -------------------
# Hovering a Weapon Mount shows the pattern/damage/element that mount will
# produce with the grid AS CURRENTLY WIRED - the sim is re-run on demand
# when edits dirtied it, so the preview always tells the truth.
var mount_preview = null
# Debounced, not run on every single hover-hex-transition: a fast mouse
# sweep across several tiles used to trigger a full _recalculate_grid()
# each time, which is the actual hover freeze (Utility-SOC: "there is a
# brief freeze whenever I hover a mount now"). 150ms is well under human
# hover-dwell time but comfortably collapses a fast sweep into one recalc.
const MOUNT_PREVIEW_DEBOUNCE_MS = 150
var _mount_preview_next_recalc_ms: int = 0

func _update_mount_preview(tile: HexTile, screen_pos: Vector2):
	if tile == null or tile.tile_type != "Weapon Mount":
		if mount_preview:
			mount_preview.hide_preview()
		return
	if not mount_preview:
		mount_preview = load("res://scripts/ui/MountPreviewPopup.gd").new()
		add_child(mount_preview)
	var entries: Array = []
	var fire_rate = 0.25
	var main = get_parent()
	if main and main.get("player") != null:
		var p = main.player
		var now_ms = Time.get_ticks_msec()
		if now_ms >= _mount_preview_next_recalc_ms:
			_mount_preview_next_recalc_ms = now_ms + MOUNT_PREVIEW_DEBOUNCE_MS
			# is_grid_dirty-gated, matching every other _recalculate_grid()
			# caller (Mech._shoot(), GarageTestRange._populate_mounts) -
			# this used to recompute the FULL multi-component energy
			# simulation (up to 7 components, each up to a 1000-step packet
			# routing loop) unconditionally on every debounce tick while the
			# mouse just swept across an unedited grid. The debounce alone
			# only slowed the repeat rate; it never stopped the redundant
			# recompute of the exact same inputs/outputs. The Test Range
			# already gives real, live per-mount damage numbers, so there's
			# nothing this preview needs a fresh recalc for except an actual
			# loadout edit.
			if p.is_grid_dirty:
				p._recalculate_grid()
		fire_rate = p.fire_rate
		for d in p.precalculated_weapons:
			if d.mount == tile:
				entries.append(d)
	mount_preview.show_for(tile, entries, fire_rate, screen_pos)

func _on_tile_clicked(tile: HexTile):
	# Packet Inspector is opt-in (see sim_inspect_toggle) - playtest report:
	# gating this purely on "the scrubber is visible" meant ANY click on
	# ANY tile, forever after the first Simulate press that run, opened the
	# inspector instead of the edit popup ("I cannot edit splitters
	# directions anymore" - the scrubber stays visible on purpose so you can
	# review a finished run, but that must never silently disable editing).
	# Default OFF so normal editing is always the default click behavior;
	# the toggle only appears once the scrubber itself is visible.
	if sim_inspect_toggle and sim_inspect_toggle.button_pressed:
		if not garage_packet_inspector:
			garage_packet_inspector = GaragePacketInspector.new(self)
		garage_packet_inspector.on_tile_clicked(tile)
		return
	if not garage_tile_config_popup:
		garage_tile_config_popup = GarageTileConfigPopup.new(self)
	garage_tile_config_popup.on_tile_clicked(tile)

# Scrubber drag handler - only re-seeks on a genuine user drag (see
# _scrubber_syncing's field comment). Dragging mid-live-play stops the
# auto-play timer loop (same as pressing Stop) so the drag isn't fighting
# the next 0.5s auto-advance.
func _on_sim_scrubber_changed(value: float):
	if _scrubber_syncing or not simulation_runner:
		return
	if is_simulating:
		is_simulating = false
		if sim_button: sim_button.text = "Simulate Energy Flow"
	simulation_runner.seek_to_step(int(round(value)))

# Any Mythic-mode change alters the precalculated grid state - make sure
# the mech rebuilds it before the next shot.
func _mark_player_grid_dirty():
	var main = get_parent()
	if main and main.get("player") != null:
		main.player.is_grid_dirty = true
	# Any real build edit also invalidates the silent-snapshot cache (see
	# GarageSimulationRunner._snapshot_cache) - cleared wholesale, not
	# per-component, since a torso edit changes what every PERIPHERAL's
	# snapshot would receive too.
	if simulation_runner:
		simulation_runner.invalidate_snapshot_cache()

# Fire-and-forget notification to TutorialManager, if one exists (it may
# not - only present during the first-run onboarding flow). Kept as a tiny
# shared helper so every call site is one line instead of a repeated
# get_first_node_in_group + null-check.
func _tutorial_notify(event: String):
	var tm = get_tree().get_first_node_in_group("tutorial_manager")
	if tm:
		tm.notify(event)

func _on_simulate_pressed():
	if not simulation_runner:
		simulation_runner = GarageSimulationRunner.new(self)
	simulation_runner.run_simulation()



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
		_mark_player_grid_dirty() # auto-equip rewrites the whole grid - a real edit
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

	# Clearing tiles invalidates any Timeline Scrubber snapshot for this
	# grid the same way switching tabs does (see _on_tab_changed).
	if sim_scrubber:
		sim_scrubber.visible = false
	if sim_inspect_toggle:
		sim_inspect_toggle.visible = false

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
		_mark_player_grid_dirty() # mass removal - a real edit
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
	var rarity_names = ["Common", "Uncommon", "Rare", "Legendary", "Mythic"]
	for item in compatible:
		var name_str = "[%s] %s" % [_slot_display_name(item.comp.slot_type), item.comp.component_name]
		if item.comp.rarity >= 0: 
			var r_name = rarity_names[item.comp.rarity] if item.comp.rarity < rarity_names.size() else str(item.comp.rarity)
			name_str += " (%s)" % r_name
		var tiles = item.comp.hex_grid.get_all_tiles().size() if item.comp.hex_grid else 0
		name_str += " [%d tiles]" % tiles
		if item.comp.infusion_level > 0: name_str += " [+%d XP]" % item.comp.infusion_level
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
	var rarity_names = ["Common", "Uncommon", "Rare", "Legendary", "Mythic"]
	for i in range(main.player_component_inventory.size()):
		var comp = main.player_component_inventory[i]
		var name_str = "[%s] %s" % [_slot_display_name(comp.slot_type), comp.component_name]
		if comp.rarity >= 0: 
			var r_name = rarity_names[comp.rarity] if comp.rarity < rarity_names.size() else str(comp.rarity)
			name_str += " (%s)" % r_name
		var tiles = comp.hex_grid.get_all_tiles().size() if comp.hex_grid else 0
		name_str += " [%d tiles]" % tiles
		if comp.infusion_level > 0: name_str += " [+%d XP]" % comp.infusion_level
		popup.add_item("Salvage " + name_str, i)
		
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
			_show_warning("Salvaged %s! +%d XP to %s" % [junk.component_name, xp_gain, active_component.component_name])
		else:
			_show_warning("ComponentEquipment missing Infusion Logic!")
			
		_refresh_inventory_ui()
		popup.queue_free()
	)
	add_child(popup)
	popup.popup_centered(Vector2(300, 400))

func _on_codex_pressed():
	if not synergy_codex_popup:
		synergy_codex_popup = SynergyCodexPopup.new(self)
	synergy_codex_popup.show_popup()

func _show_warning(msg: String):
	var dialog = AcceptDialog.new()
	dialog.dialog_text = msg
	add_child(dialog)
	dialog.popup_centered()

# Drone template (see GarageUIBuilder's Drone->All button): clone the open
# drone tab's loadout onto every other installed bay - serialize round trip
# so each bay owns an independent copy, not a shared reference.
func _on_drone_copy_all_pressed():
	var meta = component_tabs.get_tab_metadata(component_tabs.current_tab)
	if not (meta is Dictionary and meta.get("slot") == HexTile.BodySlot.DRONE):
		_show_warning("Open a Drone tab first - that drone's loadout gets copied to every other bay.")
		return
	var src_bay = meta.get("bay")
	if not src_bay or not is_instance_valid(src_bay):
		return
	var source = src_bay.get_or_build_loadout()
	var copied = 0
	for bay in _find_all_drone_bay_tiles():
		if bay == src_bay:
			continue
		bay.drone_loadout = SaveManager._deserialize_component(SaveManager._serialize_component(source))
		copied += 1
	_mark_player_grid_dirty()
	if copied == 0:
		_show_warning("No other Drone Bays installed to copy to.")
	else:
		_show_warning("Copied this drone's loadout to %d other bay(s)." % copied)

# --- Blueprint Cards ---------------------------------------------------------
# Lists every card PNG in user://champion_cards/ and applies the chosen one
# as a BLUEPRINT: the build is reassembled onto the player's mech using only
# owned parts (see ChampionCard.assemble_blueprint); anything unowned or
# unfittable becomes a shopping list. Same PNGs the Traveling Champion
# system fights - one card, two uses, per design ruling.
func _on_blueprint_pressed():
	var ChampionCardScript = load("res://scripts/pvp/ChampionCard.gd")
	var dir = DirAccess.open(ChampionCardScript.CARDS_DIR)
	var cards: Array = []
	if dir:
		for file in dir.get_files():
			if not file.ends_with(".png"):
				continue
			var f = FileAccess.open(ChampionCardScript.CARDS_DIR.path_join(file), FileAccess.READ)
			if not f:
				continue
			var payload = ChampionCardScript.extract_payload(f.get_buffer(f.get_length()))
			f.close()
			if not payload.is_empty():
				cards.append(payload)
	if cards.is_empty():
		_show_warning("No card PNGs found in %s.\nDrop a friend's Champion Card there (or export your own from the War Room)." % ProjectSettings.globalize_path(ChampionCardScript.CARDS_DIR))
		return

	var popup = PopupPanel.new()
	var vbox = VBoxContainer.new()
	popup.add_child(vbox)
	var title = Label.new()
	title.text = "Apply a Blueprint (uses only parts you own)"
	vbox.add_child(title)
	for payload in cards:
		var btn = Button.new()
		btn.text = "%s  (wave record %d)" % [payload.get("pilot_name", "Unknown"), int(payload.get("max_wave", 0))]
		btn.pressed.connect(func():
			popup.hide()
			_apply_blueprint(payload)
		)
		vbox.add_child(btn)

	# Demo builds (design ruling: ready-built pixbots for new players):
	# bundled full kits generated by the AutoEquipSolver - applying one
	# GRANTS the whole loadout; your current parts move to the component
	# inventory, nothing is lost. See scripts/debug/DemoBuildGenerator.gd.
	var demo_count = 0
	var demo_dir = DirAccess.open("res://config/demo_builds")
	if demo_dir:
		var demo_title = Label.new()
		demo_title.text = "\nDemo builds (full ready-made kit - swaps your parts to inventory)"
		vbox.add_child(demo_title)
		for file in demo_dir.get_files():
			if not file.ends_with(".json"):
				continue
			var f = FileAccess.open("res://config/demo_builds/" + file, FileAccess.READ)
			if not f:
				continue
			var data = JSON.parse_string(f.get_as_text())
			f.close()
			if not (data is Dictionary and data.has("components")):
				continue
			demo_count += 1
			var demo_btn = Button.new()
			demo_btn.text = "DEMO: %s" % data.get("demo_name", file)
			demo_btn.pressed.connect(func():
				popup.hide()
				_apply_demo_build(data)
			)
			vbox.add_child(demo_btn)

	add_child(popup)
	popup.popup_centered(Vector2(360, 120 + (cards.size() + demo_count) * 40))
	popup.popup_hide.connect(func(): popup.queue_free())

func _apply_demo_build(data: Dictionary):
	var main = get_parent()
	if not main or main.get("player") == null:
		return
	var player = main.player
	# Old parts go to the component inventory - a demo kit is a leg up,
	# never a downgrade that eats your gear.
	for slot in player.components.keys().duplicate():
		var old = player.unequip_component(slot)
		if old and main.get("player_component_inventory") != null:
			main.player_component_inventory.append(old)
	for slot_str in data["components"]:
		var comp = SaveManager._deserialize_component(data["components"][slot_str])
		if comp:
			player.equip_component(comp)
	player.is_grid_dirty = true
	player._recalculate_grid()
	_refresh_component_ui()
	_refresh_inventory_ui()
	_show_warning("Demo kit '%s' equipped!\nYour previous parts are in the component inventory (Swap Component to get them back)." % data.get("demo_name", "?"))

# Test Range (see GarageTestRange.gd): live-fire popup with its own
# physics world - the garage's paused tree doesn't apply inside it.
func _on_test_range_pressed():
	var main = get_parent()
	if not main or main.get("player") == null:
		_show_warning("No active mech to test-fire.")
		return
	var range_popup = load("res://scripts/ui/GarageTestRange.gd").new()
	range_popup.setup(main.player)
	add_child(range_popup)
	range_popup.popup_centered(Vector2(940, 540))

# Same reuse-a-single-instance pattern as MainMenu._on_war_room_pressed -
# toggles an existing instance back open instead of stacking duplicates.
# Parented to the Garage (not Main) so it still exists/toggles correctly
# even if the Garage itself is what's currently on screen with Main paused
# underneath.
func _on_war_room_pressed():
	var existing = get_node_or_null("WarRoomInstance")
	if existing:
		existing._toggle()
		return
	var wr = load("res://scripts/ui/WarRoomMenu.gd").new()
	wr.name = "WarRoomInstance"
	add_child(wr)
	wr._toggle()

# --- Named build/part slots ----------------------------------------------
# Unlimited named save slots for full builds and single parts (playtest
# ruling: "a wider variety of builds ... not just 3 slots"). One popup
# manager for both: a save-as row on top, then a Load/Delete row per saved
# slot. Files live in user://loadouts/ via SaveManager; the old numbered
# quick-slots still appear in the Builds list as "Quick Slot N".
func _on_builds_pressed():
	_open_slot_manager(true)

func _on_parts_pressed():
	if not active_component:
		_show_warning("Open a component tab first - part slots save whichever part is on screen.")
		return
	_open_slot_manager(false)

func _open_slot_manager(full_build: bool):
	var main = get_parent()
	if not main or main.get("player") == null:
		return
	var slot_type: int = -1 if full_build else active_component.slot_type

	var popup = PopupPanel.new()
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(420, 0)
	popup.add_child(vbox)

	var title = Label.new()
	if full_build:
		title.text = "Full builds - loading replaces your WHOLE mech (no refunds)"
	else:
		title.text = "Saved parts for this slot type - loading replaces ONLY this tab's part"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(title)

	var save_row = HBoxContainer.new()
	vbox.add_child(save_row)
	var name_edit = LineEdit.new()
	name_edit.placeholder_text = "New slot name..."
	if not full_build:
		name_edit.text = active_component.component_name
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(name_edit)
	var save_btn = Button.new()
	save_btn.text = "Save as"
	save_row.add_child(save_btn)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 280)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	var list_vbox = VBoxContainer.new()
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_vbox)

	# A lambda can't reference itself by name in GDScript (the capture is
	# taken before the assignment completes) - route the delete-refresh
	# through a one-slot array filled in after creation.
	var rebuild_holder: Array = [null]
	var rebuild = func():
		for child in list_vbox.get_children():
			child.queue_free()
		var entries = SaveManager.list_named_loadouts() if full_build else SaveManager.list_named_components(slot_type)
		if entries.is_empty():
			var empty = Label.new()
			empty.text = "(nothing saved yet)"
			list_vbox.add_child(empty)
		for entry in entries:
			var row = HBoxContainer.new()
			list_vbox.add_child(row)
			var lbl = Label.new()
			lbl.text = str(entry.name)
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(lbl)
			var load_btn = Button.new()
			load_btn.text = "Load"
			load_btn.pressed.connect(func():
				popup.hide()
				if full_build:
					if SaveManager.load_loadout_file(entry.path, main.player):
						_refresh_component_ui()
						_refresh_inventory_ui()
						_show_warning("Build '%s' loaded." % entry.name)
				else:
					var loaded = SaveManager.load_named_component(entry.path, slot_type)
					if not loaded:
						_show_warning("Couldn't load '%s' - wrong slot type or corrupt file." % entry.name)
						return
					# Same replace semantics as the old numbered part slots:
					# swap just this component, outgoing part is not refunded.
					var old = main.player.unequip_component(slot_type)
					if old:
						old.queue_free()
					main.player.equip_component(loaded)
					_refresh_component_ui()
					_on_tab_changed(component_tabs.current_tab)
					_show_warning("Part '%s' loaded onto this slot." % entry.name)
			)
			row.add_child(load_btn)
			var del_btn = Button.new()
			del_btn.text = "Delete"
			del_btn.modulate = Color(1.0, 0.6, 0.6)
			del_btn.pressed.connect(func():
				SaveManager.delete_named_loadout(entry.path)
				rebuild_holder[0].call()
			)
			row.add_child(del_btn)

	rebuild_holder[0] = rebuild
	rebuild.call()

	save_btn.pressed.connect(func():
		var slot_name = name_edit.text.strip_edges()
		if slot_name == "":
			return
		var ok: bool
		if full_build:
			ok = SaveManager.save_named_loadout(slot_name, main.player)
		else:
			ok = SaveManager.save_named_component(slot_name, active_component)
		if ok:
			rebuild.call()
		else:
			_show_warning("Couldn't write the save file for '%s'." % slot_name)
	)
	name_edit.text_submitted.connect(func(_t): save_btn.pressed.emit())

	add_child(popup)
	popup.popup_centered(Vector2(440, 400))
	popup.popup_hide.connect(func(): popup.queue_free())

func _apply_blueprint(payload: Dictionary):
	var main = get_parent()
	if not main or main.get("player") == null:
		_show_warning("No active mech to apply the blueprint to.")
		return
	var ChampionCardScript = load("res://scripts/pvp/ChampionCard.gd")
	var result = ChampionCardScript.assemble_blueprint(payload, main.player, inventory)
	_mark_player_grid_dirty()
	_refresh_inventory_ui()
	if grid_renderer:
		grid_renderer.queue_redraw()
	var msg = "Blueprint '%s': placed %d of %d tiles from your stock." % [payload.get("pilot_name", "?"), result.placed, result.total]
	if not result.missing.is_empty():
		msg += "\n\nShopping list:"
		var counts = {}
		for m in result.missing:
			counts[m] = counts.get(m, 0) + 1
		for m in counts:
			msg += "\n  %dx %s" % [counts[m], m]
	_show_warning(msg)
