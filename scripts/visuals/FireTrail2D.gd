class_name FireTrail2D
extends CPUParticles2D

# Fire trail FX. Previously untextured CPUParticles2D - i.e. giant default
# SQUARES at scale 4-12 flickering yellow-to-black ("it is ghastly right
# now" - playtest). Now: a procedural soft radial dot texture (no sprite
# assets - generated once and cached), a real heat ramp (white-hot core ->
# orange -> deep red -> fading smoke), particles that shrink as they cool,
# and gentle upward drift. Shared by fire projectiles and the mount
# preview, so both improve together.

static var _flame_tex: ImageTexture = null

static func _get_flame_texture() -> ImageTexture:
	if _flame_tex:
		return _flame_tex
	var size = 16
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var d = Vector2(x - 7.5, y - 7.5).length() / 7.5
			var a = clamp(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a)) # soft quadratic falloff
	_flame_tex = ImageTexture.create_from_image(img)
	return _flame_tex

func _init():
	texture = _get_flame_texture()
	amount = 24
	lifetime = 0.55
	explosiveness = 0.0
	local_coords = false
	direction = Vector2(0, -1)
	spread = 25.0
	gravity = Vector2(0, -140) # heat rises
	initial_velocity_min = 18.0
	initial_velocity_max = 42.0
	# Texture is 16px, so these are texture multiples now, not raw pixels.
	scale_amount_min = 0.55
	scale_amount_max = 1.1
	# Flames taper as they cool instead of popping out at full size.
	var s_curve = Curve.new()
	s_curve.add_point(Vector2(0.0, 1.0))
	s_curve.add_point(Vector2(0.6, 0.55))
	s_curve.add_point(Vector2(1.0, 0.15))
	scale_amount_curve = s_curve

	# Heat ramp: white-hot birth -> orange body -> deep red -> smoke.
	var grad = Gradient.new()
	grad.offsets = [0.0, 0.22, 0.55, 1.0]
	grad.colors = [
		Color(1.0, 0.97, 0.75, 1.0),  # white-hot core
		Color(1.0, 0.55, 0.1, 0.95),  # orange body
		Color(0.85, 0.16, 0.05, 0.7), # deep red
		Color(0.16, 0.13, 0.12, 0.0), # smoke, fading out
	]
	color_ramp = grad

	# To ensure it stays behind the projectile
	show_behind_parent = true
