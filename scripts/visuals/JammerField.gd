class_name JammerField
extends Node2D

# The visible, spatial replacement for the old full-screen vision-jam dim.
# NOT a stealth effect - a Jammer announces roughly where it is (see
# Mech.gd's jammer-broadcast wiring) while denying the opposing side an
# EXACT position. Standing inside a hostile field makes a mech "Blind" (see
# Mech._update_player_sight / Main._update_player_blind_state) until its
# owner dies or it's left behind - continuously re-evaluated, never a timer.
#
# A real scene-tree Node2D (unlike the BossBrain/StatusEffectRunner/
# PlayerController RefCounted composed-object pattern elsewhere in this
# codebase) - those are non-Nodes specifically to dodge _physics_process
# ordering guarantees, which doesn't apply here. This needs to be an
# independent, group-queryable, self-positioning world object instead,
# same family as PulseRingVisual/BossTelegraphRing/JumpjetResidue.
#
# Shape: 16 boundary points at fixed angles around a lagging "anchor"
# (this node's own global_position). The anchor eases toward the owner's
# real position rather than snapping - sit still and the blob centers
# tightly on you; move fast and it trails behind, which is the whole
# "jammers effectively limit your speed" feel Natalia asked for. Each
# point's radius wobbles via periodic reroll-and-ease noise (organic,
# non-circular boundary) AND gets biased by recent movement direction -
# trailing-side points stretch and linger (slow ease back), leading-edge
# points stay tight (fast ease) - a cheap approximation of "the blob
# prefers space it's recently occupied" (the lightning/plasma analogy)
# without a literal historical-memory grid.

const POINT_COUNT := 16
const ANCHOR_LAG_WEIGHT := 1.8

const REROLL_MIN := 1.2
const REROLL_MAX := 2.2
const WOBBLE_EASE_SPEED := 1.5
const WOBBLE_MIN_MULT := 0.75
const WOBBLE_MAX_MULT := 1.25

const DRAG_STRENGTH := 0.6
const DRAG_REFERENCE_SPEED := 260.0
const DRAG_GROW_EASE := 4.0
const DRAG_SHRINK_EASE := 0.8

const VEL_SMOOTH_RATE := 6.0

# "Smear toward fresh jammed stuff" (Natalia): a secondary stretch bias
# toward wherever this field most recently caught someone, layered on top
# of the movement-drag bias below via the exact same combined-target/ease-
# selection logic - one more additive term on math that already runs every
# frame for all 16 points, not a new system. Decays back to 0 over
# JAM_PULL_DECAY_TIME so only a genuinely FRESH catch pulls the shape, not
# one from several seconds ago. Reported by whichever call site actually
# evaluates is_point_inside() and gets a hit (Mech._update_player_sight for
# the player's own field catching an enemy, Main._update_player_blind_state
# for a hostile field catching the player) - no new physics queries, this
# just taps an event that already happens.
const JAM_PULL_STRENGTH := 0.22
const JAM_PULL_DECAY_TIME := 3.0
var _jam_pull_point: Vector2 = Vector2.ZERO
var _jam_pull_strength: float = 0.0

func report_jam_contact(world_pos: Vector2) -> void:
	_jam_pull_point = world_pos
	_jam_pull_strength = 1.0

var owner_mech: Node = null
var owner_is_player: bool = false
var base_radius: float = 300.0
var lifetime: float = -1.0 # -1 = persistent (freed by owner); >0 = self-timed burst

# --- Multiplicative proximity stacking (Utility-SOC: "if multiple enemy
# jammers are in range of one another they should scale power
# multiplicatively, the closer the higher that multiplicative factor") ---
# Every OTHER same-side field within JAMMER_LINK_RANGE compounds a factor
# into stack_multiplier, stronger the closer the pair - a handful of fields
# clustered tight can legitimately cover a huge area, while a single
# isolated field (or fields spread across the map) stay at baseline. Scanned
# on a slow throttle (not every frame) via EntityCache, same convention as
# Projectile.gd's HOMING_QUERY_INTERVAL-style throttled physics/group
# queries - this is a per-field O(n) group scan, cheap at realistic jammer
# counts but no reason to pay it every tick.
const JAMMER_LINK_RANGE := 500.0
const STACK_FACTOR := 0.6
const STACK_SCAN_INTERVAL := 0.85
var stack_multiplier: float = 1.0
var _stack_scan_timer: float = 0.0

