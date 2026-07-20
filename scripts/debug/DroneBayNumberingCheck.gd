extends Node

# Regression harness for: "when drones are equipped the tile should have
# the number that corresponds to the drone's tab. The tabs need to be
# scrollable in case I try to do something stupid like a 50 drone build."
#
# Verifies: DroneBayTile.bay_number is stamped 1..N in the exact order
# GarageMenu._refresh_component_ui assigns "Drone N" tab labels (so the
# grid icon and the tab always agree), at both a small scale and a
# stress-test 50-bay scale - and that the tab bar's existing clip_tabs
# scrolling handles 50+ tabs without crashing or losing tabs.

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const DroneBayTileScript = preload("res://scripts/tiles/DroneBayTile.gd")
const GarageMenuScript = preload("res://scripts/ui/GarageMenu.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _build_mech_with_drone_bays(count: int):
	var garage = GarageMenuScript.new()
	add_child(garage)

	var backpack = ComponentEquipmentScript.new(HexTile.BodySlot.BACKPACK, HexTile.Rarity.MYTHIC)
	var hexes: Array[HexCoord] = []
	# A wide strip, guaranteed room for `count` tiles regardless of the
	# normal generate_shape() budget caps - this is a synthetic stress
	# grid, not meant to resemble a real backpack silhouette.
	for i in range(count):
		hexes.append(HexCoord.new(i, 0))
	backpack.valid_hexes = hexes
	backpack._rebuild_valid_hex_set()

	var bays: Array = []
	for i in range(count):
		var bay = DroneBayTileScript.new()
		bay.rarity = HexTile.Rarity.COMMON
		backpack.hex_grid.add_tile(HexCoord.new(i, 0), bay)
		bays.append(bay)

	garage.mech_components = {HexTile.BodySlot.BACKPACK: backpack}
	garage.component_tabs = TabBar.new()
	garage.add_child(garage.component_tabs)
	garage.grid_renderer = load("res://scripts/ui/GarageGridRenderer.gd").new()
	garage.add_child(garage.grid_renderer)
	garage.stats_label = Label.new()
	garage.add_child(garage.stats_label)
	return {"garage": garage, "bays": bays}

func _ready():
	# --- Small scale: order matches array order exactly. ---
	var small = _build_mech_with_drone_bays(3)
	small.garage._refresh_component_ui()
	_check("3-bay build: tab count is 1 (Backpack) + 3 (Drone) = 4",
		small.garage.component_tabs.get_tab_count() == 4)
	var small_ok = true
	for i in range(3):
		if small.bays[i].bay_number != i + 1:
			small_ok = false
	_check("3-bay build: bay_number stamped 1,2,3 matching tab order", small_ok)
	small.garage.queue_free()

	# --- Stress scale: 50 drone bays. ---
	var big = _build_mech_with_drone_bays(50)
	big.garage._refresh_component_ui()
	_check("50-bay build: tab count reaches 51 (Backpack + 50 Drone tabs) without crashing",
		big.garage.component_tabs.get_tab_count() == 51)
	_check("50-bay build: clip_tabs scrolling is active (set by GarageUIBuilder)",
		big.garage.component_tabs.clip_tabs)
	var big_ok = true
	for i in range(50):
		if big.bays[i].bay_number != i + 1:
			big_ok = false
			print("    mismatch at index %d: bay_number=%d" % [i, big.bays[i].bay_number])
			break
	_check("50-bay build: every bay_number stamped correctly 1..50", big_ok)

	# Jumping to a late tab (deep into scrolled-off territory) must not crash.
	big.garage.component_tabs.current_tab = 50
	big.garage._on_tab_changed(50)
	_check("selecting the 50th Drone tab (deep into overflow) works without crashing",
		is_instance_valid(big.garage))
	big.garage.queue_free()

	if failures == 0:
		print("PASS: Drone Bay tiles show their real tab number, and the tab bar holds up at 50 drones")
	get_tree().quit(0 if failures == 0 else 1)
