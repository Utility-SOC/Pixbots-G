extends Node

# Regression harness for the ComponentDiagramView rewrite (playtest: "the
# boxes overlap, their rectangles have nothing to do with anything... the
# paperdoll is just too small... no information inside them"). The fixed
# grid layout is supposed to guarantee zero overlap BY CONSTRUCTION - this
# verifies that guarantee actually holds, that hit-testing still resolves
# to the right slot for GarageMenu's drag-drop equip, and that real
# per-component thumbnails actually get generated (not just placeholder
# text) for occupied slots.

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const ComponentDiagramViewScript = preload("res://scripts/ui/ComponentDiagramView.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _make_comp(slot: int, rarity: int) -> ComponentEquipmentScript:
	var comp = ComponentEquipmentScript.new(slot, rarity)
	# generate_procedural_shape() only populates valid_hexes (where tiles
	# COULD go, the outline) - it deliberately doesn't place any actual
	# HexTile instances (real gameplay code does that separately, per-slot,
	# via GarageShop._build_generated_component/LootManager). Place a real
	# tile at every valid hex so hex_grid isn't empty - the thumbnail
	# renderer needs actual tiles to draw, not just an outline.
	comp.generate_procedural_shape()
	var core_script = load("res://scripts/tiles/CoreTile.gd")
	for h in comp.valid_hexes:
		var tile = core_script.new()
		tile.rarity = rarity
		comp.hex_grid.add_tile(h, tile)
	return comp

func _ready():
	var diagram = ComponentDiagramViewScript.new()
	diagram.size = Vector2(900, 500) # a realistic grid_panel-sized area, not the zero-size _get_diagram_center() fallback
	add_child(diagram)
	await get_tree().process_frame

	# Build a real (not full/valid, just populated) loadout hitting every
	# anatomical slot at a rarity high enough to exercise the modifier
	# badge path too.
	var mech_components = {}
	var torso = _make_comp(HexTile.BodySlot.TORSO, HexTile.Rarity.MYTHIC)
	torso.stat_modifiers["dmg_mult"] = 1.1 # exercises the "+" badge path
	mech_components[HexTile.BodySlot.TORSO] = torso
	mech_components[HexTile.BodySlot.HEAD] = _make_comp(HexTile.BodySlot.HEAD, HexTile.Rarity.RARE)
	mech_components[HexTile.BodySlot.ARM_L] = _make_comp(HexTile.BodySlot.ARM_L, HexTile.Rarity.COMMON)
	mech_components[HexTile.BodySlot.ARM_R] = _make_comp(HexTile.BodySlot.ARM_R, HexTile.Rarity.LEGENDARY)
	mech_components[HexTile.BodySlot.LEG_L] = _make_comp(HexTile.BodySlot.LEG_L, HexTile.Rarity.UNCOMMON)
	mech_components[HexTile.BodySlot.LEG_R] = _make_comp(HexTile.BodySlot.LEG_R, HexTile.Rarity.UNCOMMON)
	# Backpack and Drone deliberately left empty - covers the "(empty)"
	# placeholder path alongside the occupied one in the same run.

	diagram.refresh(mech_components)
	await get_tree().process_frame

	# --- Zero overlap, by construction -------------------------------------
	var rects = []
	for slot_type in diagram._slot_nodes.keys():
		var node = diagram._slot_nodes[slot_type]
		if node.visible:
			rects.append(node.get_rect())
	_check("all 7 visible slot boxes present (Drone hidden, no bay equipped)", rects.size() == 7)
	var any_overlap = false
	for i in range(rects.size()):
		for j in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				any_overlap = true
	if any_overlap:
		for slot_type in diagram._slot_nodes.keys():
			var node = diagram._slot_nodes[slot_type]
			print("  DEBUG slot %s: pos=%s size=%s min=%s rect=%s" % [slot_type, node.position, node.size, node.get_combined_minimum_size(), node.get_rect()])
	_check("no two slot boxes overlap", not any_overlap)

	# --- Hit-testing still resolves correctly (GarageMenu's drag-drop path) --
	var torso_node = diagram._slot_nodes[HexTile.BodySlot.TORSO]
	var torso_center = torso_node.get_global_rect().get_center()
	_check("get_slot_at_point resolves the Torso box's own center to TORSO",
		diagram.get_slot_at_point(torso_center) == HexTile.BodySlot.TORSO)
	_check("get_slot_at_point resolves a point far outside any box to -1",
		diagram.get_slot_at_point(Vector2(-5000, -5000)) == -1)

	# --- Real per-component thumbnails, not just placeholder text ----------
	var torso_thumb: TextureRect = diagram._slot_thumbs[HexTile.BodySlot.TORSO]
	_check("occupied Torso slot got a real generated thumbnail texture", torso_thumb.texture != null)
	var backpack_thumb: TextureRect = diagram._slot_thumbs[HexTile.BodySlot.BACKPACK]
	_check("empty Backpack slot has no thumbnail texture", backpack_thumb.texture == null)
	_check("occupied Torso slot's stat-modifier badge row is non-empty",
		diagram._slot_badge_rows[HexTile.BodySlot.TORSO].get_child_count() > 0)

	# --- Highlight restores the correct border instead of getting stuck ----
	diagram.set_highlight(HexTile.BodySlot.ARM_L)
	diagram.set_highlight(HexTile.BodySlot.ARM_R)
	_check("switching highlight away from a slot doesn't leave it stuck", diagram._highlighted_slot == HexTile.BodySlot.ARM_R)
	diagram.set_highlight(-1)
	_check("clearing highlight (-1) is accepted without error", diagram._highlighted_slot == -1)

	# --- Zoom scales the whole diagram, boxes actually shrink --------------
	var full_zoom_size = torso_node.size
	diagram.zoom = 0.6
	diagram._reposition()
	await get_tree().process_frame
	_check("zooming out actually shrinks a box (custom_minimum_size scales, not just .size)",
		torso_node.size.x < full_zoom_size.x)

	diagram.queue_free()
	await get_tree().process_frame

	if failures == 0:
		print("PASS: ComponentDiagramView paperdoll rewrite - zero overlap, correct hit-testing, real thumbnails")
	get_tree().quit(0 if failures == 0 else 1)
