class_name ComponentDiagramView
extends Control

# Zoomable mech loadout diagram for the Garage's Components view.
#
# Rewritten per playtest feedback on the original leader-line "exploded
# diagram" layout: "the boxes overlap, their rectangles have nothing to do
# with anything, they are arbitrary, the colors are not great and the
# paperdoll is just too small... the rectangles have no information inside
# them to inform my decisions." Concretely:
#   - Fixed 4-column x 2-row GRID (below a full-width mech preview band)
#     instead of anchor+direction+gap trig math - guarantees zero overlap
#     by construction rather than by tuning gap distances, and uses the
#     panel's actual (large) available area instead of clustering tiny
#     boxes around the mech.
#   - Each box's border is RARITY-colored (matches the rest of the Garage's
#     rarity color language) instead of an arbitrary per-slot hue that
#     carried no information.
#   - Each box shows the component's REAL hex-tile shape as a small
#     rendered thumbnail (ChampionCard.render_component_thumbnail - the
#     same per-tile pixel-blit already used for Champion Card PNGs), plus
#     rarity/level, tile count, and modifier/forbidden badges - the same
#     information density as the Garage's spare-parts cards
#     (GarageInventoryPanel.gd), just applied to what's actually equipped.
# No leader lines: grid position alone (Head top-left, arms/legs below,
# Backpack/Drone as accessories) reads the anatomy without needing lines
# drawn across a cluttered background.
#
# Drag-and-drop equip is handled by GarageMenu (which already owns a manual
# drag system for hex tiles) - this view just exposes get_slot_at_point()
# so GarageMenu can hit-test a drop, and refresh() so it can push the
# currently-equipped part into each box.

signal slot_pressed(slot_type)

const MechRendererClass = preload("res://scripts/visuals/MechRenderer.gd")
const PreviewMechContext = preload("res://scripts/visuals/PreviewMechContext.gd")
const PreloadedDroneBayTile = preload("res://scripts/tiles/DroneBayTile.gd")
const ChampionCardScript = preload("res://scripts/pvp/ChampionCard.gd")

const CELL_SIZE = Vector2(172, 108)
const CELL_GAP = Vector2(16, 16)
const THUMB_CELL_PX = 8 # source resolution of the generated hex-schematic art, before TextureRect scales it to fit
# On-screen size (at zoom = 1) of the live mech preview - the actual pixel
# resolution rendered into the SubViewport, kept comfortably above this so
# scaling up doesn't look soft.
const PREVIEW_BASE_SIZE = Vector2(176, 208)
const PREVIEW_VIEWPORT_SIZE = Vector2i(300, 360)
# Vertical gap between the preview band's bottom and the grid's top row,
# and how far above center the preview itself sits - both scale with zoom
# alongside everything else so the whole diagram grows/shrinks as one unit.
const PREVIEW_TO_GRID_GAP = 22.0

# col: 0-3 left-to-right. row: 0 (top, "core"/accessory slots) or 1 (limbs).
var _slot_defs: Array = [
	{"slot": HexTile.BodySlot.HEAD, "label": "Head", "col": 0, "row": 0},
	{"slot": HexTile.BodySlot.TORSO, "label": "Torso", "col": 1, "row": 0},
	{"slot": HexTile.BodySlot.BACKPACK, "label": "Backpack", "col": 2, "row": 0},
	{"slot": HexTile.BodySlot.DRONE, "label": "Drone", "col": 3, "row": 0},
	{"slot": HexTile.BodySlot.ARM_L, "label": "L. Arm", "col": 0, "row": 1},
	{"slot": HexTile.BodySlot.ARM_R, "label": "R. Arm", "col": 1, "row": 1},
	{"slot": HexTile.BodySlot.LEG_L, "label": "L. Leg", "col": 2, "row": 1},
	{"slot": HexTile.BodySlot.LEG_R, "label": "R. Leg", "col": 3, "row": 1},
]

var zoom: float = 1.0
var _slot_nodes: Dictionary = {} # BodySlot int -> PanelContainer
var _slot_thumbs: Dictionary = {} # BodySlot int -> TextureRect
var _slot_info_labels: Dictionary = {} # BodySlot int -> Label (rarity/Lv or "(empty)")
var _slot_count_labels: Dictionary = {} # BodySlot int -> Label (tile count)
var _slot_badge_rows: Dictionary = {} # BodySlot int -> HBoxContainer
var _slot_thumb_signature: Dictionary = {} # BodySlot int -> String, avoids regenerating the thumbnail image every refresh() tick
var _slot_comp: Dictionary = {} # BodySlot int -> ComponentEquipment or null, so set_highlight() can restore the correct border without re-deriving it from label state
var _highlighted_slot = -1
var _zoom_slider: HSlider = null

