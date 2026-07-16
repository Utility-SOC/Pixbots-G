extends Node

# Regression harness for the playtest fixes to the Timeline Scrubber/Packet
# Inspector session:
#   1. Tile clicks must default to the normal edit-config popup even after
#      a simulation has run - Inspect mode is opt-in, off by default, and
#      resets to off on every fresh Simulate press ("I cannot edit
#      splitters directions anymore").
#   2. Turning Inspect ON routes clicks to the Packet Inspector instead.
#   3. Fill-paint template stamping: painting new Splitters starting from
#      an existing configured one on the grid gives every new copy the
#      SAME active_faces/output_ratios, not each one's own random roll
#      ("if I hover over a splitter... it will match the first splitter").

const GarageMenuScript = preload("res://scripts/ui/GarageMenu.gd")
const GarageSimulationRunnerScript = preload("res://scripts/ui/GarageSimulationRunner.gd")
const GarageInventoryPanelScript = preload("res://scripts/ui/GarageInventoryPanel.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")
const SplitterTileScript = preload("res://scripts/tiles/SplitterTile.gd")

func _ready():
	var failures = 0
	var world = Node2D.new()
	add_child(world)

	var garage = GarageMenuScript.new()
	world.add_child(garage)

	var comp = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.RARE)
	world.add_child(comp)
	comp.generate_shape() # populates valid_hexes/can_place_tile - _drop_fill_line gates on this, unlike raw hex_grid.add_tile
	var core = CoreTileScript.new()
	core.rarity = HexTile.Rarity.RARE
	comp.hex_grid.add_tile(HexCoord.new(0, 0), core)
	# Origin splitter: a distinctive, non-default config to detect a copy.
	var origin = SplitterTileScript.new()
	origin.rarity = HexTile.Rarity.MYTHIC
	var origin_faces: Array[int] = [0, 2, 4]
	origin.active_faces = origin_faces
	origin.adjust_ratio_weight(0, 5.0)
	comp.hex_grid.add_tile(HexCoord.new(1, 0), origin)

	garage.active_component = comp
	garage.mech_components = {HexTile.BodySlot.TORSO: comp}
	garage.grid_renderer.setup(comp.hex_grid, garage, comp.valid_hexes)

	# --- 1 & 2: click routing before/after a sim run, and toggle reset -----
	garage.simulation_runner = GarageSimulationRunnerScript.new(garage)
	garage.simulation_runner.run_simulation()
	garage.is_simulating = false

	if not garage.sim_inspect_toggle.visible or garage.sim_inspect_toggle.button_pressed:
		push_error("FAIL: inspect toggle should appear OFF right after a fresh Simulate press")
		failures += 1
	else:
		print("1) inspect toggle visible and OFF immediately after Simulate")

	garage._on_tile_clicked(origin)
	if garage.garage_tile_config_popup == null:
		push_error("FAIL: default click after simulating didn't open the config popup")
		failures += 1
	elif garage.garage_packet_inspector != null:
		push_error("FAIL: default click after simulating opened the Packet Inspector instead of the config popup")
		failures += 1
	else:
		print("2) default click after Simulate opens the EDIT popup, not the inspector - regression fixed")

	garage.sim_inspect_toggle.button_pressed = true
	garage._on_tile_clicked(origin)
	if garage.garage_packet_inspector == null:
		push_error("FAIL: click with Inspect ON didn't open the Packet Inspector")
		failures += 1
	else:
		print("3) click with Inspect explicitly ON opens the Packet Inspector")

	# Re-simulating must reset the toggle back to OFF - never a sticky mode.
	garage.simulation_runner.run_simulation()
	garage.is_simulating = false
	if garage.sim_inspect_toggle.button_pressed:
		push_error("FAIL: Inspect toggle carried over ON across a fresh Simulate press")
		failures += 1
	else:
		print("4) Inspect toggle resets to OFF on every fresh Simulate press")

	# --- 5: fill-paint template stamping ------------------------------------
	var inv_panel = GarageInventoryPanelScript.new(garage)
	var stock: Array[int] = [1, 5] # SplitterTile's own default active_faces
	var loose1 = SplitterTileScript.new()
	loose1.rarity = HexTile.Rarity.MYTHIC
	loose1.active_faces = stock.duplicate()
	var loose2 = SplitterTileScript.new()
	loose2.rarity = HexTile.Rarity.MYTHIC
	loose2.active_faces = stock.duplicate()
	garage.inventory = [loose1, loose2]
	garage.dragged_tile = loose1
	garage.fill_template_tile = origin # simulating "the hover paused on the existing origin splitter first"
	garage.grid_renderer.fill_preview_hexes = [HexCoord.new(1, 0), HexCoord.new(2, 0), HexCoord.new(3, 0)]

	inv_panel._drop_fill_line()

	var placed_a = comp.hex_grid.get_tile(HexCoord.new(2, 0))
	var placed_b = comp.hex_grid.get_tile(HexCoord.new(3, 0))
	var faces_match = placed_a != null and placed_b != null \
		and placed_a.active_faces == origin.active_faces \
		and placed_b.active_faces == origin.active_faces \
		and placed_a.get_ratio_weight(0) == origin.get_ratio_weight(0) \
		and placed_b.get_ratio_weight(0) == origin.get_ratio_weight(0)
	if not faces_match:
		push_error("FAIL: fill-painted splitters didn't inherit the origin's config (origin=%s a=%s b=%s)" % [
			origin.active_faces, placed_a.active_faces if placed_a else "?", placed_b.active_faces if placed_b else "?"])
		failures += 1
	else:
		print("5) fill-paint from an existing splitter stamps BOTH active_faces and ratio weights onto every new copy")

	# --- 6: without a template (normal drag, no origin hover), tiles keep
	# their own inventory config unchanged - the opt-in must not become the
	# only behavior.
	comp.hex_grid.remove_tile(HexCoord.new(2, 0))
	comp.hex_grid.remove_tile(HexCoord.new(3, 0))
	var loose3 = SplitterTileScript.new()
	loose3.rarity = HexTile.Rarity.MYTHIC
	var own_faces: Array[int] = [1, 3]
	loose3.active_faces = own_faces
	garage.inventory = [loose3]
	garage.dragged_tile = loose3
	garage.fill_template_tile = null
	garage.grid_renderer.fill_preview_hexes = [HexCoord.new(2, 0)]
	inv_panel._drop_fill_line()
	var placed_c = comp.hex_grid.get_tile(HexCoord.new(2, 0))
	if placed_c == null or placed_c.active_faces != own_faces:
		push_error("FAIL: without a template, a placed splitter's own config got clobbered")
		failures += 1
	else:
		print("6) without hovering an origin first, placed tiles keep their own config (opt-in confirmed)")

	if failures == 0:
		print("PASS: editing regression fixed, inspect mode is opt-in, fill-template stamping works and is opt-in")
	get_tree().quit(0 if failures == 0 else 1)
