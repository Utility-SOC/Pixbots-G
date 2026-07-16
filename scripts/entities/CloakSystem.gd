class_name CloakSystem
extends RefCounted

# Cloak Generator runtime behavior (Ambusher backpack ability), split out of
# Mech.gd's _update_cloak/_break_cloak/_get_ambush_multiplier block - see
# StatusEffectRunner.gd's header for why this is a composed RefCounted
# rather than a sibling Node (load-bearing _physics_process ordering rules
# that out - see Mech.gd's boss_brain/status_runner/player_controller
# fields for the full explanation).
#
# Capacity/rate fields (has_cloak_generator, max_cloak_charge,
# cloak_recharge_rate, cloak_recharge_delay, cloak_drain_rate) and the
# is_cloaked boolean itself deliberately STAY on Mech, same principle as
# StatusEffectRunner's status_effects dict: _recalculate_grid() writes the
# capacity fields directly on every loadout change (which can happen before
# this system would otherwise ever be constructed), and BossBrain/
# PlayerController read AND write is_cloaked externally, at any time,
# without caring whether a CloakSystem exists yet. Only the per-frame
# charge/timer/visual TICK - the part those external callers never touch
# directly - moved here.

var mech: Mech

# The one field that used to run through max()/min() clamps on Mech every
# frame - now lives here since nothing outside Mech.gd's own two thin
# wrappers (_break_cloak/_get_ambush_multiplier) needs to read it directly.
var cloak_charge: float = 0.0
var time_since_cloak_break: float = 999.0

# Ambush bonus window: any damage dealt within AMBUSH_WINDOW_DURATION
# seconds of a decloak event (from any cause - firing, taking a hit, or
# cloak charge running out, since break_cloak() is the one chokepoint all
# three funnel through) gets AMBUSH_MULTIPLIER applied.
var _ambush_window_timer: float = 0.0
const AMBUSH_WINDOW_DURATION = 0.25
const AMBUSH_MULTIPLIER = 2.5

func _init(p_mech: Mech):
	mech = p_mech

func tick(delta: float) -> void:
	if _ambush_window_timer > 0.0:
		_ambush_window_timer = max(0.0, _ambush_window_timer - delta)

	if not mech.has_cloak_generator:
		if mech.is_cloaked or mech.modulate.a < 1.0:
			mech.is_cloaked = false
			mech.modulate.a = 1.0
		return

	time_since_cloak_break += delta

	if mech.is_cloaked:
		cloak_charge = max(0.0, cloak_charge - mech.cloak_drain_rate * delta)
		if cloak_charge <= 0.0:
			break_cloak()
	elif time_since_cloak_break >= mech.cloak_recharge_delay:
		cloak_charge = min(mech.max_cloak_charge, cloak_charge + mech.cloak_recharge_rate * delta)

		var wants_cloak = false
		if mech.is_player:
			wants_cloak = InputMap.has_action("cloak") and Input.is_action_pressed("cloak")
		elif mech.target:
			# Ambush AI: stay cloaked while closing in, reveal once at striking range
			wants_cloak = mech.global_position.distance_to(mech.target.global_position) > mech.engagement_distance * 0.9

		if wants_cloak and cloak_charge >= mech.max_cloak_charge * 0.3:
			mech.is_cloaked = true

	var target_alpha = 0.3 if mech.is_cloaked else 1.0
	# Was 8.0 - converged in under half a second, way too snappy for a
	# "cloak" to read as anything more than a quick flicker. This is a
	# genuinely slow fade now (~2-2.5s to fully settle).
	mech.modulate.a = lerp(mech.modulate.a, target_alpha, 1.2 * delta)

	# The "big distorted circle" visual: a heat-haze shimmer bubble around
	# the cloaked mech (screen-UV displacement shader). Fades in/out with
	# the cloak. Doubles as the ambusher counterplay tell - a player who
	# learns the shimmer can spot an incoming cloaked ambusher.
	_update_distortion(delta)

const CLOAK_DISTORTION_RADIUS = 80.0
const CLOAK_SHADER_CODE = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float dist = length(centered) * 2.0;
	// 1.0 at the middle, 0 at the rim - the bubble has a soft edge
	float mask = smoothstep(1.0, 0.55, dist);
	// Wobbling ripple rings drifting through the bubble
	float ripple = sin(dist * 22.0 - TIME * 4.0) + sin(centered.x * 18.0 + TIME * 2.3);
	vec2 dir = dist > 0.001 ? centered / dist : vec2(0.0);
	vec2 offset = dir * ripple * 0.012 * strength * mask;
	vec4 scene = texture(screen_tex, SCREEN_UV + offset);
	// Slight cool tint so the bubble reads even over flat terrain
	scene.rgb = mix(scene.rgb, scene.rgb * vec3(0.92, 0.97, 1.05), mask * strength);
	COLOR = vec4(scene.rgb, mask * min(1.0, strength * 3.0));
}"""

var _cloak_distortion: ColorRect = null
var _cloak_distortion_strength: float = 0.0

func _ensure_distortion():
	if _cloak_distortion and is_instance_valid(_cloak_distortion):
		return
	if not mech.get_parent():
		return
	_cloak_distortion = ColorRect.new()
	_cloak_distortion.size = Vector2.ONE * CLOAK_DISTORTION_RADIUS * 2.0
	_cloak_distortion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh = Shader.new()
	sh.code = CLOAK_SHADER_CODE
	var mat = ShaderMaterial.new()
	mat.shader = sh
	_cloak_distortion.material = mat
	# Sibling of the mech, NOT a child: children inherit modulate, so a
	# child bubble would fade out with the cloaking mech - i.e. disappear
	# exactly when it's supposed to be the only visible tell. As a sibling
	# it keeps full opacity and just follows the mech's position.
	mech.get_parent().add_child(_cloak_distortion)
	mech.tree_exiting.connect(func():
		if _cloak_distortion and is_instance_valid(_cloak_distortion):
			_cloak_distortion.queue_free()
	)

func _update_distortion(delta: float):
	var target = 1.0 if mech.is_cloaked else 0.0
	_cloak_distortion_strength = lerp(_cloak_distortion_strength, target, 1.2 * delta)

	if _cloak_distortion_strength < 0.02:
		if _cloak_distortion and is_instance_valid(_cloak_distortion):
			_cloak_distortion.visible = false
		return

	_ensure_distortion()
	if not _cloak_distortion:
		return
	_cloak_distortion.visible = true
	_cloak_distortion.global_position = mech.global_position - _cloak_distortion.size / 2.0
	_cloak_distortion.material.set_shader_parameter("strength", _cloak_distortion_strength)

func break_cloak() -> void:
	if not mech.is_cloaked:
		return
	mech.is_cloaked = false
	time_since_cloak_break = 0.0
	_ambush_window_timer = AMBUSH_WINDOW_DURATION

# Ambush multiplier for whatever damage is about to be dealt. True while
# still cloaked (covers the shot that's actively breaking cloak this call)
# OR while the post-decloak window is running (covers everything else
# within AMBUSH_WINDOW_DURATION seconds of any decloak, regardless of
# cause - see break_cloak).
func get_ambush_multiplier() -> float:
	if mech.is_cloaked or _ambush_window_timer > 0.0:
		return AMBUSH_MULTIPLIER
	return 1.0
