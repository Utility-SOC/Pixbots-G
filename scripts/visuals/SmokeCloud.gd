class_name SmokeCloud
extends Node2D

# Smoke Grenade zone. Passive, like JammerField.gd - it doesn't track who's
# inside it or push anything onto them; MinimapOverlay.gd and
# Mech.apply_damage/apply_part_damage each call is_point_inside() themselves
# whenever they need to know (same "no cached list, callers check" model
# JammerField already established for the identical friend-or-foe-agnostic
# "any mech, not a damage/collision query" shape). Circular check, not a
# wobbly boundary polygon - a thick, mostly-static smoke cloud reads fine as
# a plain circle, and it's one distance comparison instead of a full
# point-in-polygon test at every caller.
#
# GPU migration convention (AAA Polish Roadmap Priority 1): built GPU-only
# from the start, no CPUParticles2D at all - see JumpjetResidue.gd for the
# sibling zone-effect this mirrors.

var radius: float = 320.0
var lifetime: float = 6.0
var timer: float = 0.0

# Fade window at the end of lifetime, seconds - reads as smoke thinning out
# rather than an abrupt pop, same idea as JumpjetResidue's fade-then-free.
const FADE_TIME = 1.5

var _visual: Polygon2D
var _particles: GPUParticles2D

func is_point_inside(world_pos: Vector2) -> bool:
	return global_position.distance_to(world_pos) <= radius

func _ready():
	add_to_group("smoke_cloud")

	_visual = Polygon2D.new()
	var points = PackedVector2Array()
	for j in range(24):
		var angle = j * (TAU / 24.0)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	_visual.polygon = points
	_visual.color = Color(0.6, 0.6, 0.58, 0.55) # thick, opaque-reading grey
	_visual.z_index = 5 # above terrain/mechs, reads as genuinely obscuring
	add_child(_visual)

	_particles = GPUParticles2D.new()
	_particles.amount = 40
	_particles.lifetime = 2.5
	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = radius * 0.9
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 5.0
	mat.initial_velocity_max = 18.0
	mat.gravity = Vector3(0, -6, 0)
	mat.scale_min = 3.0
	mat.scale_max = 6.0
	mat.color = Color(0.75, 0.75, 0.72, 0.65)
	_particles.process_material = mat
	add_child(_particles)

func _physics_process(delta: float):
	timer += delta
	var time_left = lifetime - timer
	if time_left <= FADE_TIME:
		var fade = clamp(time_left / FADE_TIME, 0.0, 1.0)
		modulate.a = fade
		if time_left <= 0.0:
			_particles.emitting = false
			if fade <= 0.0:
				queue_free()
