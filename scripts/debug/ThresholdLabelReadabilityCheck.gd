extends Node

# Regression guard for GarageTileConfigPopup.gd's Weapon Mount firing-
# threshold button label. The old "str(v/1000) + 'k'" formatting was fine
# up to the base 1.2M ceiling, but Accumulator-scaled thresholds (see
# WeaponMountTile.get_threshold_options / WeaponMountThresholdScalingCheck.gd)
# can now reach into the hundreds of millions, producing unreadable labels
# like "180075k". Fixed with M/B-suffixed formatting; this check drives the
# REAL popup end-to-end (not just the formatting formula in isolation) to
# make sure the fix is actually wired into what the player sees.

const GarageMenuScript = preload("res://scripts/ui/GarageMenu.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")
const WeaponMountTileScript = preload("res://scripts/tiles/WeaponMountTile.gd")
const AccumulatorTileScript = preload("res://scripts/tiles/AccumulatorTile.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _find_button_with_prefix(node: Node, prefix: String) -> Button:
	if node is Button and str(node.text).begins_with(prefix):
		return node
	for c in node.get_children():
		var found = _find_button_with_prefix(c, prefix)
		if found:
			return found
	return null

func _ready():
	var world = Node2D.new()
	add_child(world)

	var garage = GarageMenuScript.new()
	world.add_child(garage)

	var comp = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.RARE)
	world.add_child(comp)
	comp.generate_shape()
	var core = CoreTileScript.new()
	core.rarity = HexTile.Rarity.RARE
	comp.hex_grid.add_tile(HexCoord.new(0, 0), core)

	var mount = WeaponMountTileScript.new()
	mount.rarity = HexTile.Rarity.MYTHIC # threshold cycling is a Mythic-only ability - see GarageTileConfigPopup.gd's "tile.rarity < MYTHIC" locked-hint gate
	comp.hex_grid.add_tile(HexCoord.new(1, 0), mount)
	var acc = AccumulatorTileScript.new()
	acc.rarity = HexTile.Rarity.MYTHIC
	comp.hex_grid.add_tile(HexCoord.new(1, 0).neighbor(0), acc)

	garage.active_component = comp
	garage.mech_components = {HexTile.BodySlot.TORSO: comp}
	garage.grid_renderer.setup(comp.hex_grid, garage, comp.valid_hexes)

	# Cycle straight to the biggest available Accumulator-scaled tier
	# (mirrors WeaponMountThresholdScalingCheck.gd's own approach).
	var options = mount.get_threshold_options(comp.hex_grid, HexCoord.new(1, 0))
	mount.mythic_firing_threshold = options.max()
	_check("test setup actually reached a threshold in the hundreds of millions (got %d)" % mount.mythic_firing_threshold,
		mount.mythic_firing_threshold > 100000000)

	garage._on_tile_clicked(mount)
	var btn = _find_button_with_prefix(garage, "Firing Threshold:")
	_check("the real config popup has a Firing Threshold button", btn != null)
	if btn:
		_check("the button label uses M/B-suffixed formatting, not a raw 9-digit number (got: %s)" % btn.text,
			(btn.text.contains("M") or btn.text.contains("B")) and not btn.text.contains("000000"))

	# Sanity: the small/default end of the scale still reads as before.
	# queue_free() is deferred, so wait a frame before re-searching the
	# tree or the stale popup's button (still present until freed) would
	# shadow the new one in _find_button_with_prefix's depth-first search.
	for c in garage.get_children():
		if c is PopupPanel:
			c.queue_free()
	await get_tree().process_frame
	mount.mythic_firing_threshold = 0
	garage._on_tile_clicked(mount)
	var btn2 = _find_button_with_prefix(garage, "Firing Threshold:")
	_check("threshold 0 still reads as 'Auto-fire (0)', unchanged by the M/B formatting change",
		btn2 != null and btn2.text.contains("Auto-fire (0)"))

	if failures == 0:
		print("PASS: Weapon Mount firing-threshold label stays readable at Accumulator-scaled hundred-million-plus values")
	get_tree().quit(0 if failures == 0 else 1)
