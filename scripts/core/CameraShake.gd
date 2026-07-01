extends Camera2D

var shake_intensity: float = 0.0
var shake_duration: float = 0.0

func _process(delta: float):
	if shake_duration > 0.0:
		shake_duration -= delta
		offset = Vector2(
			randf_range(-shake_intensity, shake_intensity),
			randf_range(-shake_intensity, shake_intensity)
		)
		shake_intensity = lerp(shake_intensity, 0.0, 10.0 * delta)
	else:
		offset = Vector2.ZERO
		shake_intensity = 0.0

func shake(intensity: float, duration: float):
	# Base shake is 10 pixels per intensity unit
	shake_intensity = max(shake_intensity, intensity * 10.0)
	shake_duration = max(shake_duration, duration)
