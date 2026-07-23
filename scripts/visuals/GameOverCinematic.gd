extends CanvasLayer

# Task #12: game-over explosion + crater cinematic. DeathExplosion.gd
# already handles the shockwave/particles/crater decal - this adds the
# beat AROUND it: a brief slow-motion dip, the battle camera pushing in
# toward the crater instead of staying locked to the (now invisible, frozen)
# player, and a "GAME OVER" title card. Additive, not a replacement -
# Main.gd's existing 3-second Timer -> _open_garage() flow (current_wave
# reset, enemy cleanup, get_tree().paused = true) is untouched; this runs
# alongside it purely for presentation, and fully finishes (including
# restoring Engine.time_scale to 1.0) well before that 3-second mark, so
# nothing here is still running once the world pauses for the Garage.
# Self-contained/fire-and-forget, same shape as DeathExplosion.gd.

const SLOWMO_SCALE = 0.3
const SLOWMO_DURATION = 0.5 # sim-seconds - real time is longer while slow
# Divides zoom, doesn't multiply it - in this codebase's Camera2D
# convention a SMALLER zoom value shows MORE of the map (see
# CameraShake._enter_strategic: it sets zoom to viewport_size/map_size, a
# tiny value, specifically to frame the WHOLE map = zoomed OUT), so pushing
# IN toward the crater means dividing zoom down, not multiplying it up.
const CAMERA_PUSH_ZOOM_DIV = 1.35
const LABEL_FADE_DELAY = 0.3
const LABEL_FADE_DURATION = 0.6

var death_position: Vector2 = Vector2.ZERO

func _ready():
	var label = Label.new()
	label.text = "GAME OVER"
	label.add_theme_font_size_override("font_size", 64)
	label.add_theme_color_override("font_color", Color(0.9, 0.15, 0.15))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 8)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.modulate.a = 0.0
	add_child(label)

	var label_tween = create_tween()
	label_tween.tween_property(label, "modulate:a", 1.0, LABEL_FADE_DURATION).set_delay(LABEL_FADE_DELAY)

	Engine.time_scale = SLOWMO_SCALE
	var scale_tween = create_tween()
	scale_tween.tween_interval(SLOWMO_DURATION)
	scale_tween.tween_callback(func(): Engine.time_scale = 1.0)

	var cameras = get_tree().get_nodes_in_group("camera")
	if not cameras.is_empty():
		var camera: Camera2D = cameras[0]
		camera.top_level = true # detach from the frozen player, same trick CameraShake._enter_strategic uses
		camera.position_smoothing_enabled = false
		var cam_tween = create_tween()
		cam_tween.set_parallel(true)
		cam_tween.tween_property(camera, "global_position", death_position, 0.6)
		cam_tween.tween_property(camera, "zoom", camera.zoom / CAMERA_PUSH_ZOOM_DIV, 0.6)

	# Self-free once every animation above has had time to finish (label
	# fade is the longest at delay+duration) - well inside Main.gd's
	# 3-second window, so this is gone before the Garage-open pause.
	var cleanup_timer = get_tree().create_timer(LABEL_FADE_DELAY + LABEL_FADE_DURATION + 0.1)
	cleanup_timer.timeout.connect(queue_free)
