shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

// Ground-flush glowing ring for a village's Reach radius (see
// systems/faith/reach.gd, which documents this exact file as the
// territory-rendering answer to "no UI overlay for territory"). Color
// follows Naklon the same way the terrain material does: green-ish near
// Mercy, red-ish near Cruelty. See reach_border.gd for how the ring's
// inner/outer radius is kept in sync with Reach.radius_for_village().
uniform float naklon_unit : hint_range(0.0, 1.0) = 0.0;
uniform float pulse_speed = 1.2;

void fragment() {
	vec3 mercy_color = vec3(0.35, 0.9, 0.55);
	vec3 cruelty_color = vec3(0.95, 0.2, 0.15);
	vec3 col = mix(mercy_color, cruelty_color, naklon_unit);
	float pulse = 0.75 + 0.25 * sin(TIME * pulse_speed);
	ALBEDO = col;
	EMISSION = col * pulse * 1.5;
	ALPHA = 0.55;
}