# Live preview of the player's actual equipped mech, rendered off-screen by
# a real MechRenderer (the same class that draws every mech in the game) and
# displayed via a TextureRect - a genuine MechRenderer, so equipping a
# different rarity/type of part actually changes what's drawn (size,
# jitter, accents) - not just a label change.
var _preview_viewport: SubViewport = null
var _preview_context: PreviewMechContext = null
var _preview_renderer: Node2D = null
var _preview_rect: TextureRect = null
# Cheap fingerprint of the last mech_components dict actually rendered.
# refresh() gets called from GarageMenu._refresh_component_inventory_list(),
# which fires on nearly every Garage UI tick (sorting, list rebuilds, tray
# refreshes) - NOT just real equip changes. Without this guard,
# _rebuild_visuals() (a real cost: rebuilds every body-part mesh/particle
# node from scratch) was re-running on every single one of those refreshes,
# which is the leading suspect for the reappeared "lag when I first shoot"
# right after leaving the Garage. Only rebuild when what's equipped actually
# changed.
var _last_preview_signature: String = ""

const RARITY_NAMES = ["Common", "Uncommon", "Rare", "Legendary", "Mythic"]
const EMPTY_BORDER_COLOR = Color(0.4, 0.4, 0.45)
const HIGHLIGHT_COLOR = Color(1.0, 0.95, 0.5)

func _ready():
	mouse_filter = Control.MOUSE_FILTER_PASS
	resized.connect(_reposition)

	_zoom_slider = HSlider.new()
	_zoom_slider.min_value = 0.6
	_zoom_slider.max_value = 1.8
	_zoom_slider.step = 0.05
	_zoom_slider.value = 1.0
	_zoom_slider.custom_minimum_size = Vector2(0, 20)
	_zoom_slider.value_changed.connect(func(v):
		zoom = v
		_reposition()
	)
	add_child(_zoom_slider)

	_preview_viewport = SubViewport.new()
	_preview_viewport.size = PREVIEW_VIEWPORT_SIZE
	_preview_viewport.transparent_bg = true
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_preview_viewport)

	_preview_context = PreviewMechContext.new()
	_preview_context.position = Vector2(PREVIEW_VIEWPORT_SIZE) * 0.5
	_preview_viewport.add_child(_preview_context)

	_preview_renderer = MechRendererClass.new()
	_preview_context.add_child(_preview_renderer)

	_preview_rect = TextureRect.new()
	_preview_rect.texture = _preview_viewport.get_texture()
	_preview_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_preview_rect)

	for info in _slot_defs:
		var node = _make_slot_node(info)
		add_child(node)
		_slot_nodes[info.slot] = node

	_reposition()

func _get_diagram_center() -> Vector2:
	var w = size.x if size.x > 0 else 700.0
	var h = size.y if size.y > 0 else 420.0
	return Vector2(w * 0.5, h * 0.5)

func _make_slot_node(info: Dictionary) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = CELL_SIZE
	panel.size = CELL_SIZE
	_apply_slot_style(panel, EMPTY_BORDER_COLOR)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 1)
	panel.add_child(vbox)

	var thumb = TextureRect.new()
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# EXPAND_IGNORE_SIZE: without this, TextureRect's minimum size defaults
	# to the assigned texture's OWN native pixel dimensions - and the
	# generated thumbnail's native size varies a lot by component (a
	# spread-out 100-hex Mythic torso vs. a compact 10-hex Common arm),
	# so different slots would silently blow past CELL_SIZE by wildly
	# different amounts and break the grid's zero-overlap guarantee. With
	# this, custom_minimum_size below is the only floor, same for every box
	# regardless of what shape happens to be equipped in it.
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	thumb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	thumb.custom_minimum_size = Vector2(0, 40)
	vbox.add_child(thumb)
	_slot_thumbs[info.slot] = thumb

	var name_lbl = Label.new()
	name_lbl.text = info.label
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 12)
	vbox.add_child(name_lbl)

	var info_lbl = Label.new()
	info_lbl.text = "(empty)"
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_lbl.add_theme_font_size_override("font_size", 10)
	info_lbl.modulate = Color(1, 1, 1, 0.75)
	vbox.add_child(info_lbl)
	_slot_info_labels[info.slot] = info_lbl

	var bottom_row = HBoxContainer.new()
	bottom_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(bottom_row)

	var count_lbl = Label.new()
	count_lbl.text = ""
	count_lbl.add_theme_font_size_override("font_size", 9)
	count_lbl.modulate = Color(0.75, 0.75, 0.75)
	bottom_row.add_child(count_lbl)
	_slot_count_labels[info.slot] = count_lbl

	var badge_row = HBoxContainer.new()
	badge_row.add_theme_constant_override("separation", 3)
	bottom_row.add_child(badge_row)
	_slot_badge_rows[info.slot] = badge_row

	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(_on_slot_gui_input.bind(info.slot))
	return panel

