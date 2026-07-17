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

# Corporate Sponsorships (task #17): Shadow Systems' Cloak (C) toggle state -
# only meaningful when mech.shadow_toggle_mode is true (see tick()'s player
# input branch). Lives here rather than on Mech since it's pure per-frame
# input-tracking state, same category as everything else this class owns.
var toggle_state: bool = false

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

	# Corporate Sponsorships: external_cloak_timer decays regardless of
	# whether THIS mech owns a cloak generator - it's refreshed by a nearby
	# Shadow-equipped ally's own _share_cloak_with_allies() pulse (see below),
	# and is what lets an ally with no cloak generator of their own still
	# fade out while covered by someone else's field.
	if mech.external_cloak_timer > 0.0:
		mech.external_cloak_timer = max(0.0, mech.external_cloak_timer - delta)

	if not mech.has_cloak_generator:
		if mech.external_cloak_timer <= 0.0:
			if mech.is_cloaked or mech.modulate.a < 1.0:
				mech.is_cloaked = false
				mech.modulate.a = 1.0
			return
		# No cloak generator of our own, but an ally's Shadow field currently
		# covers us - still fade out, just skip every bit of charge/recharge/
		# input logic below (none of it applies without a real generator).
		_apply_fade(delta)
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
			if mech.shadow_toggle_mode:
				# Shadow Systems: Cloak (C) is a toggle, not hold-to-cloak.
				if InputMap.has_action("cloak") and Input.is_action_just_pressed("cloak"):
					toggle_state = not toggle_state
				wants_cloak = toggle_state
			else:
				wants_cloak = InputMap.has_action("cloak") and Input.is_action_pressed("cloak")
		elif mech.target:
			# Ambush AI: stay cloaked while closing in, reveal once at striking range
			wants_cloak = mech.global_position.distance_to(mech.target.global_position) > mech.engagement_distance * 0.9

		if wants_cloak and cloak_charge >= mech.max_cloak_charge * 0.3:
			mech.is_cloaked = true

	_apply_fade(delta)

	# Shadow Systems' ally-share pulse: while actively cloaked, refresh
	# external_cloak_timer on every ally within shadow_share_radius so they
	# fade out too, even without a cloak generator of their own.
	if mech.is_cloaked and mech.shadow_share_radius > 0.0:
		_share_cloak_with_allies()

func _apply_fade(delta: float) -> void:
	var effectively_cloaked = mech.is_cloaked or mech.external_cloak_timer > 0.0
	var target_alpha = 0.3 if effectively_cloaked else 1.0
	# Was 8.0 - converged in under half a second, way too snappy for a
	# "cloak" to read as anything more than a quick flicker. This is a
	# genuinely slow fade now (~2-2.5s to fully settle).
	mech.modulate.a = lerp(mech.modulate.a, target_alpha, 1.2 * delta)

	# The "big distorted circle" visual: a heat-haze shimmer bubble around
	# the cloaked mech (screen-UV displacement shader). Fades in/out with
	# the cloak. Doubles as the ambusher counterplay tell - a player who
	# learns the shimmer can spot an incoming cloaked ambusher. Ally-shared
	# fades get the same tell - a squad going dark together is just as
	# spottable as a lone Ambusher.
	_update_distortion(delta, effectively_cloaked)

# Shadow Systems (task #17): "cloaks any allies you have within X radius"
# (locked design). Same ally-detection split HealBeaconSystem._emit_pulse() already
# uses (AI: squad/"enemy" group; player: companion drones) - refreshes
# external_cloak_timer on everyone in range rather than touching their
# is_cloaked directly, since a target without its own CloakSystem tick
# wouldn't otherwise know to fade back out once coverage lapses.
const ALLY_CLOAK_REFRESH = 0.4 # seconds - reapplied every tick while in range, so this only has to outlast one frame's gap

func _share_cloak_with_allies() -> void:
	var allies: Array = []
	if mech.is_player:
		var main = mech.get_tree().current_scene if mech.is_inside_tree() else null
		if main and "drone_nodes" in main:
			allies = main.drone_nodes.values()
	else:
		allies = EntityCache.get_group("enemy")
	for ally in allies:
		if ally == mech or not is_instance_valid(ally) or not ("external_cloak_timer" in ally):
			continue
		if mech.global_position.distance_to(ally.global_position) > mech.shadow_share_radius:
			continue
		ally.external_cloak_timer = max(ally.external_cloak_timer, ALLY_CLOAK_REFRESH)

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

func _update_distortion(delta: float, effectively_cloaked: bool):
	var target = 1.0 if effectively_cloaked else 0.0
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

const DECLOAK_BURST_RADIUS = 70.0

func break_cloak() -> void:
	if not mech.is_cloaked:
		return
	mech.is_cloaked = false
	time_since_cloak_break = 0.0
	_ambush_window_timer = AMBUSH_WINDOW_DURATION
	_show_decloak_tell()

# Counterplay tell (Status.md backlog): the shimmer bubble above only tells a
# player "something cloaked is nearby" while it's still hidden - there was no
# distinct cue for the reveal MOMENT itself, so an Ambusher's opening hit
# landed with zero warning beyond the shimmer a player had to already be
# watching for. A quick bright ring snapping outward at the exact instant of
# decloak (reusing the same BossTelegraphRing.burst() pattern Mech's Deflector
# shield overflow already uses) gives a sharper, unmissable "it's HERE now"
# moment distinct from the slow ongoing shimmer.
func _show_decloak_tell():
	if not mech.get_parent():
		return
	var ring = load("res://scripts/visuals/BossTelegraphRing.gd").new()
	mech.get_parent().add_child(ring)
	ring.global_position = mech.global_position
	ring.burst(10.0, DECLOAK_BURST_RADIUS, 0.25, Color(0.75, 0.95, 1.0, 1.0))

# Ambush multiplier for whatever damage is about to be dealt. True while
# still cloaked (covers the shot that's actively breaking cloak this call)
# OR while the post-decloak window is running (covers everything else
# within AMBUSH_WINDOW_DURATION seconds of any decloak, regardless of
# cause - see break_cloak).
func get_ambush_multiplier() -> float:
	if mech.is_cloaked or _ambush_window_timer > 0.0:
		return AMBUSH_MULTIPLIER
	return 1.0
