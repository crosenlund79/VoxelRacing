// VoxelRacing: soft voxel smoke and dust puffs (instanced, alpha-blended).
// INSTANCE_CUSTOM.g = opacity; the instance colour is the puff colour.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_lambert, specular_disabled;

varying float v_alpha;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void vertex() {
	v_alpha = INSTANCE_CUSTOM.g;
}

void fragment() {
	vec2 e2 = min(UV2, 1.0 - UV2);
	float edge = min(e2.x, e2.y);
	ALBEDO = to_linear(COLOR.rgb) * (0.9 + 0.1 * smoothstep(0.0, 0.2, edge));
	ALPHA = v_alpha * COLOR.a;
	ROUGHNESS = 1.0;
}
