shader_type spatial;
// LOW-SPEC PATH (see docs/systems/performance_lowspec.md). Three changes from
// how this shipped, none cosmetic:
//
//  * NO hint_screen_texture / hint_depth_texture. Declaring either makes
//    Godot perform a full-screen buffer copy every frame the material is
//    visible, whether or not the sample is branched around. That is the
//    single most expensive thing this project removed from the ocean, and a
//    handful of river ribbons must not quietly reintroduce it.
//  * `blend_mix` dropped and `ALPHA` no longer written. Writing ALPHA at all
//    marks the surface transparent: no depth prepass, no early-Z,
//    back-to-front sorting. The river was never see-through.
//  * `cull_disabled` -> `cull_back`. A ribbon is a single layer, so with
//    culling off its front and back faces land at identical depth and which
//    one survives is arbitrary — and Godot flips the shading normal on a
//    back face. That is exactly the bug that made the terrain render as if
//    lit from below for days (see island_generator.gd's winding comment).
render_mode world_vertex_coords, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// TITHE & TERROR — narrow river / coastline-inlet water.
//
// Same Gerstner-sum + depth-fade-foam + fresnel approach as
// world/ocean/ocean.gdshader, tuned for short, steep, fast ripples
// aligned to a flow direction instead of open-sea swell, plus a
// flow-direction UV scroll and bank-edge foam (UV.x is 0/1 at the two
// banks, UV.y runs along the spline length — see
// world/ocean/river_surface.gd, which builds this mesh from an array of
// Vector3 control points and fills these uniforms). See
// docs/systems/ocean.md for the full uniform reference.

#include "res://world/ocean/gerstner_common.gdshaderinc"

group_uniforms Waves;
uniform vec4 wave_dir_len_steep[6];
uniform vec2 wave_amp_speed[6];
uniform float crest_reference_height = 0.18;

group_uniforms Flow;
// Unit-ish direction of water travel in world XZ (set from the spline's
// start->end direction by river_surface.gd); scrolls the micro-detail and
// foam noise so the surface visibly flows downstream.
uniform vec2 flow_direction = vec2(0.0, 1.0);
uniform float flow_time = 0.0;
uniform float flow_uv_scale = 0.6;

group_uniforms Surface_Color;
// Deliberately pushed toward blue and away from the green the terrain now
// is. The authored teal-green was almost exactly the colour of the grass it
// runs through, so from god view a river read as a slightly shinier stripe of
// grass. Contrast against what surrounds it is what makes water legible at
// that distance — see docs/systems/worldbuilding_practices.md on value and
// hue separation being the thing top-down readability actually needs.
uniform vec4 color_shallow : source_color = vec4(0.30, 0.55, 0.66, 1.0);
uniform vec4 color_deep : source_color = vec4(0.05, 0.20, 0.34, 1.0);
uniform float depth_fade_distance = 2.0;
uniform float refraction_strength = 0.03;

group_uniforms Foam;
uniform vec4 foam_color : source_color = vec4(0.92, 0.96, 0.97, 1.0);
uniform float foam_distance = 0.35;
// Fraction of the channel's UV.x width (each bank) that always foams —
// river/inlet edges are shallow and turbulent even with no nearby object.
uniform float bank_foam_width = 0.12;
uniform float foam_noise_scale = 1.4;
uniform float foam_crest_threshold = 0.55;
uniform float foam_crest_softness = 0.3;

group_uniforms Micro_Detail;
uniform float micro_normal_strength = 0.22;
uniform float micro_normal_scale = 3.0;

group_uniforms Reflection;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.1;
uniform float fresnel_power = 4.0;
uniform vec3 fresnel_tint : source_color = vec3(0.8, 0.85, 0.86);

// Deliberately no depth/screen samplers — see the render_mode note above.
// A river's cross-section depth is known from the ribbon's own UV.x (0 at one
// bank, 1 at the other), which is free and does not need the depth buffer.

varying vec2 v_world_xz;
varying float v_wave_height_norm;
varying vec2 v_uv;

void calculate_gerstner_river(vec2 pos, float t, out vec3 displacement, out vec3 normal) {
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
	calculate_gerstner_river(base_xz, TIME, displacement, wave_normal);

	VERTEX += displacement;
	NORMAL = wave_normal;

	v_world_xz = base_xz;
	v_wave_height_norm = clamp((displacement.y / max(crest_reference_height, 0.001)) * 0.5 + 0.5, 0.0, 1.0);
	v_uv = UV;
}

void fragment() {
	// Cross-channel depth straight from the ribbon UV: 0 at either bank, 1
	// mid-stream. This replaces the scene-depth read and is arguably more
	// correct for a river anyway — a watercourse is deepest in its middle by
	// definition, whereas the depth buffer only knew how far the bed happened
	// to be behind the surface.
	float bank_dist = min(v_uv.x, 1.0 - v_uv.x) * 2.0; // 0 bank .. 1 centre
	float shallow_mix = smoothstep(0.0, 1.0, bank_dist);
	vec3 base_color = mix(color_shallow.rgb, color_deep.rgb, shallow_mix);

	vec2 flow_uv = v_uv * flow_uv_scale + flow_direction * flow_time;
	vec2 e = vec2(0.1, 0.0);
	float n_c = fbm(flow_uv * micro_normal_scale, 3);
	float n_x = fbm((flow_uv + e.xy) * micro_normal_scale, 3);
	float n_z = fbm((flow_uv + e.yx) * micro_normal_scale, 3);
	vec3 micro_n = vec3(n_c - n_x, 1.0, n_c - n_z);
	vec3 shaded_normal = normalize(NORMAL + micro_n * micro_normal_strength * vec3(1.0, 0.0, 1.0));

	// Foam at the banks and on wave crests. The old shore_foam term needed
	// scene depth and is folded into bank_foam, which is the same idea.
	float bank_foam = 1.0 - smoothstep(0.0, bank_foam_width * 2.0, bank_dist);
	float crest_foam = smoothstep(foam_crest_threshold, foam_crest_threshold + foam_crest_softness, v_wave_height_norm);
	float foam_mask = clamp(bank_foam + crest_foam, 0.0, 1.0);
	float breakup = fbm(flow_uv * foam_noise_scale, 3);
	foam_mask *= mix(0.6, 1.0, breakup);

	vec3 final_color = mix(base_color, foam_color.rgb, clamp(foam_mask, 0.0, 1.0));

	float fresnel = pow(1.0 - clamp(dot(shaded_normal, VIEW), 0.0, 1.0), fresnel_power);
	final_color = mix(final_color, mix(final_color, fresnel_tint, 0.5), fresnel);

	ALBEDO = final_color;
	NORMAL = shaded_normal;
	ROUGHNESS = mix(roughness_base, 0.85, foam_mask);
	METALLIC = 0.02;
	SPECULAR = mix(0.5, 0.1, foam_mask);
}

