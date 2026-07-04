extends Camera2D

var shake_intensity: float = 0.0
var shake_duration: float = 0.0

# --- Battlefield zoom -------------------------------------------------------
# Mouse wheel zooms the game camera out to show more of the table (or back
# in). Camera2D.zoom below 1.0 = wider view. Smooth-lerped so it reads as
# a camera pull, not a snap. NOTE: the minimap consumes wheel events while
# the cursor is over it (accept_event), so the two don't fight.
const ZOOM_MIN = 0.3  # "way more of the game table"
const ZOOM_MAX = 1.5
const ZOOM_STEP = 1.12
var _target_zoom: float = 1.0

func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_zoom = clamp(_target_zoom * ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_zoom = clamp(_target_zoom / ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)

func _process(delta: float):
	var zoom_weight = 8.0 * delta
	if zoom_weight > 1.0: zoom_weight = 1.0
	zoom = zoom.lerp(Vector2.ONE * _target_zoom, zoom_weight)

	if shake_duration > 0.0:
		shake_duration -= delta
		offset = Vector2(
			randf_range(-shake_intensity, shake_intensity),
			randf_range(-shake_intensity, shake_intensity)
		)
		var lerp_weight = 10.0 * delta
		if lerp_weight > 1.0: lerp_weight = 1.0
		shake_intensity = lerp(shake_intensity, 0.0, lerp_weight)
	else:
		offset = Vector2.ZERO
		shake_intensity = 0.0

func shake(intensity: float, duration: float):
	# Base shake is 10 pixels per intensity unit
	shake_intensity = max(shake_intensity, intensity * 10.0)
	shake_duration = max(shake_duration, duration)
