shader_type spatial;
// cull_back, NOT cull_disabled — and the history matters, because the
// obvious-looking "safe" choice here is actively wrong.
//
// An earlier pass hit small holes punched through steep ridge slopes and
// "fixed" them by switching this to cull_disabled, reasoning that a
// heightfield can never truly overhang so rendering both sides is free
// safety. It is not free: with both sides drawn, a triangle's front and
// back faces land at the *exact same depth*, so which one survives the
// depth test is a coin flip — and Godot flips the shading normal to point
// DOWN on a back face. Wherever the back face won, the terrain was lit as
// if it were the underside of the world: no sun at all, sky ambient only.
// That is what made the whole island render as a flat dark blue-grey
// slab, and it survived every plausible-looking diagnosis (sun direction,
// shadows, ambient, tonemapping, fog, normal maps, the ocean) because
// none of those were the cause.
//
// Measured, same mesh, same white albedo, same light:
//   cull_back     -> (224, 230, 236)   correctly lit
//   cull_front    -> ( 85, 105, 136)   the flipped-normal underside
//   cull_disabled -> ( 85, 105, 136)   i.e. the underside was winning
//
// The winding produced by island_generator.gd's build_mesh() is correct
// (cull_back keeps the topside, which the measurement above confirms), and
// the original hole problem was independently and properly fixed at the
// source — lower ridge-noise weight plus the smoothing pass in
// _sample_grid(). Do not "fix" holes here again; fix the slopes instead.
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

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
	//
	// NOTE THE max(..., 0.0): Naklon.unit() returns 0.5 at NEUTRAL alignment,
	// not 0.0 (core/naklon.gd — it maps -1..1 onto 0..1). The original
	// `naklon_unit * 0.6` therefore stripped 0.3 off the grass mask before the
	// player had done anything at all, so a brand-new island opened as ~30%
	// bare rock and read grey. The shader's own header describes the intended
	// behaviour "at 0", i.e. it was written as though neutral were zero. A
	// neutral god should look out over a living green island; only a
	// deliberately cruel one earns bare stone. Cruelty still reaches the same
	// 0.6 maximum it always did, it just starts from neutral instead of from
	// full mercy.
	float cruelty_rock_bias = max(naklon_unit - 0.5, 0.0) * 1.2;
	float grass_amount = clamp(slope - cruelty_rock_bias, 0.0, 1.0) * (1.0 - beach);
	float rock_amount = clamp(1.0 - grass_amount - beach, 0.0, 1.0);

	vec4 albedo = g_albedo * grass_amount + r_albedo * rock_amount + s_albedo * beach;
	vec3 normal_map = normalize(g_n * grass_amount + r_n * rock_amount + s_n * beach) * 0.5 + 0.5;
	float rough = g_rough * grass_amount + r_rough * rock_amount + s_rough * beach;

	// Mercy/Cruelty color grade on top of the blended albedo: rolling green
	// near Mercy, dry/ash-red near Cruelty. Multiplicative so the base scan
	// textures stay legible instead of being replaced by a flat tint.
	//
	// Three-point, not two: a straight mix(mercy, cruelty, naklon_unit) puts
	// NEUTRAL (unit 0.5, see the note above) at the arithmetic midpoint of a
	// green and an ash-red, which is a desaturated grey-khaki — the colour of
	// nothing. That was half of why a fresh island looked lifeless. Neutral
	// now has its own authored anchor: a believable living green, with mercy
	// pushing it lusher and cruelty still reaching the same burnt end it did
	// before. Saturation is deliberately lifted at the green end because the
	// underlying scan (Grass004) is a muted real-world olive, and read from
	// god-view distance through fog it needs help to stay green rather than
	// silting up into grey.
	vec3 mercy_tint = vec3(0.72, 1.18, 0.62);
	vec3 neutral_tint = vec3(0.80, 1.10, 0.66);
	vec3 cruelty_tint = vec3(0.95, 0.72, 0.62);
	vec3 tint = naklon_unit < 0.5
		? mix(mercy_tint, neutral_tint, naklon_unit * 2.0)
		: mix(neutral_tint, cruelty_tint, (naklon_unit - 0.5) * 2.0);
	albedo.rgb *= tint;

	ALBEDO = albedo.rgb;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	NORMAL_MAP = normal_map;
	NORMAL_MAP_DEPTH = 1.0;
}
