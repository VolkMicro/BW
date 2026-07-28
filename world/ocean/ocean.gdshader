shader_type spatial;
render_mode world_vertex_coords, blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// TITHE & TERROR — open-ocean surface.
//
// Six-wave Gerstner sum computed entirely in VERTEX (real geometric
// displacement, not a normal-map trick), depth-fade shoreline/object foam
// plus wave-crest whitecaps, a depth-tinted "subsurface" color gradient
// with a cheap screen-space refraction blend, and fresnel-weighted
// reflection response. Driven by world/ocean/ocean_surface.gd, which
// builds the subdivided PlaneMesh this is applied to and fills the two
// wave uniform arrays from a GerstnerWaveSet resource — see
// docs/systems/ocean.md for the full uniform reference and tuning notes,
// and world/ocean/river.gdshader for the narrow-water variant.

#include "res://world/ocean/gerstner_common.gdshaderinc"

group_uniforms Waves;
// wave_dir_len_steep[i] = vec4(direction.x, direction.y, wavelength_m, steepness_0_1)
// wave_amp_speed[i]      = vec2(amplitude_m, phase_speed)
// Populated by OceanSurface from a GerstnerWaveSet — see
// GerstnerWaveSet.to_shader_dir_len_steep()/to_shader_amp_speed(). An
// entry with amplitude <= 0 is treated as inert (skipped), so fewer than
// 6 active waves is fine.
uniform vec4 wave_dir_len_steep[6];
uniform vec2 wave_amp_speed[6];
// Rough "how tall does a wave get" reference used only to normalize the
// whitecap crest mask below (0..1); does not affect the physical wave sum.
uniform float crest_reference_height = 1.6;

group_uniforms Surface_Color;
uniform vec4 color_shallow : source_color = vec4(0.263, 0.616, 0.576, 1.0);
uniform vec4 color_deep : source_color = vec4(0.016, 0.078, 0.153, 1.0);
// Meters of "scene depth below the water surface" over which the color
// fully transitions from color_shallow to color_deep.
uniform float depth_fade_distance = 6.0;
// How strongly the fragment normal bends the screen-texture sample
// (cheap fake refraction), scaled by how shallow the water is.
uniform float refraction_strength = 0.04;

group_uniforms Foam;
uniform vec4 foam_color : source_color = vec4(0.92, 0.96, 0.97, 1.0);
// Meters of depth-diff within which shoreline/object foam appears.
uniform float foam_distance = 0.65;
uniform float foam_noise_scale = 0.4;
// v_wave_height_norm threshold (0..1) above which a wave crest gets a
// whitecap, and how soft that threshold's edge is.
uniform float foam_crest_threshold = 0.6;
uniform float foam_crest_softness = 0.35;

group_uniforms Micro_Detail;
// Small fbm-driven normal perturbation layered on top of the analytic
// Gerstner normal so the low-poly mesh doesn't look faceted at grazing
// angles; not a real normal-map texture (see docs' "Assets used").
uniform float micro_normal_strength = 0.18;
uniform float micro_normal_scale = 1.6;

group_uniforms Reflection;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.06;
uniform float fresnel_power = 5.0;
uniform vec3 fresnel_tint : source_color = vec3(0.75, 0.82, 0.86);

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

varying vec2 v_world_xz;
varying float v_wave_height_norm;

// Sums wave_dir_len_steep/wave_amp_speed (this file's own uniforms) into a
// vertex displacement + analytic surface normal. Kept local (rather than
// in the shared include) to avoid passing whole arrays as shader function
// parameters — see docs/systems/ocean.md for why.
void calculate_gerstner_ocean(vec2 pos, float t, out vec3 displacement, out vec3 normal) {
	displacement = vec3(0.0);
	normal = vec3(0.0, 1.0, 0.0);

	float active_waves = 0.0;
	for (int i = 0; i < 6; i++) {
		if (wave_amp_speed[i].x > 0.0001) {
			active_waves += 1.0;
		}
	}
	active_waves = max(active_waves, 1.0);

	for (int i = 0; i < 6; i++) {
		float amplitude = wave_amp_speed[i].x;
		if (amplitude <= 0.0001) {
			continue;
		}
		float speed = wave_amp_speed[i].y;
		vec2 dir = normalize(wave_dir_len_steep[i].xy);
		float wavelength = max(wave_dir_len_steep[i].z, 0.01);
		float steepness = clamp(wave_dir_len_steep[i].w, 0.0, 1.0);

		float k = TAU_W / wavelength;
		float f = k * dot(dir, pos) + t * speed;
		float qi = steepness / (k * amplitude * active_waves);

		displacement.x += qi * amplitude * dir.x * cos(f);
		displacement.z += qi * amplitude * dir.y * cos(f);
		displacement.y += amplitude * sin(f);

		float wa = k * amplitude;
		normal.x -= dir.x * wa * cos(f);
		normal.z -= dir.y * wa * cos(f);
		normal.y -= qi * wa * sin(f);
	}

	normal = normalize(normal);
}

void vertex() {
	vec2 base_xz = VERTEX.xz;
	vec3 displacement;
	vec3 wave_normal;
	calculate_gerstner_ocean(base_xz, TIME, displacement, wave_normal);

	VERTEX += displacement;
	NORMAL = wave_normal;

	v_world_xz = base_xz;
	v_wave_height_norm = clamp((displacement.y / max(crest_reference_height, 0.001)) * 0.5 + 0.5, 0.0, 1.0);
}

