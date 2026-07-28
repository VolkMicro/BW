shader_type spatial;
// cull_disabled (not cull_back): a heightfield mesh is single-valued per
// (x,z) so it can never truly overhang, but ridged/high-frequency noise
// can still put a triangle's local slope near-vertical for a couple of
// grid cells at a time. From a normal outdoor camera angle those cells'
// winding-derived face normal can point just past horizontal, away from
// the camera, and cull_back would drop them — visible as small holes
// straight through to the sea/sky rather than a smoothly shaded steep
// slope. Terrain is cheap enough per-triangle that rendering both sides
// is the safe, standard fix (see world/terrain/island_generator.gd's
// blend-weight comment for the complementary fix: keeping slopes gentler
// in the first place).
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Naklon-reactive island terrain: triplanar-blended grass / rock / sand by
// world-space normal (slope) and height, re-balanced by `naklon_unit`.
//
// PUBLIC CONTRACT for package D (art direction) and anyone else driving this
// material at runtime:
//   uniform name: "naklon_unit", range 0..1, 0 = full Mercy, 1 = full
//   Cruelty (same convention as Naklon.unit() in core/naklon.gd — do not
//   re-invert it downstream). At 0, grass covers every slope below
//   rock_slope_start unless naturally steep; as it rises toward 1, grass
//   cover recedes and the same silhouette shows more bare, cracked rock
//   through cruelty_rock_bias, and the whole surface receives a burnt/ash
//   color tint. This is a look change only — it never changes the mesh or
//   collision, so gameplay logic reading terrain height is unaffected.
uniform float naklon_unit : hint_range(0.0, 1.0) = 0.0;

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

uniform float texture_scale = 0.08; // 1 / meters-per-tile
uniform float sand_height = 1.5; // meters above sea_level still counted as beach
uniform float rock_slope_start = 0.55; // dot(normal, up) below this = full rock
uniform float rock_slope_end = 0.35; // dot(normal, up) at/below this = still rock, no blend headroom left
uniform float blend_sharpness = 4.0; // triplanar axis-weight power
uniform float sea_level = 0.0;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec4 triplanar(sampler2D tex, vec3 world_pos, vec3 blend_w, float scale) {
	vec4 xz = texture(tex, world_pos.xz * scale);
	vec4 xy = texture(tex, world_pos.xy * scale);
	vec4 zy = texture(tex, world_pos.zy * scale);
	return xz * blend_w.y + xy * blend_w.z + zy * blend_w.x;
}

void fragment() {
	vec3 n = normalize(v_world_normal);
	vec3 blend_w = pow(abs(n), vec3(blend_sharpness));
	blend_w /= (blend_w.x + blend_w.y + blend_w.z + 0.00001);

	vec4 g_albedo = triplanar(grass_albedo, v_world_pos, blend_w, texture_scale);
	vec4 r_albedo = triplanar(rock_albedo, v_world_pos, blend_w, texture_scale);
	vec4 s_albedo = triplanar(sand_albedo, v_world_pos, blend_w, texture_scale);

	vec3 g_n = triplanar(grass_normal, v_world_pos, blend_w, texture_scale).rgb * 2.0 - 1.0;
	vec3 r_n = triplanar(rock_normal, v_world_pos, blend_w, texture_scale).rgb * 2.0 - 1.0;
	vec3 s_n = triplanar(sand_normal, v_world_pos, blend_w, texture_scale).rgb * 2.0 - 1.0;

	float g_rough = triplanar(grass_rough, v_world_pos, blend_w, texture_scale).r;
	float r_rough = triplanar(rock_rough, v_world_pos, blend_w, texture_scale).r;
	float s_rough = triplanar(sand_rough, v_world_pos, blend_w, texture_scale).r;

	// Slope mask: 1 = flat ground (grass-able), 0 = cliff face (rock only).
	float slope = clamp(smoothstep(rock_slope_end, rock_slope_start, n.y), 0.0, 1.0);
	// Beach mask: low and flat, near sea level.
	float beach = clamp(1.0 - (v_world_pos.y - sea_level) / max(sand_height, 0.001), 0.0, 1.0);
	beach *= slope; // steep faces never count as beach even at low elevation

	// Naklon reshapes ground cover on the same silhouette: near Cruelty,
	// grass recedes off shallow slopes into bare rock even where the terrain
	// itself hasn't changed shape.
	float cruelty_rock_bias = naklon_unit * 0.6;
	float grass_amount = clamp(slope - cruelty_rock_bias, 0.0, 1.0) * (1.0 - beach);
	float rock_amount = clamp(1.0 - grass_amount - beach, 0.0, 1.0);

	vec4 albedo = g_albedo * grass_amount + r_albedo * rock_amount + s_albedo * beach;
	vec3 normal_map = normalize(g_n * grass_amount + r_n * rock_amount + s_n * beach) * 0.5 + 0.5;
	float rough = g_rough * grass_amount + r_rough * rock_amount + s_rough * beach;

	// Mercy/Cruelty color grade on top of the blended albedo: rolling green
	// near Mercy, dry/ash-red near Cruelty. Multiplicative so the base scan
	// textures stay legible instead of being replaced by a flat tint.
	vec3 mercy_tint = vec3(0.85, 1.05, 0.85);
	vec3 cruelty_tint = vec3(0.95, 0.72, 0.62);
	vec3 tint = mix(mercy_tint, cruelty_tint, naklon_unit);
	albedo.rgb *= tint;

	ALBEDO = albedo.rgb;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	NORMAL_MAP = normal_map;
	NORMAL_MAP_DEPTH = 1.0;
}
