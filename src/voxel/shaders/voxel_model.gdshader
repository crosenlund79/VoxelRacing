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
// Wind sway of tall props: displacement (model units) at height 1 unit.
instance uniform float sway = 0.0;
// P006 vehicle components (VoxelVehicle): UV.x = emit kind + 4 * component
// id. A set bit hides that component (it broke away), or shows it battered;
// 20 components per channel. `charred`: the burnt-out wreck after a blast.
instance uniform vec4 parts_gone = vec4(0.0);
instance uniform vec4 parts_hurt = vec4(0.0);
instance uniform float charred = 0.0;

varying float v_hurt;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

float part_bit(vec4 mask, int p) {
	int w = p / 20;
	float word = w == 0 ? mask.x : (w == 1 ? mask.y : (w == 2 ? mask.z : mask.w));
	return float((int(word + 0.5) >> (p - w * 20)) & 1);
}

void vertex() {
	v_hurt = 0.0;
	if (UV.x > 3.5) {
		int p = int(floor(UV.x * 0.25 + 0.01));
		if (part_bit(parts_gone, p) > 0.5) {
			VERTEX = vec3(0.0);
		}
		v_hurt = part_bit(parts_hurt, p);
	}
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
	if (v_hurt > 0.5) {  // battered: darker, scuffed to bare metal here and there
		c *= 0.8 + 0.1 * rnd;
		c = mix(c, vec3(0.24, 0.23, 0.22), step(0.9, rnd) * 0.55);
	}
	if (charred > 0.0) {
		c = mix(c, vec3(0.025, 0.022, 0.02) * (0.6 + 1.2 * rnd), charred * (0.7 + 0.3 * rnd));
	}
	float glossy = step(1.0, UV.y);
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
	float kind = mod(UV.x, 4.0);
	vec3 em = vec3(0.0);
	if (kind > 0.5 && kind < 1.5) {
		em = to_linear(head_tint.rgb) * (0.3 + head_glow * 3.2);
	} else if (kind > 1.5 && kind < 2.5) {
		em = to_linear(tail_color) * (0.3 + tail_glow * 3.6);
	} else if (kind > 2.5) {
		em = c * (lamp_glow * 6.0);  // glow voxels light up in their own colour
	}
	EMISSION = em * (1.0 - charred);
}
