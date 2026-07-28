// naklon_reactive.gdshader
//
// Package D — one reusable PBR-ish spatial shader that blends a Mercy-pole
// look and a Cruelty-pole look live, driven by the `naklon_unit` global
// shader uniform (see naklon_globals.gdshaderinc). Every "generic X reacts
// to Naklon" material in materials/ (rock, timber, fabric) is an instance
// of THIS shader with different uniform presets — the palette lives in the
// .tres, the reactive mechanism lives here once.
//
// Design intent (see docs/systems/art_direction.md for the full style bible):
//   Mercy   -> soft, rounded-reading normals, warm low-contrast light
//              response, low specular, little-to-no surface damage, a
//              faint warm rim light (things look cared for).
//   Cruelty -> harsher specular, cracked/fractured procedural detail with
//              an iron-red ember glow inside the cracks, ash-desaturated
//              base color (things look starved, fractured, and hot at the
//              seams).
// The crack pattern is procedural (naklon_fbm-based), not a texture, so
// this needs no authored art to look right on any mesh/UV set.

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/naklon_globals.gdshaderinc"

// --- base color ---
uniform vec4 albedo_mercy : source_color = vec4(0.42, 0.55, 0.32, 1.0);
uniform vec4 albedo_cruelty : source_color = vec4(0.08, 0.07, 0.07, 1.0);

// --- PBR response ---
uniform float roughness_mercy : hint_range(0.0, 1.0) = 0.75;
uniform float roughness_cruelty : hint_range(0.0, 1.0) = 0.35;
uniform float metallic_mercy : hint_range(0.0, 1.0) = 0.0;
uniform float metallic_cruelty : hint_range(0.0, 1.0) = 0.15;
uniform float specular_mercy : hint_range(0.0, 1.0) = 0.3;
uniform float specular_cruelty : hint_range(0.0, 1.0) = 0.85;

// --- procedural crack/damage detail ---
uniform float crack_amount_mercy : hint_range(0.0, 1.0) = 0.0;
uniform float crack_amount_cruelty : hint_range(0.0, 1.0) = 0.85;
uniform float crack_scale : hint_range(1.0, 64.0) = 12.0;
uniform vec4 crack_glow_color : source_color = vec4(0.72, 0.14, 0.08, 1.0);
uniform float crack_glow_energy : hint_range(0.0, 4.0) = 1.6;

// --- bump (fed by the same crack noise, so damage reads as relief too) ---
uniform float normal_strength_mercy : hint_range(0.0, 2.0) = 0.25;
uniform float normal_strength_cruelty : hint_range(0.0, 2.0) = 1.3;

// --- soft mercy rim light ("things look cared for") ---
uniform vec4 rim_color_mercy : source_color = vec4(1.0, 0.93, 0.78, 1.0);
uniform float rim_mercy : hint_range(0.0, 2.0) = 0.6;
uniform float rim_cruelty : hint_range(0.0, 2.0) = 0.05;

void fragment() {
	vec2 uv = UV;

	float crack_amt = naklon_mix_f(crack_amount_mercy, crack_amount_cruelty);
	float crack_mask = naklon_crack_mask(uv, crack_scale, crack_amt);

	vec3 albedo = naklon_mix_v3(albedo_mercy.rgb, albedo_cruelty.rgb);
	albedo = mix(albedo, albedo * 0.3, crack_mask * 0.7);
	ALBEDO = albedo;

	ROUGHNESS = naklon_mix_f(roughness_mercy, roughness_cruelty);
	METALLIC = naklon_mix_f(metallic_mercy, metallic_cruelty);
	SPECULAR = naklon_mix_f(specular_mercy, specular_cruelty);

	// Fake bump from the crack noise's local gradient — no normal map asset
	// needed, and it stays perfectly aligned with the visible crack mask.
	float nstr = naklon_mix_f(normal_strength_mercy, normal_strength_cruelty);
	float e = 1.0 / max(crack_scale * 8.0, 8.0);
	float n0 = naklon_fbm(uv * crack_scale);
	float nx = naklon_fbm((uv + vec2(e, 0.0)) * crack_scale);
	float ny = naklon_fbm((uv + vec2(0.0, e)) * crack_scale);
	vec3 bump = normalize(vec3(n0 - nx, n0 - ny, 0.6));
	NORMAL_MAP = bump * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = nstr;

	float rim_amt = naklon_mix_f(rim_mercy, rim_cruelty);
	vec3 rim_term = rim_color_mercy.rgb * rim_amt *
		pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);

	EMISSION = crack_glow_color.rgb * crack_mask * crack_glow_energy * (0.35 + 0.9 * naklon_eased()) + rim_term;
}
