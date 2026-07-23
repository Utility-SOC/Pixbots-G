extends Camera2D

var shake_intensity: float = 0.0
var shake_duration: float = 0.0

# --- Battlefield zoom (the ONE owner of camera.zoom) ------------------------
# There were briefly TWO wheel-zoom systems (this one and a Main.gd one)
# lerping camera.zoom against each other every frame - the "zooms out then
# pops back in" playtest report. Main's was removed; everything lives here.
#
# base_zoom is set by Main at camera creation (1.5 / PIXEL_SHRINK_FACTOR -
# zoom is relative to the internal pixel viewport, not the window).
# The wheel moves a target FACTOR the camera glides toward and snaps onto.
# Zooming out past FACTOR_MIN enters STRATEGIC VIEW (playtest ruling): the
# camera detaches from the pixbot and SNAPS to frame the whole table.
# Wheel-up exits back to tactical follow-cam at max zoom-out.
var base_zoom: float = 0.75
# Lowered from 0.35 - per the user: "could you make it zoom out a little
# more before snapping? It makes a moderate strategic view challenging
# (right now it goes from tactical view to - whole map)." Gives roughly
# 1.75x more zoom-out room in tactical mode before the hard strategic snap.
const FACTOR_MIN = 0.2 # tactical zoom-out limit (~5.0x classic framing)
const FACTOR_MAX = 1.0
const ZOOM_STEP = 1.15
const ZOOM_GLIDE = 9.0 # exponential approach rate per second

var _factor: float = 1.0
var _target_factor: float = 1.0
var strategic: bool = false
var _smoothing_was: bool = true

func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if strategic:
				_exit_strategic()
			else:
				_target_factor = min(FACTOR_MAX, _target_factor * ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if strategic:
				return # already all the way out
			if _target_factor <= FACTOR_MIN + 0.001:
				_enter_strategic()
			else:
				_target_factor = max(FACTOR_MIN, _target_factor / ZOOM_STEP)

func _enter_strategic():
	var maps = get_tree().get_nodes_in_group("map_generator")
	if maps.is_empty():
		return
	var map = maps[0]
	strategic = true
	top_level = true # stop following the pixbot
	_smoothing_was = position_smoothing_enabled
	position_smoothing_enabled = false # ruling: SNAP to the board, no pan
	var map_px = Vector2(map.width, map.height) * map.tile_size
	global_position = map_px / 2.0
	var vp = get_viewport_rect().size
	var fit = min(vp.x / map_px.x, vp.y / map_px.y) * 0.95
	zoom = Vector2.ONE * fit
	reset_smoothing()

func _exit_strategic():
	strategic = false
	top_level = false
	position = Vector2.ZERO
	position_smoothing_enabled = _smoothing_was
	reset_smoothing()
	# Re-enter tactical at max zoom-out; further wheel-ups glide back in.
	_factor = FACTOR_MIN
	_target_factor = FACTOR_MIN

func _process(delta: float):
	if not strategic:
		if _factor != _target_factor:
			# Exponential glide (frame-rate independent) with a hard snap
			# near the target so fractional resting zooms don't shimmer the
			# pixel pipeline.
			var t = 1.0 - exp(-ZOOM_GLIDE * delta)
			_factor = lerpf(_factor, _target_factor, t)
			if abs(_factor - _target_factor) < 0.004:
				_factor = _target_factor
		zoom = Vector2.ONE * base_zoom * _factor

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
