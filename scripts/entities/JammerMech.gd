extends "res://scripts/entities/Mech.gd"

var jammer_radius: float = 800.0
var jammer_power: float = 0.5 # 50% reduction early game
var is_jamming: bool = false

# Domain-of-effect ring color - SupportMech overrides this to teal so
# players can visually tell "this one heals/protects/jams" from "this one is
# muting my damage" at a glance (was previously done by re-tinting a filled
# Polygon2D disc; see _draw() below for why that's gone).
var ring_glow_color: Color = Color(0.3, 0.65, 1.0)

# Draw-batching (task #14): _draw() below issues 3 draw_arc calls at 64
# segments each (SupportMech's own _draw() adds 2 more on top via super) -
# was queue_redraw()'d unconditionally every _process tick. The pulse it's
# animating (see _draw()) has a ~1s period (sin(msec/150)), so redrawing
# at 60Hz captures motion nobody can perceive between frames - same
# "redraw throttle" idea already applied to MinimapOverlay/GarageGridRenderer.
# Randomized starting offset (not synced to 0) so every Jammer/Support on
# the field doesn't redraw on the exact same tick - same desync trick
# Projectile.gd already uses for its homing/vortex query timers.
const REDRAW_HZ = 20.0
var _redraw_timer: float = 0.0

func _ready():
	super._ready()

	# Calculate scaling power reduction based on current wave
	var main = get_tree().current_scene
	if main and "current_wave" in main:
		# Starts at 0.5 (50%), reaches 0.1 (90% reduction) around wave 30+
		jammer_power = max(0.1, 0.5 - (main.current_wave * 0.015))
	z_index = -5
	_redraw_timer = randf() * (1.0 / REDRAW_HZ)

func _process(delta: float):
	if is_instance_valid(target) and target.has_method("apply_jammer_debuff"):
		var dist = global_position.distance_to(target.global_position)
		is_jamming = dist <= jammer_radius
		if is_jamming:
			target.apply_jammer_debuff(jammer_power)
	else:
		is_jamming = false
	_redraw_timer -= delta
	if _redraw_timer <= 0.0:
		_redraw_timer = 1.0 / REDRAW_HZ
		queue_redraw()

# Glowing boundary-outline visual for the aura's domain of effect - was a
# flat translucent filled disc (dimmed the whole interior with no clear
# edge, and wasn't reliably kept in sync with jammer_radius); this draws
# directly at the real radius so the boundary itself is what's legible.
# Layered stroke widths/alphas fake a soft glow since this project has no
# WorldEnvironment/bloom - same idiom PulseRingVisual.gd already uses for
# its expanding-ring effect.
func _draw():
	var pulse = 0.5 + sin(Time.get_ticks_msec() / 150.0) * 0.2
	var intensity = 1.0 if is_jamming else 0.5
	var c = ring_glow_color
	draw_arc(Vector2.ZERO, jammer_radius, 0.0, TAU, 64, Color(c.r, c.g, c.b, 0.10 * pulse * intensity), 14.0, true)
	draw_arc(Vector2.ZERO, jammer_radius, 0.0, TAU, 64, Color(c.r, c.g, c.b, 0.22 * pulse * intensity), 7.0, true)
	draw_arc(Vector2.ZERO, jammer_radius, 0.0, TAU, 64, Color(c.r, c.g, c.b, 0.55 * intensity), 2.0, true)
