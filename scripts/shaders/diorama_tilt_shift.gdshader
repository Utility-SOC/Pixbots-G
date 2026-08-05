shader_type canvas_item;

// AAA Polish Roadmap Priority 2 - "Tabletop Diorama Shader" (Pillar II item
// 3). Applied directly to the pixel viewport's SubViewportContainer
// (Main._setup_pixel_viewport()) rather than a separate fullscreen
// ColorRect + SCREEN_TEXTURE overlay - the container already presents
// exactly the diegetic tabletop scene as its own TEXTURE, one layer below
// hud_canvas, so this reads only the game world and never touches HUD text.
// Flat GPU cost regardless of scene complexity (a fixed number of texture
// taps per screen pixel), and reinforces the locked "20mm miniatures on a
// 4x8ft tabletop mat" fantasy (Status.md Section 1) instead of being purely
// cosmetic - the whole point is to make the battlefield read as something
// photographed on a table, not a flat 2D scene.
//
// Two effects, both classic tilt-shift-photography signatures:
// 1. A vertical-only blur that grows with distance from a horizontal
//    in-focus band - directional (not a circular/omnidirectional blur)
//    because that's what an actual tilted lens does: it blurs perpendicular
//    to the focal plane, not uniformly in every direction.
// 2. A vignette darkening the corners, so the eye reads the mat's center
//    (where the fight actually is) as the "in frame" subject.

uniform float focus_center : hint_range(0.0, 1.0) = 0.5;
uniform float focus_size : hint_range(0.0, 0.5) = 0.34;
uniform float blur_strength : hint_range(0.0, 0.02) = 0.002;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.35;
uniform float vignette_radius : hint_range(0.0, 1.5) = 0.75;
uniform float vignette_softness : hint_range(0.01, 1.5) = 0.5;

void fragment() {
	float dist_from_focus = abs(UV.y - focus_center);
	// 0 inside the sharp focus band, ramping to 1 by the screen edge.
	float blur_amount = clamp((dist_from_focus - focus_size) / max(0.0001, 0.5 - focus_size), 0.0, 1.0);
	float radius = blur_amount * blur_strength;

	// 5-tap vertical blur, weights summing to 1.0 - at radius 0 every tap
	// samples the identical UV, so the in-focus band is untouched.
	vec4 col = texture(TEXTURE, UV) * 0.4;
	col += texture(TEXTURE, UV + vec2(0.0, radius)) * 0.24;
	col += texture(TEXTURE, UV - vec2(0.0, radius)) * 0.24;
	col += texture(TEXTURE, UV + vec2(0.0, radius * 2.0)) * 0.06;
	col += texture(TEXTURE, UV - vec2(0.0, radius * 2.0)) * 0.06;

	float d = distance(UV, vec2(0.5));
	float vignette = 1.0 - smoothstep(vignette_radius - vignette_softness, vignette_radius, d) * vignette_strength;
	col.rgb *= vignette;

	COLOR = col;
}
