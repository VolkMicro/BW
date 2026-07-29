shader_type spatial;
// NOTE the render_mode change (low-spec pass, see docs/systems/performance_lowspec.md):
// `blend_mix` was dropped and `ALPHA = 1.0` was removed from fragment().
// Writing ALPHA at all is what marks a Godot 4 spatial shader as
// alpha-using, which pushes the whole surface into the TRANSPARENT render
// list — no depth prepass, no early-Z rejection, back-to-front sorting, and
// (on Forward+) a place in the pass that needs the screen copy. This ocean
// is an 800x800 m plane that fills most of a god-view frame and was never
// actually see-through (ALPHA was a hard-coded 1.0), so it was paying the
// entire transparent-pass tax for nothing. It is now a normal opaque
// surface: it writes depth, gets early-Z, and occludes everything behind it.
render_mode world_vertex_coords, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// TITHE & TERROR — open-ocean surface.
//
// Six-wave Gerstner sum computed entirely in VERTEX (real geometric
// displacement, not a normal-map trick), shoreline/crest foam, a
// depth-tinted "subsurface" color gradient and fresnel-weighted reflection
// response. Driven by world/ocean/ocean_surface.gd, which builds the
// subdivided PlaneMesh this is applied to and fills the two wave uniform
// arrays from a GerstnerWaveSet resource — see docs/systems/ocean.md for
// the full uniform reference and tuning notes, and world/ocean/river.gdshader
// for the narrow-water variant.
//
// ---------------------------------------------------------------------
// TWO COMPILE-TIME QUALITY PATHS (added by the low-spec pass)
// ---------------------------------------------------------------------
// As checked in, this file compiles to the CHEAP path. The expensive
// screen-space refraction + scene-depth shoreline fade only exists when the
// preprocessor symbol OCEAN_HIGH_QUALITY is defined.
//
// Why a *compile-time* switch and not a `uniform bool`: in Godot 4 the
// renderer decides whether to perform a full-screen back-buffer copy (for
// hint_screen_texture) and a depth-buffer copy (for hint_depth_texture) by
// inspecting whether the compiled shader *declares* those samplers at all.
// A runtime `if` around the sampling still declares them, so the copies
// still happen every frame, for every frame this material is visible. On an
// integrated GPU sharing system memory bandwidth with the CPU, two
// full-render-resolution copies plus the render-pass break they force are
// exactly the kind of cost that has to disappear entirely, not be branched
// around. Defining the symbol is done by OceanSurface (see
// `high_quality_water` there), which prepends `#define OCEAN_HIGH_QUALITY`
// to this source and compiles it as a separate Shader at runtime. Loading
// this .gdshader directly as a resource — which is what any .tscn material
// reference does — always gets the cheap path.

#include "res://world/ocean/gerstner_common.gdshaderinc"

#ifdef OCEAN_HIGH_QUALITY
	#define OCEAN_FBM_OCTAVES 4
#else
	#define OCEAN_FBM_OCTAVES 2
#endif

group_uniforms Waves;
// wave_dir_len_steep[i] = vec4(direction.x, direction.y, wavelength_m, steepness_0_1)
// wave_amp_speed[i]      = vec2(amplitude_m, phase_speed)
// Populated by OceanSurface from a GerstnerWaveSet — see
// GerstnerWaveSet.to_shader_dir_len_steep()/to_shader_amp_speed(). An
// entry with amplitude <= 0 is treated as inert (skipped), so fewer than
// 6 active waves is fine — the low-spec path deliberately sends fewer.
uniform vec4 wave_dir_len_steep[6];
uniform vec2 wave_amp_speed[6];
// Rough "how tall does a wave get" reference used only to normalize the
// whitecap crest mask below (0..1); does not affect the physical wave sum.
uniform float crest_reference_height = 1.6;

group_uniforms Surface_Color;
uniform vec4 color_shallow : source_color = vec4(0.263, 0.616, 0.576, 1.0);
uniform vec4 color_deep : source_color = vec4(0.016, 0.078, 0.153, 1.0);
// Meters of "scene depth below the water surface" over which the color
// fully transitions from color_shallow to color_deep. HIGH path only.
uniform float depth_fade_distance = 6.0;
// How strongly the fragment normal bends the screen-texture sample
// (cheap fake refraction), scaled by how shallow the water is. HIGH only.
uniform float refraction_strength = 0.04;

