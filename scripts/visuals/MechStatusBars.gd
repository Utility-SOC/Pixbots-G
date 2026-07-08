class_name MechStatusBars
extends Node2D

# HP/shield bar layer, split out of MechRenderer.gd so it can be added as the
# LAST child of the renderer (see MechRenderer._rebuild_visuals()) instead of
# drawn via the renderer's own _draw(). A node's own draw commands render
# BEFORE its children's, so when the bars lived on MechRenderer itself, every
# body part (head, V-fin/antenna, boss mast, etc.) painted right over them -
# reported as the bars "hiding behind my head". Being a separate, later-added
# sibling fixes the draw order regardless of where any part's shapes fall.
#
# Position also now scales with the mech's actual role visual scale (0.8
# scout ... 1.8 boss) instead of one fixed offset that only cleared the
# smallest builds - a boss-scale head could reach well past the old fixed
# -40px and get clipped by/blend into the bar anyway even with the ordering
# fix alone.

var owner_mech: Node = null
var owner_renderer: Node = null

var _last_hp_pct: float = -1.0
var _last_shld_pct: float = -1.0

func _process(_delta):
	if not owner_mech or not is_instance_valid(owner_mech) or not "hp" in owner_mech:
		return
	var hp_pct = clamp(owner_mech.hp / max(1.0, owner_mech.max_hp), 0.0, 1.0)
	var shld_pct = 0.0
	if owner_mech.max_shield_hp > 0:
		shld_pct = clamp(owner_mech.shield_hp / max(1.0, owner_mech.max_shield_hp), 0.0, 1.0)
	if hp_pct != _last_hp_pct or shld_pct != _last_shld_pct:
		_last_hp_pct = hp_pct
		_last_shld_pct = shld_pct
		queue_redraw()

func _get_render_scale() -> float:
	if owner_renderer and is_instance_valid(owner_renderer) and "last_render_scale" in owner_renderer:
		return owner_renderer.last_render_scale
	return 1.0

func _draw():
	if not owner_mech or not is_instance_valid(owner_mech) or not "hp" in owner_mech:
		return

	var scale_f = _get_render_scale()
	var bar_width = 44.0
	var bar_height = 5.0
	var bar_gap = 2.0
	# Base clearance (30px) covers the smallest chassis; the extra term scales
	# with role visual size so a boss's much taller head/antenna silhouette
	# doesn't reach up into the bars.
	var y_offset = -(34.0 + 22.0 * scale_f)

	var hp_pct = clamp(owner_mech.hp / max(1.0, owner_mech.max_hp), 0.0, 1.0)
	var shld_pct = 0.0
	if owner_mech.max_shield_hp > 0:
		shld_pct = clamp(owner_mech.shield_hp / max(1.0, owner_mech.max_shield_hp), 0.0, 1.0)

	var has_shield = owner_mech.max_shield_hp > 0
	var top_y = y_offset - (bar_height + bar_gap if has_shield else 0.0)

	# Single dark backing panel behind both bars (with a slim light border)
	# instead of just a black rect per-bar - reads as one cohesive readout
	# against busy backgrounds/other mechs instead of two thin stripes that
	# can disappear against similarly dark terrain or silhouettes.
	var panel_pad = 1.5
	var panel_rect = Rect2(
		-bar_width / 2.0 - panel_pad,
		top_y - panel_pad,
		bar_width + panel_pad * 2.0,
		(y_offset + bar_height) - top_y + panel_pad * 2.0
	)
	draw_rect(panel_rect, Color(0.0, 0.0, 0.0, 0.65))
	draw_rect(panel_rect, Color(1.0, 1.0, 1.0, 0.25), false, 1.0)

	# HP bar (always present)
	draw_rect(Rect2(-bar_width / 2.0, y_offset, bar_width, bar_height), Color(0.12, 0.12, 0.12))
	var hp_color = Color(0.25, 0.9, 0.3) if owner_mech.is_player else Color(0.9, 0.2, 0.2)
	if hp_pct > 0.0:
		draw_rect(Rect2(-bar_width / 2.0, y_offset, bar_width * hp_pct, bar_height), hp_color)

	# Shield bar (only when this mech actually has shield capacity)
	if has_shield:
		var shld_y = y_offset - bar_height - bar_gap
		draw_rect(Rect2(-bar_width / 2.0, shld_y, bar_width, bar_height), Color(0.12, 0.12, 0.12))
		if shld_pct > 0.0:
			draw_rect(Rect2(-bar_width / 2.0, shld_y, bar_width * shld_pct, bar_height), Color(0.3, 0.65, 1.0))