func _apply_slot_style(panel: PanelContainer, border_color: Color):
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.85)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = border_color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)

func _on_slot_gui_input(event: InputEvent, slot_type):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		slot_pressed.emit(slot_type)

func _reposition():
	var center = _get_diagram_center()
	if _zoom_slider:
		_zoom_slider.position = Vector2(0, 0)
		_zoom_slider.size = Vector2(size.x, 20)

	var preview_size = PREVIEW_BASE_SIZE * zoom
	var grid_width = 4 * CELL_SIZE.x * zoom + 3 * CELL_GAP.x * zoom
	var grid_height = 2 * CELL_SIZE.y * zoom + CELL_GAP.y * zoom
	var total_height = preview_size.y + PREVIEW_TO_GRID_GAP * zoom + grid_height
	var top = center.y - total_height * 0.5

	if _preview_rect:
		_preview_rect.size = preview_size
		_preview_rect.position = Vector2(center.x - preview_size.x * 0.5, top)

	var grid_top = top + preview_size.y + PREVIEW_TO_GRID_GAP * zoom
	var grid_left = center.x - grid_width * 0.5
	var cell_w = CELL_SIZE.x * zoom
	var cell_h = CELL_SIZE.y * zoom
	for info in _slot_defs:
		var node = _slot_nodes[info.slot]
		var x = grid_left + info.col * (cell_w + CELL_GAP.x * zoom)
		var y = grid_top + info.row * (cell_h + CELL_GAP.y * zoom)
		node.position = Vector2(x, y)
		# custom_minimum_size (not just .size) has to scale too - a
		# PanelContainer clamps its actual rendered size to at least its
		# own reported minimum, so a stale fixed minimum from _ready()
		# would silently block the boxes from ever shrinking below it,
		# even though .size below was set correctly on every zoom-out.
		node.custom_minimum_size = Vector2(cell_w, cell_h)
		node.size = Vector2(cell_w, cell_h)

# Pushes currently-equipped parts (from GarageMenu.mech_components) into each
# box's thumbnail/labels, AND rebuilds the live preview so it actually shows
# what's equipped. Called by GarageMenu whenever equip state changes.
func refresh(mech_components: Dictionary):
	# Drone isn't a real mech_components entry (see HexTile.BodySlot.DRONE's
	# comment) - its data lives nested on whatever Drone Bay tile is
	# installed anywhere in the mech (not just the Backpack - see
	# DroneBayTile.find_all_in_mech), if any. Look that up once here rather
	# than duplicating the lookup per-slot; the whole box hides itself when
	# there's no Drone Bay equipped at all, distinct from an anatomical slot
	# just sitting "(empty)".
	var mech_drone_bays = PreloadedDroneBayTile.find_all_in_mech(mech_components)
	var drone_bay = mech_drone_bays[0] if not mech_drone_bays.is_empty() else null

	for info in _slot_defs:
		var node = _slot_nodes.get(info.slot)
		if not node:
			continue

		var comp = null
		if info.slot == HexTile.BodySlot.DRONE:
			node.visible = drone_bay != null
			if drone_bay:
				comp = drone_bay.get_or_build_loadout()
		else:
			comp = mech_components.get(info.slot)

		_refresh_slot_visual(info.slot, node, comp)

	if _preview_renderer:
		var sig = _compute_preview_signature(mech_components)
		if sig != _last_preview_signature:
			_last_preview_signature = sig
			_preview_renderer.components = mech_components
			_preview_renderer._rebuild_visuals()