# LOCAL space (relative to this node's own global_position, i.e. the
# anchor) - is_point_inside() and the minimap renderer both consume this
# directly, so the visual boundary IS the gameplay hitbox, no mismatch.
var boundary_points: PackedVector2Array = PackedVector2Array()

var _radius_current: Array = []
var _radius_target: Array = []
var _reroll_timer: Array = []
var _drag_mult_current: Array = []

var _anchor_vel_smoothed: Vector2 = Vector2.ZERO
var _prev_global_pos: Vector2 = Vector2.ZERO
var _distortion: ColorRect = null

# Call BEFORE add_child (same convention as JumpjetResidue/PulseRingVisual
# in this codebase: global_position + setup() first, so the first _process
# tick already has correct state instead of a one-frame pop-in).
func setup(p_owner_mech: Node, p_base_radius: float, p_lifetime: float = -1.0) -> void:
	owner_mech = p_owner_mech
	owner_is_player = is_instance_valid(p_owner_mech) and "is_player" in p_owner_mech and p_owner_mech.is_player
	base_radius = p_base_radius
	lifetime = p_lifetime
	_prev_global_pos = global_position

	_radius_current.resize(POINT_COUNT)
	_radius_target.resize(POINT_COUNT)
	_reroll_timer.resize(POINT_COUNT)
	_drag_mult_current.resize(POINT_COUNT)
	for i in range(POINT_COUNT):
		_radius_current[i] = base_radius
		_radius_target[i] = base_radius
		_reroll_timer[i] = randf_range(REROLL_MIN, REROLL_MAX)
		_drag_mult_current[i] = 1.0

	_rebuild_boundary_points()
	add_to_group("jammer_field")

func _ready():
	_ensure_distortion()

func _process(delta: float):
	if lifetime > 0.0:
		lifetime -= delta
		if lifetime <= 0.0:
			queue_free()
			return

	# Anchor lag: ease toward the owner's real position instead of snapping.
	# A stationary boss burst has no owner_mech, so this is skipped entirely
	# and the field just stays put where it was spawned.
	if is_instance_valid(owner_mech):
		global_position = global_position.lerp(owner_mech.global_position, clamp(ANCHOR_LAG_WEIGHT * delta, 0.0, 1.0))

	_stack_scan_timer -= delta
	if _stack_scan_timer <= 0.0:
		_stack_scan_timer = STACK_SCAN_INTERVAL
		_rescan_stack_multiplier()

	# Smoothed velocity estimate for the directional drag bias below - a
	# single-frame stutter shouldn't spike the whole boundary.
	var raw_vel = Vector2.ZERO
	if delta > 0.0:
		raw_vel = (global_position - _prev_global_pos) / delta
	_prev_global_pos = global_position
	_anchor_vel_smoothed = _anchor_vel_smoothed.lerp(raw_vel, clamp(VEL_SMOOTH_RATE * delta, 0.0, 1.0))

	var speed = _anchor_vel_smoothed.length()
	var move_dir = _anchor_vel_smoothed / speed if speed > 0.01 else Vector2.ZERO
	var speed_factor = clamp(speed / DRAG_REFERENCE_SPEED, 0.0, 1.0)

	if _jam_pull_strength > 0.0:
		_jam_pull_strength = max(0.0, _jam_pull_strength - delta / JAM_PULL_DECAY_TIME)
	var pull_dir = Vector2.ZERO
	if _jam_pull_strength > 0.0:
		pull_dir = (_jam_pull_point - global_position).normalized()

	for i in range(POINT_COUNT):
		# Organic wobble: periodic reroll + ease, independent of movement.
		_reroll_timer[i] -= delta
		if _reroll_timer[i] <= 0.0:
			_reroll_timer[i] = randf_range(REROLL_MIN, REROLL_MAX)
			_radius_target[i] = base_radius * stack_multiplier * randf_range(WOBBLE_MIN_MULT, WOBBLE_MAX_MULT)
		_radius_current[i] = lerp(_radius_current[i], _radius_target[i], clamp(WOBBLE_EASE_SPEED * delta, 0.0, 1.0))

		# Directional drag bias: trailing-side points (opposite movement)
		# stretch and linger; leading-edge points stay tight and snap back
		# fast. This is the "blob prefers space it's recently occupied"
		# feel - velocity-correlated bias with asymmetric ease rates, not a
		# literal memory grid.
		var theta = i * TAU / POINT_COUNT
		var point_dir = Vector2.RIGHT.rotated(theta)
		var alignment = -point_dir.dot(move_dir) if move_dir != Vector2.ZERO else 0.0
		var target_mult = 1.0 + alignment * DRAG_STRENGTH * speed_factor

		if pull_dir != Vector2.ZERO:
			var pull_alignment = max(0.0, point_dir.dot(pull_dir))
			target_mult += pull_alignment * JAM_PULL_STRENGTH * _jam_pull_strength

		var ease = DRAG_GROW_EASE if target_mult > _drag_mult_current[i] else DRAG_SHRINK_EASE
		_drag_mult_current[i] = lerp(_drag_mult_current[i], target_mult, clamp(ease * delta, 0.0, 1.0))

	_rebuild_boundary_points()
	_update_distortion()