group_uniforms Shoreline_Cheap;
// The cheap, depth-INDEPENDENT shoreline used when the depth-texture path
// is compiled out.
//
// Rather than reading the depth buffer every frame to find out how far the
// sea floor is below each fragment, OceanSurface asks the terrain that same
// question ONCE, on the CPU, at mesh build time — one
// IslandTerrain.sample_height() call per ocean vertex — and bakes the answer
// into the mesh's vertex colours (red channel, normalised against
// shore_depth_reference below). The fragment stage then just reads the
// interpolated COLOR.r it was going to interpolate anyway. Per-fragment cost
// of the whole shoreline: one multiply. No texture read, no back-buffer
// copy, no depth copy.
//
// Honest limitations, both consequences of it being baked:
//  * It is STATIC. Real depth-buffer foam curls around anything the depth
//    pass drew — a boat, a villager the Hand dropped in the surf. This only
//    knows about the terrain, as it stood when the ocean was built.
//  * Its spatial resolution is the ocean mesh's vertex spacing (12.5 m per
//    quad on the low-spec path), so the shore band is a soft ~10 m gradient
//    rather than a crisp waterline. At god-view altitude that reads fine;
//    at a beach-level camera it would not.
// A mesh with no baked colours (a plain PlaneMesh, or no terrain found)
// gets white vertex colours, i.e. "deep everywhere" — no shore band at all,
// which is the correct, artifact-free fallback.
//
// Meters of water depth that COLOR.r == 1.0 represents. Must match
// OceanSurface.shore_depth_reference; vertex colour is 8-bit, so this also
// sets the quantisation (8 m / 255 = ~3 cm steps).
uniform float shore_depth_reference = 8.0;

group_uniforms Foam;
uniform vec4 foam_color : source_color = vec4(0.92, 0.96, 0.97, 1.0);
// Meters of water depth within which shoreline foam appears. Used by BOTH
// quality paths — the only difference is where the depth number came from
// (the depth buffer on HIGH, the baked vertex colour on the cheap path).
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
// Camera distances (m) over which the fbm micro-detail fades out and is
// then skipped entirely. Deliberately short: from god view the camera sits
// >130 m above the water, so this branch is never taken there, and it only
// costs anything if a future camera actually flies down to the surface.
uniform float detail_near = 30.0;
uniform float detail_far = 90.0;

group_uniforms Reflection;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.06;
uniform float fresnel_power = 5.0;
uniform vec3 fresnel_tint : source_color = vec3(0.75, 0.82, 0.86);

#ifdef OCEAN_HIGH_QUALITY
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
#endif

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

	// NOTE: the ocean's inland triangles are removed on the CPU, in
	// OceanSurface._bake_shore_mask(), not here. Two shader-side attempts are
	// recorded there and in this file's history: a fragment `discard`
	// (reproducibly crashed Godot 4.3 on Mesa lavapipe, signal 11) and
	// sinking inland vertices in VERTEX (worked, but left long visible skirt
	// triangles fanning down from the coastline). Dropping whole triangles at
	// bake time has neither problem and costs nothing per frame.

	v_world_xz = base_xz;
	v_wave_height_norm = clamp((displacement.y / max(crest_reference_height, 0.001)) * 0.5 + 0.5, 0.0, 1.0);
}

