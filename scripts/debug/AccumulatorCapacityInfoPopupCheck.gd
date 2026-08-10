extends Node

# Regression check for GarageTileConfigPopup's Accumulator-popup capacity
# readout (replaces the old Mythic-only "capacity dial" button, removed
# when Accumulator capacity became automatic/rarity+count-driven for every
# rarity). Confirms the popup actually builds without crashing for several
# rarities and shows a sensible readout - runtime coverage, not just parse-
# time (ContiguousAccumulatorCheck.gd already proves this file parses
# cleanly via its own preload, but never calls on_tile_clicked() for an
# Accumulator specifically).

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

func _find_label_containing(node: Node, substr: String) -> Label:
	if node is Label and substr in node.text:
		return node
	for c in node.get_children():
		var found = _find_label_containing(c, substr)
		if found:
			return found
	return null

func _ready():
	for rarity in [HexTile.Rarity.COMMON, HexTile.Rarity.UNCOMMON, HexTile.Rarity.RARE, HexTile.Rarity.LEGENDARY, HexTile.Rarity.MYTHIC]:
		var comp = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.RARE)
		var hexes: Array[HexCoord] = [HexCoord.new(0, 0)]
		comp.valid_hexes = hexes
		comp._rebuild_valid_hex_set()
		var acc = AccumulatorTileScript.new()
		acc.rarity = rarity
		comp.hex_grid.add_tile(HexCoord.new(0, 0), acc)

		var garage = GarageMenuScript.new()
		add_child(garage)
		garage.grid_renderer = GarageGridRendererScript.new()
		garage.add_child(garage.grid_renderer)
		garage.grid_renderer.setup(comp.hex_grid, garage, comp.valid_hexes)
		garage.grid_renderer.active_component = comp
		var helper = GarageTileConfigPopupScript.new(garage)

		helper.on_tile_clicked(acc) # must not crash for any rarity
		var tier_info = HexTile.ACCUMULATOR_CAPACITY_TIERS[rarity]
		var found = _find_label_containing(garage, "%dx" % tier_info[0])
		_check("the config popup for a %s Accumulator builds without crashing and shows its %dx ceiling" % [
			["Common", "Uncommon", "Rare", "Legendary", "Mythic"][rarity], tier_info[0]],
			found != null)

		garage.queue_free()

	if failures == 0:
		print("PASS: Accumulator config popup builds cleanly and shows the correct capacity ceiling for every rarity")
	get_tree().quit(0 if failures == 0 else 1)
