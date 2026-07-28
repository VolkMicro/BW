// TITHE & TERROR — shared water-shader math.
// Included by world/ocean/ocean.gdshader and world/ocean/river.gdshader.
// Deliberately contains ONLY pure helper functions (noise + depth
// reconstruction) and no uniform declarations — each including shader
// keeps its own uniform set (and its own local Gerstner wave-summation
// function, which references its own uniforms directly) so this file
// never has to guess another shader's array sizes or naming. See
// docs/systems/ocean.md for how the two shaders use these.

const float TAU_W = 6.28318530718;

// Cheap 2D hash -> [0,1], used as the noise lattice for value_noise/fbm.
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Smooth-interpolated value noise in [0,1].
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Fractal Brownian motion sum of value_noise, `octaves` fixed at the call
// site (always pass a literal, e.g. fbm(uv, 4)) to keep the loop trivial
// for the shader compiler.
float fbm(vec2 p, int octaves) {
	float value = 0.0;
	float amp = 0.5;
	for (int i = 0; i < octaves; i++) {
		value += amp * value_noise(p);
		p *= 2.02;
		amp *= 0.5;
	}
	return value;
}

// Reconstructs linear view-space depth (positive, meters from camera)
// from a raw DEPTH_TEXTURE sample. `inv_projection` is the fragment
// built-in INV_PROJECTION_MATRIX. Used for depth-fade foam/shallow-color
// blending against whatever the opaque pass drew (terrain, a boat, a
// dock) beneath the water surface.
float linearize_depth(float raw_depth, vec2 screen_uv, mat4 inv_projection) {
	vec3 ndc = vec3(screen_uv * 2.0 - 1.0, raw_depth);
	vec4 view = inv_projection * vec4(ndc, 1.0);
	view.xyz /= view.w;
	return -view.z;
}
