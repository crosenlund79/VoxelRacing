// VoxelRacing: instanced voxel effects (debris, sparks, fire, stars).
// Mesh: one bevelled voxel (VoxelMesher, white, AO in alpha). The MultiMesh
// instance colour tints it (debris keeps the car's own voxel colours) and
// INSTANCE_CUSTOM.r makes it glow (sparks, fire, stars).
shader_type spatial;
render_mode depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform float bevel = 0.3;
uniform float glow = 6.0;

varying float v_emit;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void vertex() {
	v_emit = INSTANCE_CUSTOM.r;
}

void fragment() {
	vec3 c = to_linear(COLOR.rgb);
	vec2 e2 = min(UV2, 1.0 - UV2);
	float edge = min(e2.x, e2.y);
	float px = length(fwidth(UV2));
	float show = 1.0 - smoothstep(0.35, 0.8, px);
	c *= 1.0 - bevel * show * (1.0 - smoothstep(0.0, 0.18, edge));
	ALBEDO = c;
	AO = COLOR.a;
	ROUGHNESS = 0.75;
	SPECULAR = 0.4;
	EMISSION = c * v_emit * glow;
}
