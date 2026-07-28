// naklon_globals.gdshaderinc
//
// Package D (art direction) — shared shader plumbing for "everything reacts
// to Naklon." `#include` this file from any .gdshader (spatial or
// canvas_item) that wants to blend a mercy-pole look and a cruelty-pole look
// live, driven by the single scalar `core/naklon.gd` autoload exposes.
//
// This file declares ONE global shader uniform, `naklon_unit`, which mirrors
// `Naklon.unit()` (0.0 = full Mercy, 1.0 = full Cruelty). It is kept in sync
// at runtime by shaders/naklon_shader_driver.gd — see that file's header
// comment for exactly how to wire it into a scene. If no driver has run yet
// (e.g. this shader is opened standalone in the editor), `naklon_unit` just
// uses the default below (0.5, neutral) and nothing errors.
//
// Every helper below is a pure function of `naklon_unit` plus whatever the
// calling shader passes in — no side effects, safe to call from vertex or
// fragment stages.

global uniform float naklon_unit = 0.5;

// ---------------------------------------------------------------------
// Naklon-space mixing helpers
// ---------------------------------------------------------------------

// Linear blend between a mercy-pole value and a cruelty-pole value.
float naklon_mix_f(float mercy_value, float cruelty_value) {
	return mix(mercy_value, cruelty_value, naklon_unit);
}

vec2 naklon_mix_v2(vec2 mercy_value, vec2 cruelty_value) {
	return mix(mercy_value, cruelty_value, naklon_unit);
}

vec3 naklon_mix_v3(vec3 mercy_value, vec3 cruelty_value) {
	return mix(mercy_value, cruelty_value, naklon_unit);
}

vec4 naklon_mix_v4(vec4 mercy_value, vec4 cruelty_value) {
	return mix(mercy_value, cruelty_value, naklon_unit);
}

// Smoothstepped version of naklon_unit — use where you want the transition
// to feel like it accelerates away from neutral rather than being perfectly
// linear (e.g. emission intensity, rim strength).
float naklon_eased() {
	float t = clamp(naklon_unit, 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

// ---------------------------------------------------------------------
// Cheap procedural noise (value noise + fbm) — used for the crack/ash
// detail that reads as "the world is fraying" at the cruelty pole, and can
// double as organic grain/mottling at the mercy pole with amount clamped low.
// ---------------------------------------------------------------------

float naklon_hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float naklon_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = naklon_hash21(i);
	float b = naklon_hash21(i + vec2(1.0, 0.0));
	float c = naklon_hash21(i + vec2(0.0, 1.0));
	float d = naklon_hash21(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// 4-octave fractal value noise, 0..1-ish.
float naklon_fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += amplitude * naklon_noise(p);
		p *= 2.02;
		amplitude *= 0.5;
	}
	return value;
}

// Ridge-thresholded fbm that reads as thin cracks/veins. `amount` (0..1)
// both narrows the ridge (more cracks = thinner, sharper edges look better
// at high amount) and fades the mask out entirely at amount == 0, so it is
// safe to call unconditionally and drive purely by `amount`.
float naklon_crack_mask(vec2 uv, float scale, float amount) {
	float n = naklon_fbm(uv * scale);
	float edge_width = mix(0.24, 0.045, clamp(amount, 0.0, 1.0));
	float ridge = 1.0 - smoothstep(0.0, edge_width, abs(n - 0.5) * 2.0);
	return ridge * clamp(amount, 0.0, 1.0);
}