func _refresh_slot_visual(slot_type, node: PanelContainer, comp):
	var info_lbl: Label = _slot_info_labels[slot_type]
	var count_lbl: Label = _slot_count_labels[slot_type]
	var badge_row: HBoxContainer = _slot_badge_rows[slot_type]
	var thumb: TextureRect = _slot_thumbs[slot_type]

	for c in badge_row.get_children():
		c.queue_free()

	_slot_comp[slot_type] = comp

	if not comp:
		_apply_slot_style(node, EMPTY_BORDER_COLOR)
		info_lbl.text = "(empty)"
		info_lbl.modulate = Color(1, 1, 1, 0.5)
		count_lbl.text = ""
		thumb.texture = null
		_slot_thumb_signature[slot_type] = ""
		return

	var rarity = clamp(comp.rarity, 0, 4)
	var rarity_color = ChampionCardScript.RARITY_COLORS[rarity]
	var border = HIGHLIGHT_COLOR if slot_type == _highlighted_slot else rarity_color
	_apply_slot_style(node, border)

	var txt = RARITY_NAMES[rarity]
	if comp.infusion_level > 0:
		txt += " Lv%d" % comp.infusion_level
	info_lbl.text = txt
	info_lbl.modulate = rarity_color
	info_lbl.modulate.a = 1.0

	var tile_count = comp.hex_grid.get_all_tiles().size() if comp.hex_grid else 0
	count_lbl.text = "%d tiles" % tile_count

	if not comp.stat_modifiers.is_empty():
		var mod_badge = Label.new()
		mod_badge.text = "+"
		mod_badge.modulate = Color(0.4, 1.0, 0.5)
		mod_badge.add_theme_font_size_override("font_size", 12)
		badge_row.add_child(mod_badge)
	if not comp.forbidden_tile_types.is_empty():
		var forb_badge = Label.new()
		forb_badge.text = "!"
		forb_badge.modulate = Color(1.0, 0.4, 0.4)
		forb_badge.add_theme_font_size_override("font_size", 12)
		badge_row.add_child(forb_badge)

	# Regenerating the thumbnail is a real (if small) per-slot image build -
	# refresh() fires far more often than the equipped shape actually
	# changes (see this file's header). tile_count catches in-Garage tile
	# add/remove edits to the SAME component instance; identity+rarity+level
	# catches an actual swap. Doesn't catch "removed one tile, added a
	# different one, net count unchanged" - acceptable staleness for a
	# thumbnail, not the source of truth for anything.
	var sig = "%d:%d:%d:%d" % [comp.get_instance_id(), rarity, comp.infusion_level, tile_count]
	if _slot_thumb_signature.get(slot_type, "") != sig:
		_slot_thumb_signature[slot_type] = sig
		var img = ChampionCardScript.render_component_thumbnail(comp, THUMB_CELL_PX)
		thumb.texture = ImageTexture.create_from_image(img) if img else null

# Builds a cheap string key summarizing which component (by identity, rarity,
# and infusion level - the things that actually change how it's drawn) is in
# each slot, so refresh() can tell a real equip change from a no-op refresh.
func _compute_preview_signature(mech_components: Dictionary) -> String:
	var parts = PackedStringArray()
	for info in _slot_defs:
		var comp = mech_components.get(info.slot)
		if comp:
			parts.append("%d:%d:%d:%d" % [info.slot, comp.get_instance_id(), comp.rarity, comp.infusion_level])
		else:
			parts.append("%d:-" % info.slot)
	return ",".join(parts)

func get_slot_at_point(global_pos: Vector2) -> int:
	for slot_type in _slot_nodes.keys():
		var node: Control = _slot_nodes[slot_type]
		if node.get_global_rect().has_point(global_pos):
			return slot_type
	return -1

func set_highlight(slot_type):
	if _highlighted_slot == slot_type:
		return
	var prev = _highlighted_slot
	_highlighted_slot = slot_type
	if prev != -1:
		_restyle_slot_border(prev)
	if slot_type != -1:
		var node = _slot_nodes.get(slot_type)
		if node:
			_apply_slot_style(node, HIGHLIGHT_COLOR)

# Restores a slot's border to whatever it should be from equip state alone
# (rarity color, or the neutral empty color) - used to clear a highlight
# without needing to remember what the border was before it got overridden.
func _restyle_slot_border(slot_type):
	var node = _slot_nodes.get(slot_type)
	if not node:
		return
	var comp = _slot_comp.get(slot_type)
	if comp:
		_apply_slot_style(node, ChampionCardScript.RARITY_COLORS[clamp(comp.rarity, 0, 4)])
	else:
		_apply_slot_style(node, EMPTY_BORDER_COLOR)