void fragment() {
	float raw_depth = texture(depth_texture, SCREEN_UV).r;
	float scene_depth = linearize_depth(raw_depth, SCREEN_UV, INV_PROJECTION_MATRIX);
	float water_depth = -VERTEX.z;
	float depth_diff = max(scene_depth - water_depth, 0.0);

	float shallow_mix = clamp(depth_diff / max(depth_fade_distance, 0.001), 0.0, 1.0);
	vec3 water_color = mix(color_shallow.rgb, color_deep.rgb, shallow_mix);

	vec2 refract_uv = clamp(SCREEN_UV + NORMAL.xz * refraction_strength * shallow_mix, vec2(0.001), vec2(0.999));
	vec3 refracted = texture(screen_texture, refract_uv).rgb;
	vec3 base_color = mix(refracted, water_color, clamp(shallow_mix * 1.4, 0.0, 1.0));

	// Small procedural ripple detail (no external normal map — see docs).
	// `fbm()` is evaluated at full frequency per-fragment with no mip/LOD
	// concept of its own, so from a wide god-view distance (one fragment
	// covering many meters of world space) it aliases into a repeating,
	// tiled-looking pattern rather than a blur — worse still under this
	// project's software `llvmpipe` rasterizer, which has no analytic
	// filtering to soften it (docs/rendering.md). `detail_fade` rolls the
	// micro-normal and foam-breakup terms down with distance to camera —
	// standard "fade detail with distance" practice — while leaving
	// close-up behavior (the only range `world/ocean/ocean_demo.tscn` was
	// ever screenshotted at) completely unchanged.
	float dist_to_cam = length(VERTEX - CAMERA_POSITION_WORLD);
	float detail_fade = 1.0 - smoothstep(40.0, 150.0, dist_to_cam);

	vec2 e = vec2(0.08, 0.0);
	float n_c = fbm(v_world_xz * micro_normal_scale + TIME * 0.05, 4);
	float n_x = fbm((v_world_xz + e.xy) * micro_normal_scale + TIME * 0.05, 4);
	float n_z = fbm((v_world_xz + e.yx) * micro_normal_scale + TIME * 0.05, 4);
	vec3 micro_n = vec3(n_c - n_x, 1.0, n_c - n_z);
	vec3 shaded_normal = normalize(NORMAL + micro_n * micro_normal_strength * detail_fade * vec3(1.0, 0.0, 1.0));

	float shore_foam = 1.0 - smoothstep(0.0, foam_distance, depth_diff);
	float crest_foam = smoothstep(foam_crest_threshold, foam_crest_threshold + foam_crest_softness, v_wave_height_norm);
	float foam_mask = clamp(shore_foam + crest_foam, 0.0, 1.0);
	float breakup = mix(1.0, fbm(v_world_xz * foam_noise_scale + TIME * 0.15, 4), detail_fade);
	foam_mask *= mix(0.65, 1.0, breakup);

	vec3 final_color = mix(base_color, foam_color.rgb, clamp(foam_mask, 0.0, 1.0));

	// fresnel responds to shaded_normal, which tilts through the same exact
	// six-wave periodic cycle everywhere on the plane — at the shallow,
	// distant grazing angles a wide god-view uses over hundreds of meters
	// of open water, that periodic tilt reads as a regular light/dark band
	// pattern (this is the dominant driver of the "tiled" look, more than
	// the specular term above: it persists even at high ROUGHNESS since
	// fresnel here is a albedo-mix, not a specular lobe). Capping the
	// grazing-angle falloff distance itself (fewer terms need dot(N,V)→0
	// to read as "fully grazing") softens that periodic band into a
	// gentler, less regularly-repeating gradient without changing the
	// close-range fresnel rim ocean_demo.tscn was tuned against.
	float fresnel_dot = clamp(dot(shaded_normal, VIEW), mix(0.0, 0.25, 1.0 - detail_fade), 1.0);
	float fresnel = pow(1.0 - fresnel_dot, fresnel_power);
	final_color = mix(final_color, mix(final_color, fresnel_tint, 0.6), fresnel);

	// The analytic Gerstner normal itself is periodic by construction (six
	// summed waves, each an exact sine), and specular response to a
	// periodic normal at a distance/grazing angle aliases into a repeating
	// moire of bright flecks — a harder, separate problem from the fbm
	// detail faded above (this persists even with micro-detail fully faded
	// out at long range). The standard mitigation for specular aliasing
	// on a surface a mip/LOD can't help (there is no texture here to mip)
	// is to broaden the effective roughness with distance so the
	// highlight spreads out instead of aliasing into sharp, per-fragment
	// on/off flecks — a real light-response change, not a texture fix.
	float distance_roughen = mix(0.5, 0.0, detail_fade);

	ALBEDO = final_color;
	NORMAL = shaded_normal;
	ROUGHNESS = clamp(mix(roughness_base, 0.85, foam_mask) + distance_roughen, 0.0, 1.0);
	METALLIC = 0.02;
	SPECULAR = mix(0.5, 0.1, foam_mask);
	ALPHA = 1.0;
}
