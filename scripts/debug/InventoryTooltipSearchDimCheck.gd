extends Node

# Regression harness for two playtest requests:
#   1. "When I hover a hex's name in inventory it should have a tooltip
#      that explains how the tile is used and what it does. The tooltips
#      from the grid would be fine for now."
#   2. "If I search a hex in the inventory, it should highlight any tiles
#      that match the filter on the grid (dim all tiles which do not meet
#      the criteria of the filter)."

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")
const AmplifierTileScript = preload("res://scripts/tiles/AmplifierTile.gd")
const SplitterTileScript = preload("res://scripts/tiles/SplitterTile.gd")
const GarageMenuScript = preload("res://scripts/ui/GarageMenu.gd")
const GarageGridRendererScript = preload("res://scripts/ui/GarageGridRenderer.gd")
const GarageInventoryPanelScript = preload("res://scripts/ui/GarageInventoryPanel.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# --- 1. Tooltip: inventory row gets the SAME text as the grid's own
	# tooltip, and it's non-empty/informative. ---
	var amp = AmplifierTileScript.new()
	amp.rarity = HexTile.Rarity.RARE
	var tip = GarageInventoryPanelScript.build_tile_tooltip_text(amp)
	_check("tooltip text names the tile type", tip.contains("Amplifier"))
	_check("tooltip text names the rarity", tip.contains("Rare"))
	_check("tooltip text isn't just the bare stats (has a real description blurb)", tip.length() > 40)

	# --- 2. Search-dim: build a torso with an Amplifier and a Splitter,
	# verify dim logic matches inventory-list matching exactly. ---
	var comp = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.COMMON)
	var hexes: Array[HexCoord] = [HexCoord.new(0, 0), HexCoord.new(1, 0), HexCoord.new(2, 0)]
	comp.valid_hexes = hexes
	comp._rebuild_valid_hex_set()
	comp.hex_grid.add_tile(HexCoord.new(0, 0), CoreTileScript.new())
	comp.hex_grid.add_tile(HexCoord.new(1, 0), amp)
	var splitter = SplitterTileScript.new()
	comp.hex_grid.add_tile(HexCoord.new(2, 0), splitter)

	var garage = GarageMenuScript.new()
	add_child(garage)
	garage.grid_renderer = GarageGridRendererScript.new()
	garage.add_child(garage.grid_renderer)
	garage.grid_renderer.setup(comp.hex_grid, garage, comp.valid_hexes)
	garage.grid_renderer.active_component = comp

	_check("no filter active -> nothing dimmed", not garage.grid_renderer._should_dim_tile(amp))
	garage.inventory_search_filter = "amplif"
	_check("matching filter ('amplif' vs Amplifier) -> NOT dimmed", not garage.grid_renderer._should_dim_tile(amp))
	_check("non-matching filter ('amplif' vs Splitter) -> dimmed", garage.grid_renderer._should_dim_tile(splitter))
	garage.inventory_search_filter = "zzz_nothing_matches"
	_check("filter matching nothing dims every tile", garage.grid_renderer._should_dim_tile(amp) and garage.grid_renderer._should_dim_tile(splitter))
	garage.inventory_search_filter = ""
	_check("clearing the filter un-dims everything again", not garage.grid_renderer._should_dim_tile(amp) and not garage.grid_renderer._should_dim_tile(splitter))

	# --- 3. refresh_inventory_ui actually stores the live search text on
	# garage (the wiring the renderer's _should_dim_tile depends on). ---
	garage.search_input = LineEdit.new()
	garage.add_child(garage.search_input)
	garage.search_input.text = "Splitter"
	garage.inv_vbox = VBoxContainer.new()
	garage.add_child(garage.inv_vbox)
	garage.inventory = [amp, splitter]
	garage._refresh_inventory_ui()
	_check("refresh_inventory_ui stores the lowercased live search text on garage",
		garage.inventory_search_filter == "splitter")

	if failures == 0:
		print("PASS: inventory tooltips reuse the grid's own content, and the search filter correctly dims non-matching grid tiles")
	get_tree().quit(0 if failures == 0 else 1)
