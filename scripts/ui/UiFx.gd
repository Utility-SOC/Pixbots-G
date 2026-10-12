class_name UiFx
extends RefCounted

# Shared panel transitions (Polish lane: "Tween panel transitions as a general pattern"). One short fade plus a tiny
# scale-up, run with TWEEN_PAUSE_PROCESS so it still plays while the tree is paused (every menu pauses the game).
# The end state is always exactly the control's resting state, so a skipped or interrupted tween can't leave a menu
# half transparent; the tween is bound to the control, so freeing the menu mid-fade is safe.

const DURATION = 0.14
const START_SCALE = 0.97

static func pop_in(c: Control, duration: float = DURATION, scale_in: bool = true) -> Tween:
	if c == null or not c.is_inside_tree():
		return null
	var rest_alpha: float = c.modulate.a
	var rest_scale: Vector2 = c.scale
	if c.has_meta("uifx_rest_alpha"): # reopened (possibly mid-fade): keep the real resting state, not the in-between one
		rest_alpha = float(c.get_meta("uifx_rest_alpha"))
		rest_scale = c.get_meta("uifx_rest_scale")
	c.set_meta("uifx_rest_alpha", rest_alpha)
	c.set_meta("uifx_rest_scale", rest_scale)
	c.pivot_offset = c.size * 0.5
	c.modulate.a = 0.0
	if scale_in:
		c.scale = rest_scale * START_SCALE
	var tw := c.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_parallel(true)
	tw.tween_property(c, "modulate:a", rest_alpha, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	if scale_in:
		tw.tween_property(c, "scale", rest_scale, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	return tw

# CanvasLayer menus have no modulate of their own: fade every direct Control child. Fade only: a layer's controls have no
# laid-out size yet when the menu is built, so a centre-pivot scale would pivot on the wrong point.
static func pop_in_layer(layer: CanvasLayer, duration: float = DURATION) -> void:
	for ch in layer.get_children():
		if ch is Control:
			pop_in(ch, duration, false)

# Popup windows (PopupPanel etc.) are not Controls, so fade the content they were given. Call right after popup_centered().
static func pop_in_popup(w: Window, duration: float = DURATION) -> void:
	if w == null or not w.is_inside_tree():
		return
	for ch in w.get_children():
		if ch is Control:
			pop_in(ch, duration, false)
