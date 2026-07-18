class_name ComponentDiagramView
extends Control

# Zoomable "exploded parts diagram" for the Garage's Components view.
#
# Shows a simplified mech silhouette in the middle with a fixed-size callout
# box per body slot (head, torso, both arms, backpack, both legs), each
# linked back to its anchor point on the silhouette by a leader line. Per
# the user's design pass (confirmed via mockup): head sits off to the left,
# backpack off to the right, torso above but slightly left of center, arms
# and legs flank below - and when the silhouette is zoomed, the callout
# BOXES stay a constant screen size (only their position along the leader
# line moves) so they never become illegibly tiny or comically huge.
#
# Drag-and-drop equip is handled by GarageMenu (which already owns a manual
# drag system for hex tiles) - this view just exposes get_slot_at_point() so
# GarageMenu can hit-test a drop, and refresh() so it can push the
# currently-equipped part into each callout's label.

signal slot_pressed(slot_type)

const MechRendererClass = preload("res://scripts/visuals/MechRenderer.gd")
const PreviewMechContext = preload("res://scripts/visuals/PreviewMechContext.gd")
const PreloadedDroneBayTile = preload("res://scripts/tiles/DroneBayTile.gd")

const CALLOUT_SIZE = Vector2(78, 38)
# On-screen size (at zoom = 1) of the live mech preview - the actual pixel
# resolution rendered into the SubViewport, kept comfortably above this so
# scaling up doesn't look soft.
const PREVIEW_BASE_SIZE = Vector2(100, 140)
const PREVIEW_VIEWPORT_SIZE = Vector2i(200, 280)

# anchor: point on the silhouette this slot attaches to (relative to the
# diagram center, at zoom = 1). dir: direction the leader line travels
# before reaching the callout. gap: leader line length in pixels - does NOT
# scale with zoom, which is what keeps the callout at a roughly constant
# distance from the (zoom-scaled) anchor instead of drifting away at high
# zoom or crowding the silhouette at low zoom.
var _slot_defs: Array = [
	{"slot": HexTile.BodySlot.HEAD, "label": "Head", "color": Color(0.25, 0.45, 0.75), "anchor": Vector2(0, -50), "dir": Vector2(-1.0, -0.25), "gap": 96},
	{"slot": HexTile.BodySlot.TORSO, "label": "Torso", "color": Color(0.45, 0.45, 0.42), "anchor": Vector2(-6, -26), "dir": Vector2(-0.25, -1.0), "gap": 84},
	{"slot": HexTile.BodySlot.BACKPACK, "label": "Backpack", "color": Color(0.75, 0.55, 0.15), "anchor": Vector2(16, -12), "dir": Vector2(0.95, -0.4), "gap": 90},
	{"slot": HexTile.BodySlot.ARM_L, "label": "L. arm", "color": Color(0.45, 0.3, 0.65), "anchor": Vector2(-37, 4), "dir": Vector2(-1.0, 0.25), "gap": 78},
	{"slot": HexTile.BodySlot.ARM_R, "label": "R. arm", "color": Color(0.45, 0.3, 0.65), "anchor": Vector2(37, 4), "dir": Vector2(1.0, 0.25), "gap": 78},
	{"slot": HexTile.BodySlot.LEG_L, "label": "L. leg", "color": Color(0.15, 0.55, 0.5), "anchor": Vector2(-21, 50), "dir": Vector2(-0.85, 0.7), "gap": 78},
	{"slot": HexTile.BodySlot.LEG_R, "label": "R. leg", "color": Color(0.15, 0.55, 0.5), "anchor": Vector2(21, 50), "dir": Vector2(0.85, 0.7), "gap": 78},
	# Drone isn't physically part of the mech body (it's a separate flying
	# companion unlocked by a Drone Bay tile in the Backpack - see
	# DroneBayTile.gd) - drawn as a satellite off to the side with a longer
	# leader line than the anatomical slots above, reading as "orbiting
	# nearby" rather than attached. Only shown/interactive once a Drone Bay
	# is actually installed - see refresh()'s special-casing for this slot.
	{"slot": HexTile.BodySlot.DRONE, "label": "Drone", "color": Color(0.2, 0.55, 0.6), "anchor": Vector2(10, 10), "dir": Vector2(1.0, 0.55), "gap": 130},
]

var zoom: float = 1.0
var _slot_nodes: Dictionary = {} # BodySlot int -> PanelContainer
var _slot_labels: Dictionary = {} # BodySlot int -> Label (the second/equipped-part line)
var _line_points: Dictionary = {} # BodySlot int -> {"from": Vector2, "to": Vector2}
var _highlighted_slot = -1
var _zoom_slider: HSlider = null

