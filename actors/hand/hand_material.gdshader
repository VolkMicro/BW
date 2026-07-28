shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Naklon-reactive skin for the Hand actor. Driven from actors/hand/hand.gd
// (which reads Naklon.unit() directly each physics frame — see
// docs/systems/hand.md for why this doesn't use a global shader uniform).
// -1 (mercy) -> mercy_color, +1 (cruelty) -> cruelty_color.

uniform vec4 mercy_color : source_color = vec4(0.82, 0.85, 0.92, 1.0);
uniform vec4 cruelty_color : source_color = vec4(0.34, 0.05, 0.07, 1.0);
uniform float naklon_unit : hint_range(0.0, 1.0) = 0.0;

// 0..1, how closed the fist currently is — used for a faint "effort" glow.
uniform float grip : hint_range(0.0, 1.0) = 0.0;

// 0..1, decaying flash when a grab is attempted outside Reach.
uniform float refusal : hint_range(0.0, 1.0) = 0.0;

// 0..1, smoothed "currently hovering outside any village's Reach" state —
// a constant desaturating/dimming cue, distinct from the sharp refusal
// flash, so the hand visibly "can't" rather than only flashing on click.
uniform float out_of_reach : hint_range(0.0, 1.0) = 0.0;

uniform float base_roughness : hint_range(0.0, 1.0) = 0.32;

void fragment() {
	vec3 base = mix(mercy_color.rgb, cruelty_color.rgb, naklon_unit);

	// Desaturate + darken toward grey when out of reach.
	float luma = dot(base, vec3(0.299, 0.587, 0.114));
	vec3 desaturated = mix(base, vec3(luma), out_of_reach * 0.85);
	vec3 dimmed = desaturated * (1.0 - out_of_reach * 0.35);

	vec3 emission_col = mix(vec3(0.5, 0.65, 0.9), vec3(0.9, 0.15, 0.1), naklon_unit);
	vec3 emission = emission_col * (0.04 + grip * 0.30) * (1.0 - out_of_reach * 0.6);

	// Sharp red refusal flash rides on top of everything else.
	vec3 albedo = mix(dimmed, vec3(1.0, 0.12, 0.08), refusal * 0.65);
	emission += vec3(1.0, 0.05, 0.05) * refusal * 1.3;

	ALBEDO = albedo;
	ROUGHNESS = base_roughness + out_of_reach * 0.4;
	METALLIC = 0.04;
	EMISSION = emission;
}
