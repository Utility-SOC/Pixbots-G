extends Node

# Regression harness for: "plus signs almost entirely covered by
# scrollbar" - the Mythic Splitter's ratio-tuning "+" buttons in
# GarageTileConfigPopup, in the "Configure Outputs" popup (Splitter/
# Accessory Return branch).
#
# Root cause: the scrollable body's inner vbox was set to the EXACT same
# width as the ScrollContainer around it (360 == 360). A ScrollContainer's
# scrollbar draws as an overlay inside its own viewport rather than
# reserving separate space, so content filling that viewport edge-to-edge
# left nothing but the scrollbar thumb sitting on top of it once there was
# enough content to actually need scrolling (a Mythic Splitter's 6 face
# toggles + 6 ratio rows comfortably exceeds the panel's fixed height).
# Fixed by narrowing the inner vbox to leave real clearance.

const GarageMenuScript = preload("res://scripts/ui/GarageMenu.gd")
const SplitterTileScript = preload("res://scripts/tiles/SplitterTile.gd")
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
	var tile = SplitterTileScript.new()
	tile.rarity = HexTile.Rarity.MYTHIC
	tile.grid_position = HexCoord.new(0, 0)

	var garage = GarageMenuScript.new()
	add_child(garage)
	garage.grid_renderer = GarageGridRendererScript.new()
	garage.add_child(garage.grid_renderer)

	var popup_helper = GarageTileConfigPopupScript.new(garage)
	popup_helper.on_tile_clicked(tile)

	# Walk the freshly-built popup for the ScrollContainer and its direct
	# VBoxContainer child, and confirm real clearance between them.
	var popup = null
	for child in garage.get_children():
		if child is PopupPanel:
			popup = child
			break
	_check("a config popup was actually created", popup != null)
	if popup == null:
		get_tree().quit(1)
		return

	var scroll = _find_first(popup, "ScrollContainer")
	_check("found the scrollable body", scroll != null)
	if scroll == null:
		get_tree().quit(1)
		return

	var inner_vbox = null
	for child in scroll.get_children():
		if child is VBoxContainer:
			inner_vbox = child
			break
	_check("found the inner vbox", inner_vbox != null)
	if inner_vbox == null:
		get_tree().quit(1)
		return

	var clearance = scroll.custom_minimum_size.x - inner_vbox.custom_minimum_size.x
	_check("the inner content is narrower than the scroll viewport (real clearance for the scrollbar: %d px)" % clearance,
		clearance >= 16.0)

	popup.queue_free()

	if failures == 0:
		print("PASS: the ratio-tuning rows' + buttons have real scrollbar clearance")
	get_tree().quit(0 if failures == 0 else 1)

func _find_first(node: Node, class_name_str: String) -> Node:
	if node.get_class() == class_name_str:
		return node
	for child in node.get_children():
		var found = _find_first(child, class_name_str)
		if found:
			return found
	return null
