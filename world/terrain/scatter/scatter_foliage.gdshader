// scatter_foliage.gdshader
//
// The one material shared (as three cheap duplicates) by every grass tuft,
// tree and boulder placed by world/terrain/scatter/terrain_scatter.gd.
//
// It is deliberately the cheapest thing that can still look like something:
//   * NO textures at all. Colour comes from the mesh's vertex colours, which
//     are already in the vertex stream — zero texture fetches per fragment,
//     which matters on a bandwidth-starved integrated GPU (see
//     docs/systems/performance_lowspec.md §2.4 for why fetches are the thing
//     to count on this hardware).
//   * `specular_disabled` + `diffuse_lambert`: leaves and rock do not need a
//     specular lobe or Burley's extra maths.
//   * `cull_back`, NOT `cull_disabled`. Grass blades are built as two
//     coincident triangles with opposite winding instead (see
//     scatter_meshes.gd). `cull_disabled` would make Godot flip the shading
//     normal on whichever face wins the depth test — the exact bug that cost
//     round four of the low-spec pass a long debugging session on the terrain
//     shader. Do not "simplify" this to cull_disabled.
//
// NAKLON REACTION. `naklon_unit` here is an ordinary per-material uniform,
// NOT the `global uniform` from shaders/naklon_globals.gdshaderinc. That is
// on purpose: the global one only exists if something has instanced
// shaders/naklon_shader_driver.gd, and nothing in world/god_view.tscn does.
// TerrainScatter pushes this uniform onto its three materials from
// Naklon.naklon_changed — three property writes per alignment change, no
// per-frame and no per-instance work. Below neutral (Mercy) nothing happens
// at all; past neutral the foliage desaturates toward ash.
//
// COLOR.a IS NOT OPACITY. This shader is opaque and never writes ALPHA. The
// alpha channel of the vertex colour is a wind sway mask baked by
// scatter_meshes.gd: 0 at a trunk base or anywhere on a rock, 1 at a grass
// tip. Set `wind_strength` to 0.0 to make the vertex stage a no-op.

shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

// 0.0 = full Mercy, 0.5 = neutral, 1.0 = full Cruelty. Mirrors Naklon.unit().
uniform float naklon_unit : hint_range(0.0, 1.0) = 0.5;
uniform vec3 ash_color : source_color = vec3(0.40, 0.37, 0.33);
uniform float ash_strength : hint_range(0.0, 1.0) = 0.85;
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.95;

// Wind. One sin + one cos per vertex, on the instance's own origin so a whole
// tuft/tree sways as one piece rather than shearing apart.
uniform float wind_strength = 0.06;
uniform float wind_speed = 1.3;

void vertex() {
	float sway = COLOR.a;
	if (wind_strength > 0.0) {
		vec3 origin = MODEL_MATRIX[3].xyz;
		float phase = TIME * wind_speed + origin.x * 0.21 + origin.z * 0.17;
		float amount = wind_strength * sway;
		VERTEX.x += sin(phase) * amount;
		VERTEX.z += cos(phase * 0.83) * amount * 0.6;
	}
}

void fragment() {
	vec3 base = COLOR.rgb;
	// Only the Cruelty half of the range does anything.
	float ash = clamp((naklon_unit - 0.5) * 2.0, 0.0, 1.0) * ash_strength;
	float lum = dot(base, vec3(0.299, 0.587, 0.114));
	vec3 dead = mix(vec3(lum), ash_color, 0.65) * 0.85;
	ALBEDO = mix(base, dead, ash);
	ROUGHNESS = surface_roughness;
	SPECULAR = 0.08;
}
