extends Node

# Regression harness for: "contiguous accumulators should all adopt the
# settings of any other in the contiguous group, so I can set the key and
# autofire stuff once instead of 15 times."
#
# GarageTileConfigPopup._find_contiguous_accumulators() BFS's through hex
# adjacency (not packet routing) starting from a clicked Accumulator,
# collecting every Accumulator tile transitively touching it. Verifies: a
# straight 3-tile chain (A-B-C, where A and C only connect THROUGH B, never
# directly adjacent) all end up in one group; an isolated 4th Accumulator
# elsewhere on the grid is correctly excluded; and the popup's actual
# item_selected callbacks propagate trigger_key/auto_dump_threshold to the
# whole group, not just the clicked tile.

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const AccumulatorTileScript = preload("res://scripts/tiles/AccumulatorTile.gd")
const GarageMenuScript = preload("res://scripts/ui/GarageMenu.gd")
const GarageGridRendererScript = preload("res://scripts/ui/GarageGridRenderer.gd")
const GarageTileConfigPopupScript = preload("res://scripts/ui/GarageTileConfigPopup.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var comp = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.RARE)
	var hexes: Array[HexCoord] = [
		HexCoord.new(0, 0), HexCoord.new(1, 0), HexCoord.new(2, 0), # chain A-B-C along East
		HexCoord.new(4, 0), # isolated D, not touching the chain
	]
	comp.valid_hexes = hexes
	comp._rebuild_valid_hex_set()

	var acc_a = AccumulatorTileScript.new()
	var acc_b = AccumulatorTileScript.new()
	var acc_c = AccumulatorTileScript.new()
	var acc_d = AccumulatorTileScript.new()
	comp.hex_grid.add_tile(HexCoord.new(0, 0), acc_a)
	comp.hex_grid.add_tile(HexCoord.new(1, 0), acc_b)
	comp.hex_grid.add_tile(HexCoord.new(2, 0), acc_c)
	comp.hex_grid.add_tile(HexCoord.new(4, 0), acc_d)

	var garage = GarageMenuScript.new()
	add_child(garage)
	garage.grid_renderer = GarageGridRendererScript.new()
	garage.add_child(garage.grid_renderer)
	garage.grid_renderer.setup(comp.hex_grid, garage, comp.valid_hexes)
	garage.grid_renderer.active_component = comp
	var helper = GarageTileConfigPopupScript.new(garage)

	# --- BFS grouping ---
	var group_from_a = helper._find_contiguous_accumulators(acc_a)
	_check("chain A-B-C (A and C only connect THROUGH B) all land in one group (got %d)" % group_from_a.size(),
		group_from_a.size() == 3 and group_from_a.has(acc_a) and group_from_a.has(acc_b) and group_from_a.has(acc_c))
	_check("the isolated Accumulator is NOT pulled into the chain's group", not group_from_a.has(acc_d))

	var group_from_d = helper._find_contiguous_accumulators(acc_d)
	_check("isolated Accumulator's own group is just itself", group_from_d.size() == 1 and group_from_d[0] == acc_d)

	# BFS is symmetric - starting from the far end of the chain (C) must
	# reach the same 3-tile group as starting from A.
	var group_from_c = helper._find_contiguous_accumulators(acc_c)
	_check("BFS from either end of the chain finds the same group", group_from_c.size() == 3)

	# --- Live popup propagation: click A, change the trigger key, confirm
	# B and C (but not D) picked it up. ---
	helper.on_tile_clicked(acc_a)
	var popup = garage.get_children().filter(func(c): return c is PopupPanel)[0]
	var opt_button = _find_option_button(popup, "None")
	_check("found the trigger-key OptionButton in the popup", opt_button != null)
	if opt_button:
		opt_button.item_selected.emit(2) # "Key 2"
		_check("propagated trigger_key to B", acc_b.trigger_key == "2")
		_check("propagated trigger_key to C", acc_c.trigger_key == "2")
		_check("did NOT touch the isolated Accumulator D", acc_d.trigger_key == "None")
		_check("A itself also got the new key", acc_a.trigger_key == "2")
	# Close the same way a real outside click would (focus_exited -> hide()
	# -> popup_hide -> queue_free) rather than freeing it directly - a
	# manual queue_free() here raced with that same chain when the SECOND
	# popup below naturally stole focus from this one.
	popup.hide()
	await get_tree().process_frame

	# --- Auto-dump propagation, same group. ---
	helper.on_tile_clicked(acc_b)
	await get_tree().process_frame
	var popup2 = garage.get_children().filter(func(c): return c is PopupPanel)
	if popup2.size() > 0:
		var dump_opt = _find_option_button(popup2[0], "Off (key fire only)")
		if dump_opt:
			dump_opt.item_selected.emit(3) # 75%
			_check("auto_dump_threshold propagated to A (clicked from B)", abs(acc_a.auto_dump_threshold - 0.75) < 0.001)
			_check("auto_dump_threshold propagated to C too", abs(acc_c.auto_dump_threshold - 0.75) < 0.001)
			_check("isolated D untouched by auto_dump propagation", acc_d.auto_dump_threshold == 0.0)
		popup2[0].hide()
		await get_tree().process_frame

	if failures == 0:
		print("PASS: contiguous Accumulators (transitively connected, not just direct neighbors) share trigger key and auto-dump settings")
	get_tree().quit(0 if failures == 0 else 1)

func _find_option_button(node: Node, first_item_text: String) -> OptionButton:
	if node is OptionButton and node.item_count > 0 and node.get_item_text(0) == first_item_text:
		return node
	for c in node.get_children():
		var found = _find_option_button(c, first_item_text)
		if found:
			return found
	return null
