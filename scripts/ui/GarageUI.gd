class_name GarageUI
extends Control

var hex_grid: Dictionary = {} # HexCoord -> HexTile
var inventory: Array[HexTile] = []

var grid_container: Control
var inventory_list: ItemList
var simulate_button: Button

func _ready():
	# Make it full screen
	set_anchors_preset(PRESET_FULL_RECT)
	
	# Split screen: Left side for Grid, Right side for Inventory
	var h_split = HSplitContainer.new()
	h_split.set_anchors_preset(PRESET_FULL_RECT)
	h_split.split_offset = 800 # 800px for grid, rest for inventory
	add_child(h_split)
	
	# Left side: The Hex Grid View
	grid_container = Control.new()
	h_split.add_child(grid_container)
	
	# Right side: Panel containing Inventory and Controls
	var right_panel = Panel.new()
	h_split.add_child(right_panel)
	
	var v_box = VBoxContainer.new()
	v_box.set_anchors_preset(PRESET_FULL_RECT)
	v_box.add_theme_constant_override("margin", 10)
	right_panel.add_child(v_box)
	
	var title = Label.new()
	title.text = "Component Inventory"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v_box.add_child(title)
	
	inventory_list = ItemList.new()
	inventory_list.size_flags_vertical = SIZE_EXPAND_FILL
	v_box.add_child(inventory_list)
	
	simulate_button = Button.new()
	simulate_button.text = "Simulate Energy Flow"
	simulate_button.pressed.connect(_on_simulate_pressed)
	v_box.add_child(simulate_button)
	
	# Populate some dummy inventory
	_populate_dummy_inventory()

func _populate_dummy_inventory():
	var amp = preHexTile.new("Amplifier", HexTile.TileCategory.PROCESSOR)
	var split = preHexTile.new("Splitter", HexTile.TileCategory.ROUTER)
	
	inventory.append(amp)
	inventory.append(split)
	
	for tile in inventory:
		inventory_list.add_item(tile.tile_type)

func _on_simulate_pressed():
	print("Simulation Started!")
	# Here you would instantiate an EnergyPacket and pass it through the hex_grid
	# using the HexTile process_energy() functions.
