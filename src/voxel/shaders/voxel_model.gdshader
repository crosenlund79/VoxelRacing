// VoxelRacing: voxel models (cars, wheels, scenery props, bridge parts).
// Vertex colour = voxel colour (sRGB) with baked AO in alpha (VoxelMesher),
// UV.x = emissive kind (1 head lamp, 2 tail lamp, 3 lamp bulb), UV.y = glossy
// flag + 0.9 * per-voxel random, UV2 = corner of the voxel face (bevel).
// Built on the voxel_surface shader of SirensWentQuiet (to_linear, AO,
// bevel that fades out when voxels get small on screen).
shader_type spatial;
render_mode depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform float bevel = 0.28;
uniform vec3 head_color : source_color = vec3(1.0, 0.93, 0.74);
uniform vec3 tail_color : source_color = vec3(1.0, 0.1, 0.06);
uniform vec3 lamp_color : source_color = vec3(1.0, 0.84, 0.56);

instance uniform float head_glow = 0.0;
instance uniform float tail_glow = 0.0;
instance uniform float lamp_glow = 0.0;
instance uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
instance uniform vec4 head_tint : source_color = vec4(1.0, 0.93, 0.74, 1.0);
instance uniform float wear = 0.0;
// Wind sway of tall props: displacement (model units) at height 1 unit.
instance uniform float sway = 0.0;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void vertex() {
	if (sway > 0.0) {
		vec3 o = MODEL_MATRIX[3].xyz;
		float ph = o.x * 0.37 + o.z * 0.23;
		float h = max(VERTEX.y, 0.0);
		VERTEX.x += sin(TIME * 0.9 + ph) * sway * h * h;
		VERTEX.z += cos(TIME * 0.7 + ph * 1.3) * sway * 0.6 * h * h;
	}
}

void fragment() {
	vec3 c = to_linear(COLOR.rgb) * tint.rgb;
	float rnd = fract(UV.y) / 0.9;
	float glossy = step(1.0, UV.y);
	// soot and scuffs on damaged cars: darker voxels, chosen per voxel
	if (wear > 0.0) {
		float w = step(rnd, wear * 0.85);
		c = mix(c, c * vec3(0.32, 0.29, 0.27), w);
	}
	vec2 e2 = min(UV2, 1.0 - UV2);
	float edge = min(e2.x, e2.y);
	float px = length(fwidth(UV2));
	float show = 1.0 - smoothstep(0.35, 0.7, px);
	c *= 1.0 - bevel * show * (1.0 - smoothstep(0.0, 0.16, edge));
	// a soft highlight just inside the bevel: each voxel reads as a little block
	c *= 1.0 + 0.08 * show * smoothstep(0.1, 0.18, edge) * (1.0 - smoothstep(0.22, 0.34, edge));
	ALBEDO = c;
	AO = COLOR.a;
	AO_LIGHT_AFFECT = 0.55;
	ROUGHNESS = mix(0.82, 0.18, glossy);
	SPECULAR = mix(0.35, 0.75, glossy);
	METALLIC = 0.0;
	float kind = UV.x;
	vec3 em = vec3(0.0);
	if (kind > 0.5 && kind < 1.5) {
		em = to_linear(head_tint.rgb) * (0.35 + head_glow * 6.0);
	} else if (kind > 1.5 && kind < 2.5) {
		em = to_linear(tail_color) * (0.25 + tail_glow * 5.0);
	} else if (kind > 2.5) {
		em = to_linear(lamp_color) * (lamp_glow * 7.0);
	}
	EMISSION = em;
}