# Live preview of the player's actual equipped mech, rendered off-screen by
# a real MechRenderer (the same class that draws every mech in the game) and
# displayed via a TextureRect - replaces the old flat gray placeholder
# blocks. PreviewMechContext stands in for a real Mech.gd node (see that
# file's own comment) so MechRenderer picks up the real hero color/scale/
# accent profile instead of falling back to the generic default. Since it's
# a genuine MechRenderer, equipping a different rarity/type of part actually
# changes what's drawn (size, jitter, accents) - not just a label change.
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
	var w = size.x if size.x > 0 else 300.0
	var h = size.y if size.y > 0 else 380.0
	return Vector2(w * 0.5, 34.0 + (h - 34.0) * 0.42)

func _make_slot_node(info: Dictionary) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = CALLOUT_SIZE
	panel.size = CALLOUT_SIZE

	var style = StyleBoxFlat.new()
	style.bg_color = Color(info.color, 0.35)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = info.color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	var name_lbl = Label.new()
	name_lbl.text = info.label
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(name_lbl)

	var equipped_lbl = Label.new()
	equipped_lbl.text = "(empty)"
	equipped_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	equipped_lbl.add_theme_font_size_override("font_size", 9)
	equipped_lbl.modulate = Color(1, 1, 1, 0.75)
	equipped_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(equipped_lbl)
	_slot_labels[info.slot] = equipped_lbl

	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(_on_slot_gui_input.bind(info.slot))
	return panel

func _on_slot_gui_input(event: InputEvent, slot_type):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		slot_pressed.emit(slot_type)

func _reposition():
	var center = _get_diagram_center()
	if _zoom_slider:
		_zoom_slider.position = Vector2(0, 0)
		_zoom_slider.size = Vector2(size.x, 20)

	if _preview_rect:
		var preview_size = PREVIEW_BASE_SIZE * zoom
		_preview_rect.size = preview_size
		_preview_rect.position = center - preview_size * 0.5

	for info in _slot_defs:
		var anchor = center + info.anchor * zoom
		var dir: Vector2 = info.dir.normalized()
		var callout_center = anchor + dir * info.gap
		var node = _slot_nodes[info.slot]
		node.position = callout_center - CALLOUT_SIZE * 0.5
		_line_points[info.slot] = {"from": anchor, "to": callout_center}
	queue_redraw()

func _draw():
	for slot_type in _line_points.keys():
		var node = _slot_nodes.get(slot_type)
		if node and not node.visible:
			continue
		var lp = _line_points[slot_type]
		var col = Color(0.75, 0.75, 0.75, 0.85)
		var w = 2.0
		if slot_type == _highlighted_slot:
			col = Color(1.0, 0.95, 0.5, 1.0)
			w = 3.0
		draw_line(lp.from, lp.to, col, w)

# Pushes currently-equipped parts (from GarageMenu.mech_components) into each
# callout's second label, AND rebuilds the live preview so it actually shows
# what's equipped (bigger/more detailed shapes for higher rarity, different
# jitter per component name/rarity - see MechRenderer._rebuild_visuals()).
# Called by GarageMenu whenever equip state changes.
func refresh(mech_components: Dictionary):
	var rarity_names = ["Common", "Uncommon", "Rare", "Legendary", "Mythic"]

	# Drone isn't a real mech_components entry (see HexTile.BodySlot.DRONE's
	# comment) - its data lives nested on whatever Drone Bay tile is
	# installed in the Backpack, if any. Look that up once here rather than
	# duplicating the lookup per-frame; the whole callout hides itself when
	# there's no Drone Bay equipped at all, distinct from an anatomical slot
	# just sitting "(empty)".
	var drone_bay = PreloadedDroneBayTile.find_in_backpack(mech_components.get(HexTile.BodySlot.BACKPACK))

	for info in _slot_defs:
		var lbl = _slot_labels.get(info.slot)
		if not lbl:
			continue

		if info.slot == HexTile.BodySlot.DRONE:
			var node = _slot_nodes.get(info.slot)
			if node:
				node.visible = drone_bay != null
			if drone_bay:
				var drone_comp = drone_bay.get_or_build_loadout()
				var txt = rarity_names[drone_comp.rarity] if drone_comp.rarity < rarity_names.size() else "?"
				lbl.text = txt
			continue

		var comp = mech_components.get(info.slot)
		if comp:
			var txt = rarity_names[comp.rarity] if comp.rarity < rarity_names.size() else "?"
			if comp.infusion_level > 0:
				txt += " Lv%d" % comp.infusion_level
			lbl.text = txt
		else:
			lbl.text = "(empty)"

	if _preview_renderer:
		var sig = _compute_preview_signature(mech_components)
		if sig != _last_preview_signature:
			_last_preview_signature = sig
			_preview_renderer.components = mech_components
			_preview_renderer._rebuild_visuals()

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
	_highlighted_slot = slot_type
	queue_redraw()