# Compounds a closeness-weighted factor for every OTHER same-side field
# within JAMMER_LINK_RANGE - e.g. 5 tightly clustered fields each near the
# max factor compound to roughly (1+STACK_FACTOR)^4 on top of each other's
# baseline, which is how a handful of clustered enemy jammers can credibly
# blanket a large chunk of the map, while a lone or well-spread-out field
# stays at 1.0 (no change from before this feature).
func _rescan_stack_multiplier():
	var factor = 1.0
	for other in EntityCache.get_group("jammer_field"):
		if other == self or not is_instance_valid(other):
			continue
		if other.owner_is_player != owner_is_player:
			continue
		var dist = global_position.distance_to(other.global_position)
		if dist >= JAMMER_LINK_RANGE:
			continue
		var closeness = 1.0 - (dist / JAMMER_LINK_RANGE)
		factor *= 1.0 + STACK_FACTOR * closeness
	stack_multiplier = factor

func _rebuild_boundary_points():
	boundary_points.resize(POINT_COUNT)
	for i in range(POINT_COUNT):
		var theta = i * TAU / POINT_COUNT
		var r = _radius_current[i] * _drag_mult_current[i]
		boundary_points[i] = Vector2.RIGHT.rotated(theta) * r

# Point-in-polygon against the LIVE boundary, re-evaluated by the caller
# every time (no cached "am I inside" state here) - continuously re-checked
# per the "no timer, only leaving/destroying the source clears it" design.
func is_point_inside(world_pos: Vector2) -> bool:
	if boundary_points.size() < 3:
		return false
	return Geometry2D.is_point_in_polygon(world_pos - global_position, boundary_points)

const DISTORTION_SHADER_CODE = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float strength : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float dist = length(centered) * 2.0;
	float mask = smoothstep(1.0, 0.5, dist);
	float ang = atan(centered.y, centered.x);
	// Rotational swirl term (angular, TIME-driven) layered on radial ripple -
	// reads as distinctly "jamming/distortion" rather than cloak's heat haze.
	float swirl = sin(ang * 5.0 + TIME * 1.6 + dist * 3.0) * 0.5
				+ sin(ang * 3.0 - TIME * 2.4) * 0.5;
	vec2 dir = dist > 0.001 ? centered / dist : vec2(0.0);
	vec2 tangent = vec2(-dir.y, dir.x);
	vec2 offset = (dir * swirl * 0.02 + tangent * swirl * 0.03) * strength * mask;
	vec4 scene = texture(screen_tex, SCREEN_UV + offset);
	scene.rgb = mix(scene.rgb, scene.rgb * vec3(0.55, 0.75, 1.15), mask * strength * 0.6);
	COLOR = vec4(scene.rgb, mask * strength);
}
"""

func _ensure_distortion():
	if _distortion:
		return
	_distortion = ColorRect.new()
	var size = base_radius * 3.0
	_distortion.size = Vector2.ONE * size
	_distortion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = DISTORTION_SHADER_CODE
	mat.shader = shader
	mat.set_shader_parameter("strength", 1.0)
	_distortion.material = mat
	add_child(_distortion)

func _update_distortion():
	if not _distortion:
		return
	# Resized every call (not just once at creation) so the visible
	# distortion patch actually grows when stack_multiplier grows - cheap
	# (a Vector2 set on an existing ColorRect, no reallocation).
	var target_size = Vector2.ONE * (base_radius * stack_multiplier * 3.0)
	if _distortion.size != target_size:
		_distortion.size = target_size
	_distortion.position = -_distortion.size / 2.0