void fragment() {
	// shallow_mix: 0 = shallow water color, 1 = deep water color.
	// shore_foam: 0..1 mask of "foaming because something is just below me".
	// base_color: what the water sits on top of before foam/fresnel.
	float shallow_mix;
	float shore_foam;
	vec3 water_color;
	vec3 base_color;

#ifdef OCEAN_HIGH_QUALITY
	// --- expensive path: real scene depth + screen-space refraction ---
	float raw_depth = texture(depth_texture, SCREEN_UV).r;
	float scene_depth = linearize_depth(raw_depth, SCREEN_UV, INV_PROJECTION_MATRIX);
	float water_depth = -VERTEX.z;
	float depth_diff = max(scene_depth - water_depth, 0.0);

	shallow_mix = clamp(depth_diff / max(depth_fade_distance, 0.001), 0.0, 1.0);
	water_color = mix(color_shallow.rgb, color_deep.rgb, shallow_mix);

	vec2 refract_uv = clamp(SCREEN_UV + NORMAL.xz * refraction_strength * shallow_mix, vec2(0.001), vec2(0.999));
	vec3 refracted = texture(screen_texture, refract_uv).rgb;
	base_color = mix(refracted, water_color, clamp(shallow_mix * 1.4, 0.0, 1.0));

	shore_foam = 1.0 - smoothstep(0.0, foam_distance, depth_diff);
#else
	// --- cheap path: build-time-baked sea-floor depth, no screen or depth
	// reads. Deliberately the SAME arithmetic as the branch above, just fed
	// from COLOR.r instead of from the depth buffer, so the two paths are
	// tuned by the same uniforms and look like the same ocean.
	float depth_diff = COLOR.r * shore_depth_reference;

	shallow_mix = clamp(depth_diff / max(depth_fade_distance, 0.001), 0.0, 1.0);
	water_color = mix(color_shallow.rgb, color_deep.rgb, shallow_mix);
	// Nothing to refract without a screen copy: the water is simply opaque
	// coloured water. At god-view distance this is very close to what the
	// refraction path produced anyway, because the `shallow_mix * 1.4` blend
	// above saturates to 1.0 (pure water_color, no refracted contribution)
	// everywhere deeper than ~4.3 m — i.e. across almost the whole visible
	// sea. The refraction only ever showed up in the last few metres of
	// shallows, which is exactly where the surf is opaque with foam anyway.
	base_color = water_color;

	shore_foam = 1.0 - smoothstep(0.0, foam_distance, depth_diff);
#endif

	// Small procedural ripple detail (no external normal map — see docs).
	// `fbm()` is evaluated at full frequency per-fragment with no mip/LOD
	// concept of its own, so from a wide god-view distance (one fragment
	// covering many meters of world space) it aliases into a repeating,
	// tiled-looking pattern rather than a blur. `detail_fade` rolls the
	// micro-normal and foam-breakup terms down with distance to camera, and
	// the `if` below actually SKIPS the work rather than blending its result
	// away (mix(a, fbm(...), 0.0) still pays for fbm()).
	//
	// Fixed in the low-spec pass: this used to read
	// `length(VERTEX - CAMERA_POSITION_WORLD)`, mixing a VIEW-space VERTEX
	// (what a spatial shader's fragment stage always gets, regardless of
	// `world_vertex_coords`, which only affects the vertex stage) with a
	// WORLD-space camera position. That expression is not a distance to
	// anything. In view space the camera is at the origin, so the distance
	// to the camera is simply length(VERTEX).
	float dist_to_cam = length(VERTEX);
	float detail_fade = 1.0 - smoothstep(detail_near, detail_far, dist_to_cam);

	vec3 micro_n = vec3(0.0, 1.0, 0.0);
	float breakup = 1.0;
	if (detail_fade > 0.001) {
		vec2 e = vec2(0.08, 0.0);
		float n_c = fbm(v_world_xz * micro_normal_scale + TIME * 0.05, OCEAN_FBM_OCTAVES);
		float n_x = fbm((v_world_xz + e.xy) * micro_normal_scale + TIME * 0.05, OCEAN_FBM_OCTAVES);
		float n_z = fbm((v_world_xz + e.yx) * micro_normal_scale + TIME * 0.05, OCEAN_FBM_OCTAVES);
		micro_n = vec3(n_c - n_x, 1.0, n_c - n_z);
		breakup = fbm(v_world_xz * foam_noise_scale + TIME * 0.15, OCEAN_FBM_OCTAVES);
	}
	vec3 shaded_normal = normalize(NORMAL + micro_n * micro_normal_strength * detail_fade * vec3(1.0, 0.0, 1.0));

	float crest_foam = smoothstep(foam_crest_threshold, foam_crest_threshold + foam_crest_softness, v_wave_height_norm);
	float foam_mask = clamp(shore_foam + crest_foam, 0.0, 1.0);
	foam_mask *= mix(0.65, 1.0, mix(1.0, breakup, detail_fade));

	vec3 final_color = mix(base_color, foam_color.rgb, clamp(foam_mask, 0.0, 1.0));

	// fresnel responds to shaded_normal, which tilts through the same exact
	// six-wave periodic cycle everywhere on the plane — at the shallow,
	// distant grazing angles a wide god-view uses over hundreds of meters
	// of open water, that periodic tilt reads as a regular light/dark band
	// pattern. Capping the grazing-angle falloff distance itself softens
	// that periodic band into a gentler gradient without changing the
	// close-range fresnel rim ocean_demo.tscn was tuned against.
	float fresnel_dot = clamp(dot(shaded_normal, VIEW), mix(0.0, 0.25, 1.0 - detail_fade), 1.0);
	float fresnel = pow(1.0 - fresnel_dot, fresnel_power);
	final_color = mix(final_color, mix(final_color, fresnel_tint, 0.6), fresnel);

	// The analytic Gerstner normal is periodic by construction (six summed
	// sines), and specular response to a periodic normal at a grazing angle
	// aliases into a moire of bright flecks. Broadening effective roughness
	// with distance spreads the highlight instead of aliasing it.
	float distance_roughen = mix(0.5, 0.0, detail_fade);

	ALBEDO = final_color;
	NORMAL = shaded_normal;
	ROUGHNESS = clamp(mix(roughness_base, 0.85, foam_mask) + distance_roughen, 0.0, 1.0);
	METALLIC = 0.02;
	SPECULAR = mix(0.5, 0.1, foam_mask);
	// No ALPHA write — see the render_mode note at the top of this file.
}
