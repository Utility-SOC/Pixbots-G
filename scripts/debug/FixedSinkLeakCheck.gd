extends Node

# Regression harness for the fixed_sinks inventory leak (live save audit:
# the player's actual save file had grown to 71,490 loose inventory tiles,
# ~76% of them structural tiles - Energy Intake, Weapon Mount, Torso
# Return, peripheral Links - that should never leave a component's own
# grid. Root cause: three Garage UI tile-removal paths (Clear Grid, Salvage
# for XP, right-click removal) only ever protected a TORSO's own (0,0)
# Core hex, never any component's other fixed_sinks - unlike
# AutoEquipSolver's own board-clearing step, which already excludes
# fixed_sinks correctly. Fix: ComponentEquipment.is_fixed_sink() is now
# consulted by all three.

const GarageMenuScript = preload("res://scripts/ui/GarageMenu.gd")
const GarageGridRendererScript = preload("res://scripts/ui/GarageGridRenderer.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const SplitterTileScript = preload("res://scripts/tiles/SplitterTile.gd")

# Mimics Main.gd's own field names/shape (get_tree().current_scene lookup,
# see _on_infuse_component_pressed's "player_component_inventory" check) -
# same trick PaperdollPaintColorCheck.gd/SponsorPopupCheck.gd already use.
var player_component_inventory: Array = []
var player: Node = null

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _make_filler_arm() -> Node:
	var arm = ComponentEquipmentScript.create_starter_arm(false, "", HexTile.Rarity.COMMON)
	# One ordinary player-placeable filler tile, at a valid hex that isn't
	# already a fixed_sink - the contrast case that MUST still get properly
	# returned to inventory (proving the fix doesn't over-protect).
	var filler_h = null
	for h in arm.valid_hexes:
		var is_sink = false
		for s in arm.fixed_sinks:
			if s.q == h.q and s.r == h.r:
				is_sink = true
				break
		if not is_sink:
			filler_h = h
			break
	var filler = SplitterTileScript.new()
	filler.rarity = HexTile.Rarity.COMMON
	arm.hex_grid.add_tile(filler_h, filler)
	return arm

func _ready():
	var world = Node2D.new()
	add_child(world)

	# --- is_fixed_sink() itself ---
	var probe_arm = _make_filler_arm()
	_check("is_fixed_sink() true for the Energy Intake coord", probe_arm.is_fixed_sink(probe_arm.fixed_sinks[0]))
	_check("is_fixed_sink() true for the Weapon Mount coord", probe_arm.is_fixed_sink(probe_arm.fixed_sinks[1]))
	_check("is_fixed_sink() false for an arbitrary non-sink coord", not probe_arm.is_fixed_sink(HexCoord.new(99, 99)))

	# --- Clear Grid ---
	var garage_a = GarageMenuScript.new()
	world.add_child(garage_a)
	var arm_a = _make_filler_arm()
	world.add_child(arm_a)
	garage_a.active_component = arm_a
	garage_a.mech_components = {HexTile.BodySlot.ARM_R: arm_a}
	garage_a.grid_renderer.setup(arm_a.hex_grid, garage_a, arm_a.valid_hexes)
	garage_a.inventory = []
	garage_a._on_clear_grid_pressed()

	var inv_a_types = []
	for t in garage_a.inventory:
		inv_a_types.append(t.tile_type)
	_check("Clear Grid does NOT inventory the Energy Intake", not inv_a_types.has("Energy Intake"))
	_check("Clear Grid does NOT inventory the Weapon Mount", not inv_a_types.has("Weapon Mount"))
	_check("Clear Grid DOES inventory the ordinary filler Splitter (no over-protection)", inv_a_types.has("Splitter"))
	_check("Energy Intake is still physically on the grid after Clear Grid", arm_a.hex_grid.has_tile(arm_a.fixed_sinks[0]))
	_check("Weapon Mount is still physically on the grid after Clear Grid", arm_a.hex_grid.has_tile(arm_a.fixed_sinks[1]))

	# --- Salvage for XP ---
	player_component_inventory = [_make_filler_arm()]
	var junk_ref = player_component_inventory[0]
	var garage_b = GarageMenuScript.new()
	world.add_child(garage_b)
	garage_b.inventory = []
	# A real (unrelated) active_component - _on_infuse_component_pressed's
	# XP-award tail calls active_component.add_infusion_xp(), so this can't
	# be null the way Clear Grid's test double could be.
	garage_b.active_component = _make_filler_arm()
	garage_b._on_infuse_component_pressed()
	# Simulate picking the one item in the popup (id 0) exactly like a real
	# click would - search from garage_b itself (its own add_child(popup)
	# target), not get_tree().current_scene, in case Window-derived Popup
	# nodes don't surface the same way through a from-the-root search.
	var popups = []
	_collect_popup_menus(garage_b, popups)
	_check("Salvage popup was actually built", popups.size() > 0)
	if popups.size() > 0:
		popups[0].id_pressed.emit(0)

	var inv_b_types = []
	for t in garage_b.inventory:
		inv_b_types.append(t.tile_type)
	_check("Salvage does NOT inventory the dismantled Energy Intake", not inv_b_types.has("Energy Intake"))
	_check("Salvage does NOT inventory the dismantled Weapon Mount", not inv_b_types.has("Weapon Mount"))
	_check("Salvage DOES inventory the dismantled filler Splitter", inv_b_types.has("Splitter"))
	_check("the junk component was actually removed from player_component_inventory", not player_component_inventory.has(junk_ref))

	# --- Right-click removal ---
	var arm_c = _make_filler_arm()
	world.add_child(arm_c)
	var renderer = GarageGridRendererScript.new()
	world.add_child(renderer)
	renderer.hex_grid = arm_c.hex_grid
	renderer.active_component = arm_c
	var garage_c = GarageMenuScript.new()
	world.add_child(garage_c)
	garage_c.inventory = []
	renderer.menu_parent = garage_c

	var mount_h = arm_c.fixed_sinks[1] # Weapon Mount
	renderer.hovered_hex = mount_h
	_simulate_right_click(renderer)

	var inv_c_types = []
	for t in garage_c.inventory:
		inv_c_types.append(t.tile_type)
	_check("right-click removal does NOT inventory the Weapon Mount", not inv_c_types.has("Weapon Mount"))
	_check("Weapon Mount is still physically on the grid after the attempted right-click removal", arm_c.hex_grid.has_tile(mount_h))

	if failures == 0:
		print("PASS: Clear Grid, Salvage for XP, and right-click removal all correctly protect a component's fixed_sinks now, while still returning ordinary tiles to inventory")
	get_tree().quit(0 if failures == 0 else 1)

func _collect_popup_menus(node: Node, out: Array):
	if node is PopupMenu:
		out.append(node)
	for c in node.get_children():
		_collect_popup_menus(c, out)

# GarageGridRenderer has no dedicated single-call removal function - the
# real path is _gui_input's right-click-release branch, gated on the
# release landing within 5px of the press (not a drag/pan). Drives that
# exact sequence directly rather than duplicating its logic here.
func _simulate_right_click(renderer: Node):
	var press = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	press.position = Vector2(100, 100)
	renderer._gui_input(press)

	var release = InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	release.position = Vector2(100, 100) # same spot - within the 5px "not a pan" threshold
	renderer._gui_input(release)
